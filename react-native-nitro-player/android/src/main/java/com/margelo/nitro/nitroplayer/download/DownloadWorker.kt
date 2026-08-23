package com.margelo.nitro.nitroplayer.download

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.margelo.nitro.nitroplayer.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * WorkManager worker for background downloads
 */
class DownloadWorker(
    private val context: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(context, workerParams) {
    companion object {
        const val KEY_DOWNLOAD_ID = "download_id"
        const val KEY_TRACK_ID = "track_id"
        const val KEY_TRACK_TITLE = "track_title"
        const val KEY_URL = "url"
        const val KEY_PLAYLIST_ID = "playlist_id"
        const val KEY_STORAGE_LOCATION = "storage_location"
        const val KEY_TRACK_JSON = "track_json"

        private const val NOTIFICATION_CHANNEL_ID = "nitro_player_downloads"
        private const val BASE_NOTIFICATION_ID = 2001
        private const val BUFFER_SIZE = 8192

        /**
         * Hard upper bound on a single download. Bounds runaway/trickling
         * downloads so the dataSync foreground service is always released
         * well within the Android 14+ FGS timeout window — otherwise the
         * system kills the app with ForegroundServiceDidNotStopInTimeException.
         */
        private const val MAX_DOWNLOAD_DURATION_MS = 30L * 60L * 1000L
        private val CONTENT_DISPOSITION_REGEX = Regex("filename=\"?([^\";]+)\"?")
    }

    private val downloadManager = DownloadManagerCore.getInstance(context)
    private val fileManager = DownloadFileManager.getInstance(context)
    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    /** Stable notification ID per download — derived from trackId hash. */
    private var notificationId = BASE_NOTIFICATION_ID

    override suspend fun doWork(): Result =
        withContext(Dispatchers.IO) {
            val downloadId = inputData.getString(KEY_DOWNLOAD_ID) ?: return@withContext Result.failure()
            val trackId = inputData.getString(KEY_TRACK_ID) ?: return@withContext Result.failure()
            val trackTitle = inputData.getString(KEY_TRACK_TITLE) ?: "Unknown track"
            val urlString = inputData.getString(KEY_URL) ?: return@withContext Result.failure()
            val storageLocationStr = inputData.getString(KEY_STORAGE_LOCATION) ?: StorageLocation.PRIVATE.name

            notificationId = BASE_NOTIFICATION_ID + trackId.hashCode().and(0xFFFF)

            val storageLocation =
                try {
                    StorageLocation.valueOf(storageLocationStr)
                } catch (e: Exception) {
                    StorageLocation.PRIVATE
                }

            try {
                // Set foreground notification — if POST_NOTIFICATIONS is denied,
                // WorkManager still runs the task; the notification just won't show.
                try {
                    setForeground(createForegroundInfo(trackTitle, 0, true))
                } catch (_: Exception) {
                    // Foreground promotion failed (e.g. missing permission on some OEMs).
                    // Download continues in background.
                }

                // Perform download, bounded so the foreground service is
                // always released within the Android 14+ FGS timeout window.
                val localPath =
                    withTimeout(MAX_DOWNLOAD_DURATION_MS) {
                        downloadFile(downloadId, trackId, trackTitle, urlString, storageLocation)
                    }

                if (localPath != null) {
                    val fallbackTrack = inputData.getString(KEY_TRACK_JSON)?.let { TrackItemJson.fromJson(it) }
                    downloadManager.onComplete(downloadId, trackId, localPath, fallbackTrack)
                    showCompletionNotification(trackTitle)
                    Result.success()
                } else {
                    val error =
                        DownloadError(
                            code = "DOWNLOAD_FAILED",
                            message = "Failed to download file",
                            reason = DownloadErrorReason.UNKNOWN,
                            isRetryable = true,
                        )
                    handleError(downloadId, trackId, trackTitle, error)
                }
            } catch (e: TimeoutCancellationException) {
                val error =
                    DownloadError(
                        code = "DOWNLOAD_TIMEOUT",
                        message = "Download exceeded maximum allowed duration",
                        reason = DownloadErrorReason.TIMEOUT,
                        isRetryable = true,
                    )
                handleError(downloadId, trackId, trackTitle, error)
            } catch (e: CancellationException) {
                // Worker stopped (pause/cancel) — state was already set by the
                // manager; don't overwrite it with FAILED.
                throw e
            } catch (e: Exception) {
                val errorReason =
                    when {
                        e.message?.contains("network", ignoreCase = true) == true -> DownloadErrorReason.NETWORK_ERROR
                        e.message?.contains("timeout", ignoreCase = true) == true -> DownloadErrorReason.TIMEOUT
                        e.message?.contains("space", ignoreCase = true) == true -> DownloadErrorReason.STORAGE_FULL
                        else -> DownloadErrorReason.UNKNOWN
                    }

                val error =
                    DownloadError(
                        code = e.javaClass.simpleName,
                        message = e.message ?: "Unknown error",
                        reason = errorReason,
                        isRetryable = errorReason in listOf(DownloadErrorReason.NETWORK_ERROR, DownloadErrorReason.TIMEOUT),
                    )
                handleError(downloadId, trackId, trackTitle, error)
            }
        }

    // Single retry owner: WorkManager reschedules via Result.retry(); the manager
    // only records state, never enqueues a competing request.
    private fun handleError(
        downloadId: String,
        trackId: String,
        trackTitle: String,
        error: DownloadError,
    ): Result {
        val willRetry = error.isRetryable && runAttemptCount < downloadManager.maxWorkerRetryAttempts()
        downloadManager.onError(downloadId, trackId, error, willRetry)
        showErrorNotification(trackTitle)
        return if (willRetry) Result.retry() else Result.failure()
    }

    private suspend fun downloadFile(
        downloadId: String,
        trackId: String,
        trackTitle: String,
        urlString: String,
        storageLocation: StorageLocation,
    ): String? =
        withContext(Dispatchers.IO) {
            var connection: HttpURLConnection? = null
            var inputStream: BufferedInputStream? = null
            var outputStream: FileOutputStream? = null
            var destinationFile: File? = null

            try {
                val partialPath = fileManager.getLocalPath(trackId)
                val existingBytes = partialPath?.let { File(it).length() } ?: 0L

                val url = URL(urlString)
                connection = url.openConnection() as HttpURLConnection
                connection.connectTimeout = 30000
                connection.readTimeout = 30000
                if (existingBytes > 0) {
                    connection.setRequestProperty("Range", "bytes=$existingBytes-")
                }
                connection.connect()

                val responseCode = connection.responseCode
                if (responseCode == 416) {
                    // Partial file is at or past the server's length — start clean next attempt
                    partialPath?.let { File(it).delete() }
                    throw Exception("Server returned HTTP 416 for resume, restarting download")
                }
                if (responseCode != HttpURLConnection.HTTP_OK && responseCode != HttpURLConnection.HTTP_PARTIAL) {
                    throw Exception("Server returned HTTP $responseCode")
                }
                val resuming = responseCode == HttpURLConnection.HTTP_PARTIAL && existingBytes > 0 && partialPath != null
                // Determine extension
                var extension = MimeTypeMap.getFileExtensionFromUrl(urlString)

                // 1. Try Content-Disposition
                if (extension.isNullOrEmpty()) {
                    val contentDisposition = connection.getHeaderField("Content-Disposition")
                    if (contentDisposition != null) {
                        val match = CONTENT_DISPOSITION_REGEX.find(contentDisposition)
                        if (match != null) {
                            val filename = match.groupValues[1]
                            extension = MimeTypeMap.getFileExtensionFromUrl(filename)
                        }
                    }
                }

                // 2. Try Content-Type
                if (extension.isNullOrEmpty()) {
                    val contentType = connection.contentType
                    if (contentType != null) {
                        val mimeType = contentType.split(";")[0].trim()
                        extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
                    }
                }

                val finalExtension = if (extension.isNullOrEmpty()) "mp3" else extension

                // Create destination file — appending to the partial file when the
                // server honored the Range request, truncating otherwise
                destinationFile =
                    if (resuming) {
                        File(partialPath!!)
                    } else {
                        fileManager.createDownloadFile(trackId, storageLocation, finalExtension)
                    }

                inputStream = BufferedInputStream(connection.inputStream)
                outputStream = FileOutputStream(destinationFile, resuming)

                val startOffset = if (resuming) existingBytes else 0L
                val totalBytes =
                    if (connection.contentLengthLong > 0) connection.contentLengthLong + startOffset else -1L
                var bytesDownloaded: Long = startOffset

                val buffer = ByteArray(BUFFER_SIZE)
                var bytesRead: Int
                var lastProgressUpdate = System.currentTimeMillis()

                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    // Blocking reads never suspend, so cancellation (pause/cancel,
                    // withTimeout, worker stop) must be checked explicitly here.
                    coroutineContext.ensureActive()
                    outputStream.write(buffer, 0, bytesRead)
                    bytesDownloaded += bytesRead

                    // Update progress every 250ms — both the callback and the notification
                    val now = System.currentTimeMillis()
                    if (now - lastProgressUpdate >= 250) {
                        downloadManager.onProgress(downloadId, trackId, bytesDownloaded, totalBytes)
                        val percent = if (totalBytes > 0) ((bytesDownloaded * 100) / totalBytes).toInt() else 0
                        updateProgressNotification(trackTitle, percent)
                        lastProgressUpdate = now
                    }
                }

                outputStream.flush()

                // Final progress update
                downloadManager.onProgress(downloadId, trackId, bytesDownloaded, totalBytes)

                destinationFile.absolutePath
            } catch (e: CancellationException) {
                // Keep the partial file — pause resumes from this offset via Range;
                // an explicit cancel deletes it in DownloadManagerCore.cancelDownload
                throw e
            } catch (e: Exception) {
                throw e
            } finally {
                try {
                    inputStream?.close()
                    outputStream?.close()
                    connection?.disconnect()
                } catch (e: Exception) {
                    // Ignore cleanup errors
                }
            }
        }

    // ── Notification helpers ──────────────────────────────────────────────

    private fun createForegroundInfo(
        trackTitle: String,
        percent: Int,
        indeterminate: Boolean,
    ): ForegroundInfo {
        ensureNotificationChannel()

        val notification = buildProgressNotification(trackTitle, percent, indeterminate)

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ForegroundInfo(
                notificationId,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(notificationId, notification)
        }
    }

    private fun buildProgressNotification(
        trackTitle: String,
        percent: Int,
        indeterminate: Boolean,
    ) = NotificationCompat
        .Builder(context, NOTIFICATION_CHANNEL_ID)
        .setContentTitle("Downloading")
        .setContentText(trackTitle)
        .setSubText(if (!indeterminate) "$percent%" else null)
        .setSmallIcon(android.R.drawable.stat_sys_download)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setProgress(100, percent, indeterminate)
        .build()

    private fun updateProgressNotification(trackTitle: String, percent: Int) {
        try {
            notificationManager.notify(
                notificationId,
                buildProgressNotification(trackTitle, percent, false),
            )
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted — download continues silently
        }
    }

    private fun showCompletionNotification(trackTitle: String) {
        try {
            notificationManager.notify(
                notificationId,
                NotificationCompat
                    .Builder(context, NOTIFICATION_CHANNEL_ID)
                    .setContentTitle("Download complete")
                    .setContentText(trackTitle)
                    .setSmallIcon(android.R.drawable.stat_sys_download_done)
                    .setAutoCancel(true)
                    .build(),
            )
        } catch (_: SecurityException) { }
    }

    private fun showErrorNotification(trackTitle: String) {
        try {
            notificationManager.notify(
                notificationId,
                NotificationCompat
                    .Builder(context, NOTIFICATION_CHANNEL_ID)
                    .setContentTitle("Download failed")
                    .setContentText(trackTitle)
                    .setSmallIcon(android.R.drawable.stat_notify_error)
                    .setAutoCancel(true)
                    .build(),
            )
        } catch (_: SecurityException) { }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "Downloads",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Download progress notifications"
                }
            notificationManager.createNotificationChannel(channel)
        }
    }
}
