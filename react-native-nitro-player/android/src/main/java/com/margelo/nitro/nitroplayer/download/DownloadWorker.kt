package com.margelo.nitro.nitroplayer.download

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import android.webkit.MimeTypeMap
import com.margelo.nitro.nitroplayer.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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
        const val KEY_URL = "url"
        const val KEY_PLAYLIST_ID = "playlist_id"
        const val KEY_STORAGE_LOCATION = "storage_location"

        private const val NOTIFICATION_CHANNEL_ID = "nitro_player_downloads"
        private const val NOTIFICATION_ID = 2001
        private const val BUFFER_SIZE = 8192
    }

    private val downloadManager = DownloadManagerCore.getInstance(context)
    private val fileManager = DownloadFileManager.getInstance(context)

    override suspend fun doWork(): Result =
        withContext(Dispatchers.IO) {
            val downloadId = inputData.getString(KEY_DOWNLOAD_ID) ?: return@withContext Result.failure()
            val trackId = inputData.getString(KEY_TRACK_ID) ?: return@withContext Result.failure()
            val urlString = inputData.getString(KEY_URL) ?: return@withContext Result.failure()
            val storageLocationStr = inputData.getString(KEY_STORAGE_LOCATION) ?: StorageLocation.PRIVATE.name

            val storageLocation =
                try {
                    StorageLocation.valueOf(storageLocationStr)
                } catch (e: Exception) {
                    StorageLocation.PRIVATE
                }

            try {
                // Set foreground notification
                setForeground(createForegroundInfo(trackId))

                // Perform download
                val localPath = downloadFile(downloadId, trackId, urlString, storageLocation)

                if (localPath != null) {
                    downloadManager.onComplete(downloadId, trackId, localPath)
                    Result.success()
                } else {
                    val error =
                        DownloadError(
                            code = "DOWNLOAD_FAILED",
                            message = "Failed to download file",
                            reason = DownloadErrorReason.UNKNOWN,
                            isRetryable = true,
                        )
                    downloadManager.onError(downloadId, trackId, error)
                    Result.retry()
                }
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
                downloadManager.onError(downloadId, trackId, error)

                if (error.isRetryable) {
                    Result.retry()
                } else {
                    Result.failure()
                }
            }
        }

    private suspend fun downloadFile(
        downloadId: String,
        trackId: String,
        urlString: String,
        storageLocation: StorageLocation,
    ): String? =
        withContext(Dispatchers.IO) {
            var connection: HttpURLConnection? = null
            var inputStream: BufferedInputStream? = null
            var outputStream: FileOutputStream? = null

            try {
                val url = URL(urlString)
                connection = url.openConnection() as HttpURLConnection
                connection.connectTimeout = 30000
                connection.readTimeout = 30000
                connection.connect()

                val responseCode = connection.responseCode
                if (responseCode != HttpURLConnection.HTTP_OK) {
                    throw Exception("Server returned HTTP $responseCode")
                }
                // Determine extension
                var extension = MimeTypeMap.getFileExtensionFromUrl(urlString)

                // 1. Try Content-Disposition
                if (extension.isNullOrEmpty()) {
                    val contentDisposition = connection.getHeaderField("Content-Disposition")
                    if (contentDisposition != null) {
                        val match = Regex("filename=\"?([^\";]+)\"?").find(contentDisposition)
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


                // Create destination file
                val destinationFile = fileManager.createDownloadFile(trackId, storageLocation, finalExtension)

                inputStream = BufferedInputStream(connection.inputStream)
                outputStream = FileOutputStream(destinationFile)

                val totalBytes = connection.contentLengthLong
                var bytesDownloaded: Long = 0

                val buffer = ByteArray(BUFFER_SIZE)
                var bytesRead: Int
                var lastProgressUpdate = System.currentTimeMillis()

                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    outputStream.write(buffer, 0, bytesRead)
                    bytesDownloaded += bytesRead

                    // Update progress every 250ms
                    val now = System.currentTimeMillis()
                    if (now - lastProgressUpdate >= 250) {
                        downloadManager.onProgress(downloadId, trackId, bytesDownloaded, totalBytes)
                        lastProgressUpdate = now
                    }
                }

                outputStream.flush()

                // Final progress update
                downloadManager.onProgress(downloadId, trackId, bytesDownloaded, totalBytes)

                destinationFile.absolutePath
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

    private fun createForegroundInfo(trackId: String): ForegroundInfo {
        createNotificationChannel()

        val notification =
            NotificationCompat
                .Builder(context, NOTIFICATION_CHANNEL_ID)
                .setContentTitle("Downloading")
                .setContentText("Downloading track...")
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setOngoing(true)
                .setProgress(100, 0, true)
                .build()

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ForegroundInfo(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "Downloads",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Download progress notifications"
                }

            val notificationManager = context.getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }
}
