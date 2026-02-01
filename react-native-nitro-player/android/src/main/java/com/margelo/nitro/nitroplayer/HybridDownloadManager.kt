package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.NullType
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.download.DownloadManagerCore

/**
 * Hybrid implementation of DownloadManagerSpec for Android
 * Bridges Nitro modules with the native DownloadManagerCore implementation
 */
@DoNotStrip
@Keep
class HybridDownloadManager : HybridDownloadManagerSpec() {
    private val core: DownloadManagerCore

    init {
        val context =
            NitroModules.applicationContext
                ?: throw IllegalStateException("React Context is not initialized")
        core = DownloadManagerCore.getInstance(context)
    }

    // Configuration
    @DoNotStrip
    @Keep
    override fun configure(config: DownloadConfig) {
        core.configure(config)
    }

    @DoNotStrip
    @Keep
    override fun getConfig(): DownloadConfig = core.getConfig()

    // Download Operations
    override fun downloadTrack(
        track: TrackItem,
        playlistId: String?,
    ): Promise<String> =
        Promise.async {
            core.downloadTrack(track, playlistId)
        }

    override fun downloadPlaylist(
        playlistId: String,
        tracks: Array<TrackItem>,
    ): Promise<Array<String>> =
        Promise.async {
            core.downloadPlaylist(playlistId, tracks)
        }

    // Download Control
    override fun pauseDownload(downloadId: String): Promise<Unit> =
        Promise.async {
            core.pauseDownload(downloadId)
        }

    override fun resumeDownload(downloadId: String): Promise<Unit> =
        Promise.async {
            core.resumeDownload(downloadId)
        }

    override fun cancelDownload(downloadId: String): Promise<Unit> =
        Promise.async {
            core.cancelDownload(downloadId)
        }

    override fun retryDownload(downloadId: String): Promise<Unit> =
        Promise.async {
            core.retryDownload(downloadId)
        }

    override fun pauseAllDownloads(): Promise<Unit> =
        Promise.async {
            core.pauseAllDownloads()
        }

    override fun resumeAllDownloads(): Promise<Unit> =
        Promise.async {
            core.resumeAllDownloads()
        }

    override fun cancelAllDownloads(): Promise<Unit> =
        Promise.async {
            core.cancelAllDownloads()
        }

    // Download Status
    @DoNotStrip
    @Keep
    override fun getDownloadTask(downloadId: String): Variant_NullType_DownloadTask {
        val task = core.getDownloadTask(downloadId)
        return if (task != null) {
            Variant_NullType_DownloadTask.create(task)
        } else {
            Variant_NullType_DownloadTask.create(NullType.NULL)
        }
    }

    @DoNotStrip
    @Keep
    override fun getActiveDownloads(): Array<DownloadTask> = core.getActiveDownloads()

    @DoNotStrip
    @Keep
    override fun getQueueStatus(): DownloadQueueStatus = core.getQueueStatus()

    @DoNotStrip
    @Keep
    override fun isDownloading(trackId: String): Boolean = core.isDownloading(trackId)

    @DoNotStrip
    @Keep
    override fun getDownloadState(trackId: String): DownloadState = core.getDownloadState(trackId)

    // Downloaded Content Queries
    @DoNotStrip
    @Keep
    override fun isTrackDownloaded(trackId: String): Boolean = core.isTrackDownloaded(trackId)

    @DoNotStrip
    @Keep
    override fun isPlaylistDownloaded(playlistId: String): Boolean = core.isPlaylistDownloaded(playlistId)

    @DoNotStrip
    @Keep
    override fun isPlaylistPartiallyDownloaded(playlistId: String): Boolean = core.isPlaylistPartiallyDownloaded(playlistId)

    @DoNotStrip
    @Keep
    override fun getDownloadedTrack(trackId: String): Variant_NullType_DownloadedTrack {
        val track = core.getDownloadedTrack(trackId)
        return if (track != null) {
            Variant_NullType_DownloadedTrack.create(track)
        } else {
            Variant_NullType_DownloadedTrack.create(NullType.NULL)
        }
    }

    @DoNotStrip
    @Keep
    override fun getAllDownloadedTracks(): Array<DownloadedTrack> = core.getAllDownloadedTracks()

    @DoNotStrip
    @Keep
    override fun getDownloadedPlaylist(playlistId: String): Variant_NullType_DownloadedPlaylist {
        val playlist = core.getDownloadedPlaylist(playlistId)
        return if (playlist != null) {
            Variant_NullType_DownloadedPlaylist.create(playlist)
        } else {
            Variant_NullType_DownloadedPlaylist.create(NullType.NULL)
        }
    }

    @DoNotStrip
    @Keep
    override fun getAllDownloadedPlaylists(): Array<DownloadedPlaylist> = core.getAllDownloadedPlaylists()

    @DoNotStrip
    @Keep
    override fun getLocalPath(trackId: String): Variant_NullType_String {
        val path = core.getLocalPath(trackId)
        return if (path != null) {
            Variant_NullType_String.create(path)
        } else {
            Variant_NullType_String.create(NullType.NULL)
        }
    }

    // Deletion
    override fun deleteDownloadedTrack(trackId: String): Promise<Unit> =
        Promise.async {
            core.deleteDownloadedTrack(trackId)
        }

    override fun deleteDownloadedPlaylist(playlistId: String): Promise<Unit> =
        Promise.async {
            core.deleteDownloadedPlaylist(playlistId)
        }

    override fun deleteAllDownloads(): Promise<Unit> =
        Promise.async {
            core.deleteAllDownloads()
        }

    // Storage Management
    override fun getStorageInfo(): Promise<DownloadStorageInfo> =
        Promise.async {
            core.getStorageInfo()
        }

    @DoNotStrip
    @Keep
    override fun syncDownloads(): Double = core.syncDownloads().toDouble()

    // Playback Source Preference
    @DoNotStrip
    @Keep
    override fun setPlaybackSourcePreference(preference: PlaybackSource) {
        core.setPlaybackSourcePreference(preference)
    }

    @DoNotStrip
    @Keep
    override fun getPlaybackSourcePreference(): PlaybackSource = core.getPlaybackSourcePreference()

    @DoNotStrip
    @Keep
    override fun getEffectiveUrl(track: TrackItem): String = core.getEffectiveUrl(track)

    // Event Callbacks
    override fun onDownloadProgress(callback: (progress: DownloadProgress) -> Unit) {
        core.addProgressCallback(callback)
    }

    override fun onDownloadStateChange(callback: (downloadId: String, trackId: String, state: DownloadState, error: DownloadError?) -> Unit) {
        core.addStateChangeCallback(callback)
    }

    override fun onDownloadComplete(callback: (downloadedTrack: DownloadedTrack) -> Unit) {
        core.addCompleteCallback(callback)
    }
}
