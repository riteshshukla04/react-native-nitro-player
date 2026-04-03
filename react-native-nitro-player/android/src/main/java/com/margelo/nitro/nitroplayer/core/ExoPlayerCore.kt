package com.margelo.nitro.nitroplayer.core

import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer

/**
 * Thin wrapper around an [ExoPlayer] instance owned by the playback service.
 * All delegation methods are unchanged — only the constructor now accepts an
 * existing player instead of building one.
 */
class ExoPlayerCore(
    exoPlayer: ExoPlayer,
) {
    /** The underlying ExoPlayer instance — accessible for wiring. */
    internal val player: ExoPlayer = exoPlayer

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
