package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore

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

    @DoNotStrip
    @Keep
    override fun playSong(
        songId: String,
        fromPlaylist: String?,
    ) {
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

    @DoNotStrip
    @Keep
    override fun getState(): PlayerState = core.getState()

    @DoNotStrip
    @Keep
    override fun setRepeatMode(mode: RepeatMode): Boolean = core.setRepeatMode(mode)

    override fun onChangeTrack(callback: (track: TrackItem, reason: Reason?) -> Unit) {
        core.onChangeTrack = callback
    }

    override fun onPlaybackStateChange(callback: (state: TrackPlayerState, reason: Reason?) -> Unit) {
        core.onPlaybackStateChange = callback
    }

    override fun onSeek(callback: (position: Double, totalDuration: Double) -> Unit) {
        core.onSeek = callback
    }

    override fun onPlaybackProgressChange(callback: (position: Double, totalDuration: Double, isManuallySeeked: Boolean?) -> Unit) {
        core.onPlaybackProgressChange = callback
    }

    @DoNotStrip
    @Keep
    override fun configure(config: PlayerConfig) {
        core.configure(
            androidAutoEnabled = config.androidAutoEnabled,
            carPlayEnabled = config.carPlayEnabled,
            showInNotification = config.showInNotification,
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
}
