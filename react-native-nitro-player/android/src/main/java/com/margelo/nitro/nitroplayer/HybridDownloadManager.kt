@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.NullType
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.download.DownloadManagerCore

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

    // ── Configuration ─────────────────────────────────────────────────────────
    override fun configure(config: DownloadConfig) = core.configure(config)

    override fun getConfig(): DownloadConfig = core.getConfig()

    // ── Download operations ───────────────────────────────────────────────────
    override fun downloadTrack(
        track: TrackItem,
        playlistId: String?,
    ): Promise<String> = Promise.async { core.downloadTrack(track, playlistId) }

    override fun downloadPlaylist(
        playlistId: String,
        tracks: Array<TrackItem>,
    ): Promise<Array<String>> = Promise.async { core.downloadPlaylist(playlistId, tracks) }

    override fun pauseDownload(downloadId: String): Promise<Unit> = Promise.async { core.pauseDownload(downloadId) }

    override fun resumeDownload(downloadId: String): Promise<Unit> = Promise.async { core.resumeDownload(downloadId) }

    override fun cancelDownload(downloadId: String): Promise<Unit> = Promise.async { core.cancelDownload(downloadId) }

    override fun retryDownload(downloadId: String): Promise<Unit> = Promise.async { core.retryDownload(downloadId) }

    override fun pauseAllDownloads(): Promise<Unit> = Promise.async { core.pauseAllDownloads() }

    override fun resumeAllDownloads(): Promise<Unit> = Promise.async { core.resumeAllDownloads() }

    override fun cancelAllDownloads(): Promise<Unit> = Promise.async { core.cancelAllDownloads() }

    // ── Download status (sync) ────────────────────────────────────────────────
    override fun getDownloadTask(downloadId: String): Variant_NullType_DownloadTask {
        val task = core.getDownloadTask(downloadId)
        return if (task != null) {
            Variant_NullType_DownloadTask.create(task)
        } else {
            Variant_NullType_DownloadTask.create(NullType.NULL)
        }
    }

    override fun getActiveDownloads(): Array<DownloadTask> = core.getActiveDownloads()

    override fun getQueueStatus(): DownloadQueueStatus = core.getQueueStatus()

    override fun isDownloading(trackId: String): Boolean = core.isDownloading(trackId)

    override fun getDownloadState(trackId: String): DownloadState = core.getDownloadState(trackId)

    // ── Downloaded content queries (now async per spec) ───────────────────────
    override fun isTrackDownloaded(trackId: String): Promise<Boolean> = Promise.async { core.isTrackDownloaded(trackId) }

    override fun isPlaylistDownloaded(playlistId: String): Promise<Boolean> = Promise.async { core.isPlaylistDownloaded(playlistId) }

    override fun isPlaylistPartiallyDownloaded(playlistId: String): Promise<Boolean> = Promise.async { core.isPlaylistPartiallyDownloaded(playlistId) }

    override fun getDownloadedTrack(trackId: String): Promise<Variant_NullType_DownloadedTrack> =
        Promise.async {
            val track = core.getDownloadedTrack(trackId)
            if (track != null) {
                Variant_NullType_DownloadedTrack.create(track)
            } else {
                Variant_NullType_DownloadedTrack.create(NullType.NULL)
            }
        }

    override fun getAllDownloadedTracks(): Promise<Array<DownloadedTrack>> = Promise.async { core.getAllDownloadedTracks() }

    override fun getDownloadedPlaylist(playlistId: String): Promise<Variant_NullType_DownloadedPlaylist> =
        Promise.async {
            val playlist = core.getDownloadedPlaylist(playlistId)
            if (playlist != null) {
                Variant_NullType_DownloadedPlaylist.create(playlist)
            } else {
                Variant_NullType_DownloadedPlaylist.create(NullType.NULL)
            }
        }

    override fun getAllDownloadedPlaylists(): Promise<Array<DownloadedPlaylist>> = Promise.async { core.getAllDownloadedPlaylists() }

    override fun getLocalPath(trackId: String): Promise<Variant_NullType_String> =
        Promise.async {
            val path = core.getLocalPath(trackId)
            if (path != null) {
                Variant_NullType_String.create(path)
            } else {
                Variant_NullType_String.create(NullType.NULL)
            }
        }

    override fun syncDownloads(): Promise<Double> = Promise.async { core.syncDownloads().toDouble() }

    override fun getEffectiveUrl(track: TrackItem): Promise<String> = Promise.async { core.getEffectiveUrl(track) }

    // ── Deletion ──────────────────────────────────────────────────────────────
    override fun deleteDownloadedTrack(trackId: String): Promise<Unit> = Promise.async { core.deleteDownloadedTrack(trackId) }

    override fun deleteDownloadedPlaylist(playlistId: String): Promise<Unit> = Promise.async { core.deleteDownloadedPlaylist(playlistId) }

    override fun deleteAllDownloads(): Promise<Unit> = Promise.async { core.deleteAllDownloads() }

    override fun getStorageInfo(): Promise<DownloadStorageInfo> = Promise.async { core.getStorageInfo() }

    // ── Playback source ───────────────────────────────────────────────────────
    override fun setPlaybackSourcePreference(preference: PlaybackSource) = core.setPlaybackSourcePreference(preference)

    override fun getPlaybackSourcePreference(): PlaybackSource = core.getPlaybackSourcePreference()

    // ── Events ────────────────────────────────────────────────────────────────
    override fun onDownloadProgress(callback: (progress: DownloadProgress) -> Unit) = core.addProgressCallback(callback)

    override fun onDownloadStateChange(callback: (downloadId: String, trackId: String, state: DownloadState, error: DownloadError?) -> Unit) = core.addStateChangeCallback(callback)

    override fun onDownloadComplete(callback: (downloadedTrack: DownloadedTrack) -> Unit) = core.addCompleteCallback(callback)
}
