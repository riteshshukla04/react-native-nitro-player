@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.core.addToUpNextInternal
import com.margelo.nitro.nitroplayer.core.clearPlayNextOnQueue
import com.margelo.nitro.nitroplayer.core.clearUpNextOnQueue
import com.margelo.nitro.nitroplayer.core.configureOnQueue
import com.margelo.nitro.nitroplayer.core.getActualQueueInternal
import com.margelo.nitro.nitroplayer.core.getNextTracksInternal
import com.margelo.nitro.nitroplayer.core.getRepeatMode
import com.margelo.nitro.nitroplayer.core.getStateInternal
import com.margelo.nitro.nitroplayer.core.getTracksNeedingUrlsInternal
import com.margelo.nitro.nitroplayer.core.pauseOnQueue
import com.margelo.nitro.nitroplayer.core.playNextInternal
import com.margelo.nitro.nitroplayer.core.playOnQueue
import com.margelo.nitro.nitroplayer.core.playSongInternal
import com.margelo.nitro.nitroplayer.core.removeFromPlayNextOnQueue
import com.margelo.nitro.nitroplayer.core.removeFromUpNextOnQueue
import com.margelo.nitro.nitroplayer.core.reorderTemporaryTrackOnQueue
import com.margelo.nitro.nitroplayer.core.seekOnQueue
import com.margelo.nitro.nitroplayer.core.setPlayBackSpeedOnQueue
import com.margelo.nitro.nitroplayer.core.setRepeatModeOnQueue
import com.margelo.nitro.nitroplayer.core.setVolumeOnQueue
import com.margelo.nitro.nitroplayer.core.skipToIndexInternal
import com.margelo.nitro.nitroplayer.core.skipToNextOnQueue
import com.margelo.nitro.nitroplayer.core.skipToPreviousOnQueue
import com.margelo.nitro.nitroplayer.core.updateTracksOnQueue

@DoNotStrip
@Keep
class HybridTrackPlayer : HybridTrackPlayerSpec() {
    private val core: TrackPlayerCore

    // Track listener IDs for cleanup in dispose()
    private val listenerIds = mutableListOf<Pair<String, Long>>()

    init {
        val context =
            NitroModules.applicationContext
                ?: throw IllegalStateException("React Context is not initialized")
        core = TrackPlayerCore.getInstance(context)
    }

    // ── Ordered dispatch ──────────────────────────────────────────────────────
    //
    // `Promise.async { … }` launches an unordered coroutine, so the hop onto the player
    // looper happened at an arbitrary later point: two calls made in order from JS could
    // reach the player in reverse order (play-then-pause landing as pause-then-play).
    // `core.enqueue` appends synchronously, on the JS thread at call time, so execution
    // order equals JS call order.

    private fun <T> enqueue(block: () -> T): Promise<T> {
        val promise = Promise<T>()
        core.enqueue {
            try {
                promise.resolve(block())
            } catch (e: Throwable) {
                promise.reject(e)
            }
        }
        return promise
    }

    // ── Playback ─────────────────────────────────────────────────────────────

    override fun play(): Promise<Unit> = enqueue { core.playOnQueue() }

    override fun pause(): Promise<Unit> = enqueue { core.pauseOnQueue() }

    override fun seek(position: Double): Promise<Unit> = enqueue { core.seekOnQueue(position) }

    override fun skipToNext(): Promise<Unit> = enqueue { core.skipToNextOnQueue() }

    override fun skipToPrevious(): Promise<Unit> = enqueue { core.skipToPreviousOnQueue() }

    override fun playSong(
        songId: String,
        fromPlaylist: String?,
    ): Promise<Unit> = enqueue { core.playSongInternal(songId, fromPlaylist) }

    override fun skipToIndex(index: Double): Promise<Boolean> = enqueue { core.skipToIndexInternal(index.toInt()) }

    override fun setRepeatMode(mode: RepeatMode): Promise<Unit> = enqueue { core.setRepeatModeOnQueue(mode) }

    override fun getRepeatMode(): RepeatMode = core.getRepeatMode()

    override fun setVolume(volume: Double): Promise<Unit> = enqueue { core.setVolumeOnQueue(volume) }

    override fun configure(config: PlayerConfig): Promise<Unit> = enqueue { core.configureOnQueue(config) }

    // ── Queue / state reads ───────────────────────────────────────────────────

    override fun getActualQueue(): Promise<Array<TrackItem>> = enqueue { core.getActualQueueInternal().toTypedArray() }

    override fun getState(): Promise<PlayerState> = enqueue { core.getStateInternal() }

    override fun getTracksById(trackIds: Array<String>): Promise<Array<TrackItem>> = enqueue { core.getPlaylistManager().getTracksById(trackIds.toList()).toTypedArray() }

    override fun getTracksNeedingUrls(): Promise<Array<TrackItem>> = enqueue { core.getTracksNeedingUrlsInternal().toTypedArray() }

    override fun getNextTracks(count: Double): Promise<Array<TrackItem>> = enqueue { core.getNextTracksInternal(count.toInt()).toTypedArray() }

    override fun getCurrentTrackIndex(): Promise<Double> = enqueue { core.currentTrackIndex.toDouble() }

    // ── URL updates ───────────────────────────────────────────────────────────

    override fun updateTracks(tracks: Array<TrackItem>): Promise<Unit> = enqueue { core.updateTracksOnQueue(tracks.toList()) }

    // ── Temporary queue ───────────────────────────────────────────────────────

    override fun addToUpNext(trackId: String): Promise<Unit> = enqueue { core.addToUpNextInternal(trackId) }

    override fun playNext(trackId: String): Promise<Unit> = enqueue { core.playNextInternal(trackId) }

    override fun removeFromPlayNext(trackId: String): Promise<Boolean> = enqueue { core.removeFromPlayNextOnQueue(trackId) }

    override fun removeFromUpNext(trackId: String): Promise<Boolean> = enqueue { core.removeFromUpNextOnQueue(trackId) }

    override fun clearPlayNext(): Promise<Unit> = enqueue { core.clearPlayNextOnQueue() }

    override fun clearUpNext(): Promise<Unit> = enqueue { core.clearUpNextOnQueue() }

    override fun reorderTemporaryTrack(
        trackId: String,
        newIndex: Double,
    ): Promise<Boolean> = enqueue { core.reorderTemporaryTrackOnQueue(trackId, newIndex.toInt()) }

    override fun getPlayNextQueue(): Promise<Array<TrackItem>> = enqueue { core.playNextStack.toTypedArray() }

    override fun getUpNextQueue(): Promise<Array<TrackItem>> = enqueue { core.upNextQueue.toTypedArray() }

    // ── Playback speed ────────────────────────────────────────────────────────

    override fun setPlaybackSpeed(speed: Double): Promise<Unit> = enqueue { core.setPlayBackSpeedOnQueue(speed) }

    override fun getPlaybackSpeed(): Promise<Double> = enqueue { if (core.isExoInitialized) core.exo.getPlaybackSpeed().toDouble() else 1.0 }

    // ── Android Auto ──────────────────────────────────────────────────────────

    override fun isAndroidAutoConnected(): Boolean = core.isAndroidAutoConnected()

    // ── Event listeners ───────────────────────────────────────────────────────

    override fun onChangeTrack(callback: (track: TrackItem, reason: Reason?) -> Unit) {
        val id = core.addOnChangeTrackListener(callback)
        listenerIds += "onChangeTrack" to id
    }

    override fun onPlaybackStateChange(callback: (state: TrackPlayerState, reason: Reason?) -> Unit) {
        val id = core.addOnPlaybackStateChangeListener(callback)
        listenerIds += "onPlaybackStateChange" to id
    }

    override fun onSeek(callback: (position: Double, totalDuration: Double) -> Unit) {
        val id = core.addOnSeekListener(callback)
        listenerIds += "onSeek" to id
    }

    override fun onPlaybackProgressChange(callback: (position: Double, totalDuration: Double, isManuallySeeked: Boolean?) -> Unit) {
        val id = core.addOnPlaybackProgressChangeListener(callback)
        listenerIds += "onPlaybackProgressChange" to id
    }

    override fun onAndroidAutoConnectionChange(callback: (connected: Boolean) -> Unit) {
        // Replace any prior listener registered through this HybridObject so JS
        // reloads (Fast Refresh, hot reload) don't accumulate handlers.
        val existing = listenerIds.filter { it.first == "onAndroidAutoConnectionChange" }
        existing.forEach { (_, oldId) -> core.removeOnAndroidAutoConnectionListener(oldId) }
        listenerIds.removeAll { it.first == "onAndroidAutoConnectionChange" }

        val id = core.addOnAndroidAutoConnectionListener(callback)
        listenerIds += "onAndroidAutoConnectionChange" to id
    }

    override fun onTracksNeedUpdate(callback: (tracks: Array<TrackItem>, lookahead: Double) -> Unit) {
        val id =
            core.addOnTracksNeedUpdateListener { tracks, lookahead ->
                callback(tracks.toTypedArray(), lookahead.toDouble())
            }
        listenerIds += "onTracksNeedUpdate" to id
    }

    override fun onTimedMetadata(callback: (metadata: TimedMetadata) -> Unit) {
        val id = core.addOnTimedMetadataListener(callback)
        listenerIds += "onTimedMetadata" to id
    }

    override fun onTemporaryQueueChange(callback: (playNextQueue: Array<TrackItem>, upNextQueue: Array<TrackItem>) -> Unit) {
        val id =
            core.addOnTemporaryQueueChangeListener { pn, un ->
                callback(pn.toTypedArray(), un.toTypedArray())
            }
        listenerIds += "onTemporaryQueueChange" to id
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────

    override fun dispose() {
        super.dispose()
        listenerIds.forEach { (type, id) ->
            when (type) {
                "onChangeTrack" -> core.removeOnChangeTrackListener(id)
                "onPlaybackStateChange" -> core.removeOnPlaybackStateChangeListener(id)
                "onSeek" -> core.removeOnSeekListener(id)
                "onPlaybackProgressChange" -> core.removeOnPlaybackProgressChangeListener(id)
                "onAndroidAutoConnectionChange" -> core.removeOnAndroidAutoConnectionListener(id)
                "onTracksNeedUpdate" -> core.removeOnTracksNeedUpdateListener(id)
                "onTemporaryQueueChange" -> core.removeOnTemporaryQueueChangeListener(id)
                "onTimedMetadata" -> core.removeOnTimedMetadataListener(id)
            }
        }
        listenerIds.clear()
    }
}
