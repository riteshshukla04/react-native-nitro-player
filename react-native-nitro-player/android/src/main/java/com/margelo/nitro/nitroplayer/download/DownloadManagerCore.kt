package com.margelo.nitro.nitroplayer.download

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.*
import com.margelo.nitro.core.NullType
import com.margelo.nitro.nitroplayer.*
import com.margelo.nitro.nitroplayer.core.ListenerRegistry
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Core download manager using WorkManager for background downloads
 */
class DownloadManagerCore private constructor(
    private val context: Context,
) {
    companion object {
        private const val TAG = "DownloadManagerCore"

        @Volatile
        private var instance: DownloadManagerCore? = null

        fun getInstance(context: Context): DownloadManagerCore =
            instance ?: synchronized(this) {
                instance ?: DownloadManagerCore(context.applicationContext).also { instance = it }
            }

        private val ACTIVE_STATES = setOf(DownloadState.DOWNLOADING, DownloadState.PENDING, DownloadState.PAUSED)
    }

    // Configuration
    private var config: DownloadConfig =
        DownloadConfig(
            storageLocation = StorageLocation.PRIVATE,
            maxConcurrentDownloads = 3.0,
            autoRetry = true,
            maxRetryAttempts = 3.0,
            backgroundDownloadsEnabled = true,
            downloadArtwork = true,
            customDownloadPath = null,
            wifiOnlyDownloads = false,
        )

    private var playbackSourcePreference: PlaybackSource = PlaybackSource.AUTO

    // Download tracking
    private val activeTasks = ConcurrentHashMap<String, DownloadTaskMetadata>()
    private val trackMetadata = ConcurrentHashMap<String, TrackItem>()
    private val playlistAssociations = ConcurrentHashMap<String, String>()

    // Callbacks — ListenerRegistry so HybridDownloadManager.dispose can remove
    // them instead of leaking closures into dead JS runtimes across reloads
    private val progressCallbacks = ListenerRegistry<(DownloadProgress) -> Unit>()
    private val stateChangeCallbacks = ListenerRegistry<(String, String, DownloadState, DownloadError?) -> Unit>()
    private val completeCallbacks = ListenerRegistry<(DownloadedTrack) -> Unit>()

    private val mainHandler = Handler(Looper.getMainLooper())
    private val database = DownloadDatabase.getInstance(context)
    private val fileManager = DownloadFileManager.getInstance(context)

    // WorkManager
    private val workManager = WorkManager.getInstance(context)

    // Configuration
    fun configure(config: DownloadConfig) {
        this.config = config
    }

    fun getConfig(): DownloadConfig = config

    // Download Operations
    fun downloadTrack(
        track: TrackItem,
        playlistId: String?,
    ): String {
        val downloadId = UUID.randomUUID().toString()

        // Store track metadata
        trackMetadata[track.id] = track

        // Store playlist association if provided
        playlistId?.let {
            playlistAssociations[downloadId] = it
        }

        // Create download task metadata
        val metadata =
            DownloadTaskMetadata(
                downloadId = downloadId,
                trackId = track.id,
                playlistId = playlistId,
                state = DownloadState.PENDING,
                createdAt = System.currentTimeMillis().toDouble(),
                retryCount = 0,
            )
        activeTasks[downloadId] = metadata

        // Gate on maxConcurrentDownloads — excess requests wait in FIFO order
        synchronized(launchGate) {
            if (runningDownloads.size >= maxConcurrent()) {
                pendingLaunchQueue.add(downloadId)
            } else {
                runningDownloads.add(downloadId)
                enqueueDownloadWork(downloadId, track, playlistId)
            }
        }

        // Update state
        activeTasks[downloadId]?.state = DownloadState.PENDING
        notifyStateChange(downloadId, track.id, DownloadState.PENDING, null)

        return downloadId
    }

    private val launchGate = Any()
    private val pendingLaunchQueue = ArrayDeque<String>()
    private val runningDownloads = mutableSetOf<String>()

    private fun maxConcurrent(): Int = (config.maxConcurrentDownloads?.toInt() ?: 3).coerceAtLeast(1)

    private fun enqueueDownloadWork(
        downloadId: String,
        track: TrackItem,
        playlistId: String?,
    ) {
        val constraints =
            Constraints
                .Builder()
                .setRequiredNetworkType(
                    if (config.wifiOnlyDownloads == true) NetworkType.UNMETERED else NetworkType.CONNECTED,
                ).setRequiresStorageNotLow(true)
                .build()

        val inputData =
            workDataOf(
                DownloadWorker.KEY_DOWNLOAD_ID to downloadId,
                DownloadWorker.KEY_TRACK_ID to track.id,
                DownloadWorker.KEY_TRACK_TITLE to track.title,
                DownloadWorker.KEY_URL to track.url,
                DownloadWorker.KEY_PLAYLIST_ID to (playlistId ?: ""),
                DownloadWorker.KEY_STORAGE_LOCATION to (config.storageLocation?.name ?: StorageLocation.PRIVATE.name),
                DownloadWorker.KEY_TRACK_JSON to TrackItemJson.toJson(track),
            )

        val downloadRequest =
            OneTimeWorkRequestBuilder<DownloadWorker>()
                .setConstraints(constraints)
                .setInputData(inputData)
                .addTag("download_$downloadId")
                .addTag("track_${track.id}")
                .build()

        workManager.enqueueUniqueWork("download_$downloadId", ExistingWorkPolicy.KEEP, downloadRequest)
    }

    // Frees this download's concurrency slot and launches the next queued one
    private fun releaseDownloadSlot(downloadId: String) {
        var next: String? = null
        synchronized(launchGate) {
            runningDownloads.remove(downloadId)
            pendingLaunchQueue.remove(downloadId)
            if (runningDownloads.size < maxConcurrent()) {
                next = pendingLaunchQueue.pollFirst()
                next?.let { runningDownloads.add(it) }
            }
        }
        next?.let { nextId ->
            val meta = activeTasks[nextId] ?: return
            val track = trackMetadata[meta.trackId] ?: return
            enqueueDownloadWork(nextId, track, playlistAssociations[nextId])
        }
    }

    fun downloadPlaylist(
        playlistId: String,
        tracks: Array<TrackItem>,
    ): Array<String> =
        tracks
            .map { track ->
                downloadTrack(track, playlistId)
            }.toTypedArray()

    // Download Control
    fun pauseDownload(downloadId: String) {
        workManager.cancelAllWorkByTag("download_$downloadId")
        activeTasks[downloadId]?.let { metadata ->
            metadata.state = DownloadState.PAUSED
            notifyStateChange(downloadId, metadata.trackId, DownloadState.PAUSED, null)
        }
        releaseDownloadSlot(downloadId)
    }

    fun resumeDownload(downloadId: String) {
        activeTasks[downloadId]?.let { metadata ->
            val track = trackMetadata[metadata.trackId] ?: return
            val playlistId = playlistAssociations[downloadId]

            synchronized(launchGate) {
                if (runningDownloads.size >= maxConcurrent() && downloadId !in runningDownloads) {
                    pendingLaunchQueue.add(downloadId)
                    metadata.state = DownloadState.PENDING
                    notifyStateChange(downloadId, metadata.trackId, DownloadState.PENDING, null)
                    return
                }
                runningDownloads.add(downloadId)
            }
            enqueueDownloadWork(downloadId, track, playlistId)

            metadata.state = DownloadState.DOWNLOADING
            notifyStateChange(downloadId, metadata.trackId, DownloadState.DOWNLOADING, null)
        }
    }

    fun cancelDownload(downloadId: String) {
        workManager.cancelAllWorkByTag("download_$downloadId")
        activeTasks[downloadId]?.let { metadata ->
            metadata.state = DownloadState.CANCELLED
            notifyStateChange(downloadId, metadata.trackId, DownloadState.CANCELLED, null)
            activeTasks.remove(downloadId)
            // Drop the partial file (pause keeps it for Range resume), but never
            // a previously completed download's file
            if (!database.isTrackDownloaded(metadata.trackId)) {
                fileManager.getLocalPath(metadata.trackId)?.let { fileManager.deleteFile(it) }
            }
        }
        releaseDownloadSlot(downloadId)
    }

    fun retryDownload(downloadId: String) {
        activeTasks[downloadId]?.let { metadata ->
            metadata.retryCount++
            metadata.error = null
            resumeDownload(downloadId)
        }
    }

    fun pauseAllDownloads() {
        activeTasks.keys.forEach { pauseDownload(it) }
    }

    fun resumeAllDownloads() {
        activeTasks.filter { it.value.state == DownloadState.PAUSED }.keys.forEach { resumeDownload(it) }
    }

    fun cancelAllDownloads() {
        activeTasks.keys.forEach { cancelDownload(it) }
    }

    // Download Status
    fun getDownloadTask(downloadId: String): DownloadTask? = activeTasks[downloadId]?.toDownloadTask()

    fun getActiveDownloads(): Array<DownloadTask> =
        activeTasks.values
            .filter { it.state in ACTIVE_STATES }
            .map { it.toDownloadTask() }
            .toTypedArray()

    fun getQueueStatus(): DownloadQueueStatus {
        var pendingCount = 0
        var activeCount = 0
        var failedCount = 0
        var totalBytes = 0.0
        var downloadedBytes = 0.0

        for (m in activeTasks.values) {
            when (m.state) {
                DownloadState.PENDING -> {
                    pendingCount++
                }

                DownloadState.DOWNLOADING -> {
                    activeCount++
                }

                DownloadState.FAILED -> {
                    failedCount++
                }

                else -> {}
            }
            totalBytes += m.totalBytes ?: 0.0
            downloadedBytes += m.bytesDownloaded
        }

        val completedCount = database.countDownloadedTracks()

        return DownloadQueueStatus(
            pendingCount = pendingCount.toDouble(),
            activeCount = activeCount.toDouble(),
            completedCount = completedCount.toDouble(),
            failedCount = failedCount.toDouble(),
            totalBytesToDownload = totalBytes,
            totalBytesDownloaded = downloadedBytes,
            overallProgress = if (totalBytes > 0) downloadedBytes / totalBytes else 0.0,
        )
    }

    fun isDownloading(trackId: String): Boolean = activeTasks.values.any { it.trackId == trackId && it.state == DownloadState.DOWNLOADING }

    fun getDownloadState(trackId: String): DownloadState {
        activeTasks.values.find { it.trackId == trackId }?.let {
            return it.state
        }
        if (database.isTrackDownloaded(trackId)) {
            return DownloadState.COMPLETED
        }
        return DownloadState.PENDING
    }

    // Downloaded Content Queries
    fun isTrackDownloaded(trackId: String): Boolean = database.isTrackDownloaded(trackId)

    fun isPlaylistDownloaded(playlistId: String): Boolean = database.isPlaylistDownloaded(playlistId)

    fun isPlaylistPartiallyDownloaded(playlistId: String): Boolean = database.isPlaylistPartiallyDownloaded(playlistId)

    fun getDownloadedTrack(trackId: String): DownloadedTrack? = database.getDownloadedTrack(trackId)

    fun getAllDownloadedTracks(): Array<DownloadedTrack> = database.getAllDownloadedTracks().toTypedArray()

    fun getDownloadedPlaylist(playlistId: String): DownloadedPlaylist? = database.getDownloadedPlaylist(playlistId)

    fun getAllDownloadedPlaylists(): Array<DownloadedPlaylist> = database.getAllDownloadedPlaylists().toTypedArray()

    fun getLocalPath(trackId: String): String? = database.getDownloadedTrack(trackId)?.localPath

    // Deletion
    fun deleteDownloadedTrack(trackId: String) = database.deleteDownloadedTrack(trackId)

    fun deleteDownloadedPlaylist(playlistId: String) = database.deleteDownloadedPlaylist(playlistId)

    fun deleteAllDownloads() = database.deleteAllDownloads()

    // Storage
    fun getStorageInfo(): DownloadStorageInfo = fileManager.getStorageInfo()

    /** Validates all downloads and cleans up orphaned records */
    fun syncDownloads(): Int {
        val removedCount = database.syncDownloads()
        val bytesFreed = fileManager.cleanupOrphanedFiles(database.getAllDownloadedTracks().map { it.trackId }.toSet())
        NitroPlayerLogger.log("DownloadManagerCore", "syncDownloads: removed $removedCount orphaned records, freed $bytesFreed bytes")
        return removedCount
    }

    // Playback Source Preference
    fun setPlaybackSourcePreference(preference: PlaybackSource) {
        playbackSourcePreference = preference
    }

    fun getPlaybackSourcePreference(): PlaybackSource = playbackSourcePreference

    fun getEffectiveUrl(track: TrackItem): String =
        when (playbackSourcePreference) {
            PlaybackSource.NETWORK -> track.url
            PlaybackSource.DOWNLOAD -> getLocalPath(track.id) ?: track.url
            PlaybackSource.AUTO -> getLocalPath(track.id) ?: track.url
        }

    // Callbacks
    fun addProgressCallback(callback: (DownloadProgress) -> Unit): Long = progressCallbacks.add(callback)

    fun removeProgressCallback(id: Long): Boolean = progressCallbacks.remove(id)

    fun addStateChangeCallback(callback: (String, String, DownloadState, DownloadError?) -> Unit): Long = stateChangeCallbacks.add(callback)

    fun removeStateChangeCallback(id: Long): Boolean = stateChangeCallbacks.remove(id)

    fun addCompleteCallback(callback: (DownloadedTrack) -> Unit): Long = completeCallbacks.add(callback)

    fun removeCompleteCallback(id: Long): Boolean = completeCallbacks.remove(id)

    // Internal callbacks from DownloadWorker
    internal fun onProgress(
        downloadId: String,
        trackId: String,
        bytesDownloaded: Long,
        totalBytes: Long,
    ) {
        activeTasks[downloadId]?.let { metadata ->
            metadata.bytesDownloaded = bytesDownloaded.toDouble()
            metadata.totalBytes = totalBytes.toDouble()
            metadata.state = DownloadState.DOWNLOADING
        }

        val progress =
            DownloadProgress(
                trackId = trackId,
                downloadId = downloadId,
                bytesDownloaded = bytesDownloaded.toDouble(),
                totalBytes = totalBytes.toDouble(),
                progress = if (totalBytes > 0) bytesDownloaded.toDouble() / totalBytes.toDouble() else 0.0,
                state = DownloadState.DOWNLOADING,
            )

        mainHandler.post {
            progressCallbacks.forEach { it(progress) }
        }
    }

    internal fun onComplete(
        downloadId: String,
        trackId: String,
        localPath: String,
        fallbackTrack: TrackItem? = null,
    ) {
        // fallbackTrack comes from the worker's persisted inputData — the
        // in-memory maps are empty when the worker completes in a fresh process.
        val track = trackMetadata[trackId] ?: fallbackTrack ?: return
        val playlistId = playlistAssociations[downloadId]
        val storageLocation = config.storageLocation ?: StorageLocation.PRIVATE
        val fileSize = fileManager.getFileSize(localPath)

        val downloadedTrack =
            DownloadedTrack(
                trackId = trackId,
                originalTrack = track,
                localPath = localPath,
                localArtworkPath = null,
                downloadedAt = System.currentTimeMillis().toDouble(),
                fileSize = fileSize.toDouble(),
                storageLocation = storageLocation,
            )

        database.saveDownloadedTrack(downloadedTrack, playlistId)

        activeTasks[downloadId]?.let { metadata ->
            metadata.state = DownloadState.COMPLETED
            metadata.completedAt = System.currentTimeMillis().toDouble()
        }
        activeTasks.remove(downloadId)
        releaseDownloadSlot(downloadId)

        notifyStateChange(downloadId, trackId, DownloadState.COMPLETED, null)

        mainHandler.post {
            completeCallbacks.forEach { it(downloadedTrack) }
        }
    }

    // Retries are owned by WorkManager (Result.retry in DownloadWorker); this
    // only records state so a second, competing worker is never scheduled here.
    internal fun onError(
        downloadId: String,
        trackId: String,
        error: DownloadError,
        willRetry: Boolean = false,
    ) {
        activeTasks[downloadId]?.let { metadata ->
            metadata.error = error

            if (willRetry) {
                metadata.retryCount++
                metadata.state = DownloadState.PENDING
            } else {
                metadata.state = DownloadState.FAILED
                notifyStateChange(downloadId, trackId, DownloadState.FAILED, error)
                releaseDownloadSlot(downloadId)
            }
        }
    }

    internal fun maxWorkerRetryAttempts(): Int =
        if (config.autoRetry == true) (config.maxRetryAttempts?.toInt() ?: 3) else 0

    private fun notifyStateChange(
        downloadId: String,
        trackId: String,
        state: DownloadState,
        error: DownloadError?,
    ) {
        mainHandler.post {
            stateChangeCallbacks.forEach { it(downloadId, trackId, state, error) }
        }
    }
}

// Internal metadata class
internal data class DownloadTaskMetadata(
    val downloadId: String,
    val trackId: String,
    val playlistId: String?,
    var state: DownloadState,
    val createdAt: Double,
    var startedAt: Double? = null,
    var completedAt: Double? = null,
    var retryCount: Int = 0,
    var bytesDownloaded: Double = 0.0,
    var totalBytes: Double? = null,
    var error: DownloadError? = null,
) {
    fun toDownloadTask(): DownloadTask {
        val progress =
            DownloadProgress(
                trackId = trackId,
                downloadId = downloadId,
                bytesDownloaded = bytesDownloaded,
                totalBytes = totalBytes ?: 0.0,
                progress = if (totalBytes != null && totalBytes!! > 0) bytesDownloaded / totalBytes!! else 0.0,
                state = state,
            )

        val playlistIdVariant =
            if (playlistId != null) {
                Variant_NullType_String.create(playlistId)
            } else {
                null
            }

        // Copy to local val to avoid smart cast issues
        val localStartedAt = startedAt
        val startedAtVariant =
            if (localStartedAt != null) {
                Variant_NullType_Double.create(localStartedAt)
            } else {
                null
            }

        val localCompletedAt = completedAt
        val completedAtVariant =
            if (localCompletedAt != null) {
                Variant_NullType_Double.create(localCompletedAt)
            } else {
                null
            }

        val localError = error
        val errorVariant =
            if (localError != null) {
                Variant_NullType_DownloadError.create(localError)
            } else {
                null
            }

        return DownloadTask(
            downloadId = downloadId,
            trackId = trackId,
            playlistId = playlistIdVariant,
            state = state,
            progress = progress,
            createdAt = createdAt,
            startedAt = startedAtVariant,
            completedAt = completedAtVariant,
            error = errorVariant,
            retryCount = retryCount.toDouble(),
        )
    }
}
