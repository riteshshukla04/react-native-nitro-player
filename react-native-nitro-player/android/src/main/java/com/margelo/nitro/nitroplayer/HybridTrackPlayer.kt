package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore

@DoNotStrip
@Keep
class HybridTrackPlayer : HybridTrackPlayerSpec() {
    private val core: TrackPlayerCore

    init {
        val context =
            NitroModules.applicationContext ?: throw IllegalStateException("React Context is not initialized")
        core = TrackPlayerCore.getInstance(context)
    }

    @DoNotStrip
    @Keep
    override fun play() {
        core.play()
    }

    @DoNotStrip
    @Keep
    override fun pause() {
        core.pause()
    }

    override fun playSong(
        songId: String,
        fromPlaylist: String?,
    ): Promise<Unit> =
        Promise.async {
            core.playSong(songId, fromPlaylist)
        }

    @DoNotStrip
    @Keep
    override fun skipToNext() {
        core.skipToNext()
    }

    @DoNotStrip
    @Keep
    override fun skipToPrevious() {
        core.skipToPrevious()
    }

    @DoNotStrip
    @Keep
    override fun seek(position: Double) {
        core.seek(position)
    }

    override fun addToUpNext(trackId: String): Promise<Unit> =
        Promise.async {
            core.addToUpNext(trackId)
        }

    override fun playNext(trackId: String): Promise<Unit> =
        Promise.async {
            core.playNext(trackId)
        }

    override fun getActualQueue(): Promise<Array<TrackItem>> =
        Promise.async {
            core.getActualQueue().toTypedArray()
        }

    override fun getState(): Promise<PlayerState> =
        Promise.async {
            core.getState()
        }

    @DoNotStrip
    @Keep
    override fun setRepeatMode(mode: RepeatMode): Boolean = core.setRepeatMode(mode)

    @DoNotStrip
    @Keep
    override fun getRepeatMode(): RepeatMode = core.getRepeatMode()

    override fun onChangeTrack(callback: (track: TrackItem, reason: Reason?) -> Unit) {
        core.addOnChangeTrackListener(callback)
    }

    override fun onPlaybackStateChange(callback: (state: TrackPlayerState, reason: Reason?) -> Unit) {
        core.addOnPlaybackStateChangeListener(callback)
    }

    override fun onSeek(callback: (position: Double, totalDuration: Double) -> Unit) {
        core.addOnSeekListener(callback)
    }

    override fun onPlaybackProgressChange(callback: (position: Double, totalDuration: Double, isManuallySeeked: Boolean?) -> Unit) {
        core.addOnPlaybackProgressChangeListener(callback)
    }

    @DoNotStrip
    @Keep
    override fun configure(config: PlayerConfig) {
        core.configure(
            androidAutoEnabled = config.androidAutoEnabled,
            carPlayEnabled = config.carPlayEnabled,
            showInNotification = config.showInNotification,
            lookaheadCount = config.lookaheadCount?.toInt(),
        )
    }

    @Keep
    override fun onAndroidAutoConnectionChange(callback: (Boolean) -> Unit) {
        core.onAndroidAutoConnectionChange = callback
    }

    @Keep
    override fun isAndroidAutoConnected(): Boolean = core.isAndroidAutoConnected()

    @DoNotStrip
    @Keep
    override fun setVolume(volume: Double): Boolean = core.setVolume(volume)

    @DoNotStrip
    @Keep
    override fun skipToIndex(index: Double): Promise<Boolean> =
        Promise.async {
            core.skipToIndex(index.toInt())
        }

    override fun updateTracks(tracks: Array<TrackItem>): Promise<Unit> =
        Promise.async {
            core.updateTracks(tracks.toList())
        }

    override fun getTracksById(trackIds: Array<String>): Promise<Array<TrackItem>> =
        Promise.async {
            core.getTracksById(trackIds.toList()).toTypedArray()
        }

    override fun getTracksNeedingUrls(): Promise<Array<TrackItem>> =
        Promise.async {
            core.getTracksNeedingUrls().toTypedArray()
        }

    override fun getNextTracks(count: Double): Promise<Array<TrackItem>> =
        Promise.async {
            core.getNextTracks(count.toInt()).toTypedArray()
        }

    override fun getCurrentTrackIndex(): Promise<Double> =
        Promise.async {
            core.getCurrentTrackIndex().toDouble()
        }

    override fun setPlaybackSpeed(speed: Double): Promise<Unit> =
        Promise.async {
            core.setPlayBackSpeed(speed)
            Unit
        }

    override fun getPlaybackSpeed(): Promise<Double> =
        Promise.async {
            core.getPlayBackSpeed()
        }

    override fun onTracksNeedUpdate(callback: (tracks: Array<TrackItem>, lookahead: Double) -> Unit) {
        core.addOnTracksNeedUpdateListener { tracks, lookahead ->
            callback(tracks.toTypedArray(), lookahead.toDouble())
        }
    }
}
