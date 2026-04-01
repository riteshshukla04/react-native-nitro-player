package com.margelo.nitro.nitroplayer.core

import android.content.Context
import android.os.HandlerThread
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer

class ExoPlayerCore(
    context: Context,
    playerThread: HandlerThread,
) {
    /** The underlying ExoPlayer instance — accessible for MediaSessionManager wiring. */
    internal val player: ExoPlayer = build(context, playerThread)

    private fun build(
        context: Context,
        playerThread: HandlerThread,
    ): ExoPlayer {
        val loadControl =
            DefaultLoadControl
                .Builder()
                .setBufferDurationsMs(
                    // minBufferMs
                    30_000,
                    // maxBufferMs
                    120_000,
                    // bufferForPlayback
                    2_500,
                    // bufferForRebuffer
                    5_000,
                ).setBackBuffer(30_000, /* retainBackBufferFromKeyframe */ true)
                .setTargetBufferBytes(C.LENGTH_UNSET)
                .setPrioritizeTimeOverSizeThresholds(true)
                .build()

        val audioAttrs =
            AudioAttributes
                .Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .build()

        return ExoPlayer
            .Builder(context)
            .setLooper(playerThread.looper)
            .setLoadControl(loadControl)
            .setAudioAttributes(audioAttrs, /* handleAudioFocus */ true)
            .setHandleAudioBecomingNoisy(true)
            .setPauseAtEndOfMediaItems(false)
            .build()
    }

    // ── Playback ───────────────────────────────────────────────────────────
    fun play() = player.play()

    fun pause() = player.pause()

    fun seekTo(positionMs: Long) = player.seekTo(positionMs)

    fun seekToNext() = player.seekToNextMediaItem()

    fun hasNextMediaItem(): Boolean = player.hasNextMediaItem()

    fun setRepeatMode(mode: Int) {
        player.repeatMode = mode
    }

    fun setVolume(volume: Float) {
        player.volume = volume
    }

    fun setPlaybackSpeed(speed: Float) = player.setPlaybackSpeed(speed)

    fun getPlaybackSpeed(): Float = player.playbackParameters.speed

    // ── Queue mutations ────────────────────────────────────────────────────
    fun prepare() = player.prepare()

    fun seekToDefaultPosition(windowIndex: Int) = player.seekToDefaultPosition(windowIndex)

    fun clearMediaItems() = player.clearMediaItems()

    fun setMediaItems(
        items: List<MediaItem>,
        resetPosition: Boolean = false,
    ) = player.setMediaItems(items, resetPosition)

    fun addMediaItems(items: List<MediaItem>) = player.addMediaItems(items)

    fun removeMediaItems(
        fromIndex: Int,
        toIndex: Int,
    ) = player.removeMediaItems(fromIndex, toIndex)

    fun replaceMediaItem(
        index: Int,
        item: MediaItem,
    ) = player.replaceMediaItem(index, item)

    // ── Listener wiring ────────────────────────────────────────────────────
    fun addListener(listener: Player.Listener) = player.addListener(listener)

    fun removeListener(listener: Player.Listener) = player.removeListener(listener)

    // ── State reads ────────────────────────────────────────────────────────
    val playbackState: Int get() = player.playbackState
    val isPlaying: Boolean get() = player.isPlaying
    var playWhenReady: Boolean
        get() = player.playWhenReady
        set(value) {
            player.playWhenReady = value
        }
    val currentMediaItem: MediaItem? get() = player.currentMediaItem
    val currentMediaItemIndex: Int get() = player.currentMediaItemIndex
    val currentPosition: Long get() = player.currentPosition
    val duration: Long get() = player.duration
    val mediaItemCount: Int get() = player.mediaItemCount
}
