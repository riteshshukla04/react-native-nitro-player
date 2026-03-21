@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.core.addToUpNext
import com.margelo.nitro.nitroplayer.core.clearPlayNext
import com.margelo.nitro.nitroplayer.core.clearUpNext
import com.margelo.nitro.nitroplayer.core.configure
import com.margelo.nitro.nitroplayer.core.getActualQueue
import com.margelo.nitro.nitroplayer.core.getCurrentTrackIndex
import com.margelo.nitro.nitroplayer.core.getNextTracks
import com.margelo.nitro.nitroplayer.core.getPlayBackSpeed
import com.margelo.nitro.nitroplayer.core.getPlayNextQueue
import com.margelo.nitro.nitroplayer.core.getRepeatMode
import com.margelo.nitro.nitroplayer.core.getState
import com.margelo.nitro.nitroplayer.core.getTracksById
import com.margelo.nitro.nitroplayer.core.getTracksNeedingUrls
import com.margelo.nitro.nitroplayer.core.getUpNextQueue
import com.margelo.nitro.nitroplayer.core.pause
import com.margelo.nitro.nitroplayer.core.play
import com.margelo.nitro.nitroplayer.core.playNext
import com.margelo.nitro.nitroplayer.core.playSong
import com.margelo.nitro.nitroplayer.core.removeFromPlayNext
import com.margelo.nitro.nitroplayer.core.removeFromUpNext
import com.margelo.nitro.nitroplayer.core.reorderTemporaryTrack
import com.margelo.nitro.nitroplayer.core.seek
import com.margelo.nitro.nitroplayer.core.setPlayBackSpeed
import com.margelo.nitro.nitroplayer.core.setRepeatMode
import com.margelo.nitro.nitroplayer.core.setVolume
import com.margelo.nitro.nitroplayer.core.skipToIndex
import com.margelo.nitro.nitroplayer.core.skipToNext
import com.margelo.nitro.nitroplayer.core.skipToPrevious
import com.margelo.nitro.nitroplayer.core.updateTracks

@DoNotStrip
@Keep
class HybridTrackPlayer : HybridTrackPlayerSpec() {
    private val core: TrackPlayerCore

    // Track listener IDs for cleanup in dispose()
    private val listenerIds = mutableListOf<Pair<String, Long>>()

    init {
        val context = NitroModules.applicationContext
            ?: throw IllegalStateException("React Context is not initialized")
        core = TrackPlayerCore.getInstance(context)
    }

    // ── Playback ─────────────────────────────────────────────────────────────

    override fun play(): Promise<Unit> = Promise.async { core.play() }
    override fun pause(): Promise<Unit> = Promise.async { core.pause() }
    override fun seek(position: Double): Promise<Unit> = Promise.async { core.seek(position) }
    override fun skipToNext(): Promise<Unit> = Promise.async { core.skipToNext() }
    override fun skipToPrevious(): Promise<Unit> = Promise.async { core.skipToPrevious() }
    override fun playSong(songId: String, fromPlaylist: String?): Promise<Unit> = Promise.async { core.playSong(songId, fromPlaylist) }
    override fun skipToIndex(index: Double): Promise<Boolean> = Promise.async { core.skipToIndex(index.toInt()) }

    override fun setRepeatMode(mode: RepeatMode): Promise<Unit> = Promise.async { core.setRepeatMode(mode) }
    override fun getRepeatMode(): RepeatMode = core.getRepeatMode()

    override fun setVolume(volume: Double): Promise<Unit> = Promise.async { core.setVolume(volume) }

    override fun configure(config: PlayerConfig): Promise<Unit> = Promise.async { core.configure(config) }

    // ── Queue / state reads ───────────────────────────────────────────────────

    override fun getActualQueue(): Promise<Array<TrackItem>> = Promise.async { core.getActualQueue().toTypedArray() }
    override fun getState(): Promise<PlayerState> = Promise.async { core.getState() }
    override fun getTracksById(trackIds: Array<String>): Promise<Array<TrackItem>> = Promise.async { core.getTracksById(trackIds.toList()).toTypedArray() }
    override fun getTracksNeedingUrls(): Promise<Array<TrackItem>> = Promise.async { core.getTracksNeedingUrls().toTypedArray() }
    override fun getNextTracks(count: Double): Promise<Array<TrackItem>> = Promise.async { core.getNextTracks(count.toInt()).toTypedArray() }
    override fun getCurrentTrackIndex(): Promise<Double> = Promise.async { core.getCurrentTrackIndex().toDouble() }

    // ── URL updates ───────────────────────────────────────────────────────────

    override fun updateTracks(tracks: Array<TrackItem>): Promise<Unit> = Promise.async { core.updateTracks(tracks.toList()) }

    // ── Temporary queue ───────────────────────────────────────────────────────

    override fun addToUpNext(trackId: String): Promise<Unit> = Promise.async { core.addToUpNext(trackId) }
    override fun playNext(trackId: String): Promise<Unit> = Promise.async { core.playNext(trackId) }
    override fun removeFromPlayNext(trackId: String): Promise<Boolean> = Promise.async { core.removeFromPlayNext(trackId) }
    override fun removeFromUpNext(trackId: String): Promise<Boolean> = Promise.async { core.removeFromUpNext(trackId) }
    override fun clearPlayNext(): Promise<Unit> = Promise.async { core.clearPlayNext() }
    override fun clearUpNext(): Promise<Unit> = Promise.async { core.clearUpNext() }
    override fun reorderTemporaryTrack(trackId: String, newIndex: Double): Promise<Boolean> = Promise.async { core.reorderTemporaryTrack(trackId, newIndex.toInt()) }
    override fun getPlayNextQueue(): Promise<Array<TrackItem>> = Promise.async { core.getPlayNextQueue().toTypedArray() }
    override fun getUpNextQueue(): Promise<Array<TrackItem>> = Promise.async { core.getUpNextQueue().toTypedArray() }

    // ── Playback speed ────────────────────────────────────────────────────────

    override fun setPlaybackSpeed(speed: Double): Promise<Unit> = Promise.async { core.setPlayBackSpeed(speed) }
    override fun getPlaybackSpeed(): Promise<Double> = Promise.async { core.getPlayBackSpeed() }

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
        val id = core.addOnAndroidAutoConnectionListener(callback)
        listenerIds += "onAndroidAutoConnectionChange" to id
    }

    override fun onTracksNeedUpdate(callback: (tracks: Array<TrackItem>, lookahead: Double) -> Unit) {
        val id = core.addOnTracksNeedUpdateListener { tracks, lookahead ->
            callback(tracks.toTypedArray(), lookahead.toDouble())
        }
        listenerIds += "onTracksNeedUpdate" to id
    }

    override fun onTemporaryQueueChange(callback: (playNextQueue: Array<TrackItem>, upNextQueue: Array<TrackItem>) -> Unit) {
        val id = core.addOnTemporaryQueueChangeListener { pn, un ->
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
            }
        }
        listenerIds.clear()
    }
}
