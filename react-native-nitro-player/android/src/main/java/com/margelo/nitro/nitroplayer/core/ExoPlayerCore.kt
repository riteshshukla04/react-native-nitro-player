package com.margelo.nitro.nitroplayer.core

import androidx.media3.common.MediaItem
import androidx.media3.common.Player

/**
 * Thin wrapper around the **currently active** Media3 [Player].
 *
 * This is normally the service-owned `ExoPlayer` (local playback) but can be
 * swapped to a `CastPlayer` while a Google Cast session is active — both
 * implement the same [Player] interface, so every delegation method below works
 * unchanged regardless of which backend is playing. The wrapper instance is
 * reassigned (see `TrackPlayerCast.switchToPlayer`) when the backend changes.
 */
class ExoPlayerCore(
    player: Player,
) {
    /** The underlying active player instance — accessible for wiring. */
    internal val player: Player = player

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

    fun getMediaItemAt(index: Int): MediaItem = player.getMediaItemAt(index)
    val currentPosition: Long get() = player.currentPosition
    val duration: Long get() = player.duration
    val mediaItemCount: Int get() = player.mediaItemCount
}
