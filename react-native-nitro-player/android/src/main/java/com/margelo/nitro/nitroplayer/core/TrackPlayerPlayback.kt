@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import androidx.annotation.OptIn
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.margelo.nitro.nitroplayer.PlayerConfig
import com.margelo.nitro.nitroplayer.Reason
import com.margelo.nitro.nitroplayer.RepeatMode
import com.margelo.nitro.nitroplayer.TrackPlayerState
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService
import com.margelo.nitro.nitroplayer.media.NitroPlayerPlaybackService

/**
 * Playback control — all public functions are suspend and execute on the player thread
 * via withPlayerContext.
 */

suspend fun TrackPlayerCore.play() = withPlayerContext { playOnQueue() }

internal fun TrackPlayerCore.playOnQueue() = exo.play()

suspend fun TrackPlayerCore.pause() = withPlayerContext { pauseOnQueue() }

internal fun TrackPlayerCore.pauseOnQueue() = exo.pause()

suspend fun TrackPlayerCore.seek(position: Double) = withPlayerContext { seekOnQueue(position) }

internal fun TrackPlayerCore.seekOnQueue(position: Double) {
    isManuallySeeked = true
    exo.seekTo((position * 1000).toLong())
}

suspend fun TrackPlayerCore.skipToNext() = withPlayerContext { skipToNextOnQueue() }

internal fun TrackPlayerCore.skipToNextOnQueue() {
    // The timeline is windowed, so hasNextMediaItem() is not the logical answer —
    // top up first when more tracks remain in currentTracks / the temp queues.
    if (!exo.hasNextMediaItem()) rebuildQueueFromCurrentPosition()
    if (exo.hasNextMediaItem()) {
        exo.seekToNext()
        checkUpcomingTracksForUrls(lookaheadCount)
    }
}

suspend fun TrackPlayerCore.skipToPrevious() = withPlayerContext { skipToPreviousOnQueue() }

internal fun TrackPlayerCore.skipToPreviousOnQueue() {
    val currentPosition = exo.currentPosition
    when {
        currentPosition > 2000 -> {
            exo.seekTo(0)
        }

        currentTemporaryType != TrackPlayerCore.TemporaryType.NONE -> {
            // playFromIndexInternal clears both temp lists; cursor may be -1 (anchor removed).
            if (currentTracks.isEmpty()) exo.seekTo(0) else playFromIndexInternal(maxOf(0, currentTrackIndex))
        }

        currentTrackIndex > 0 -> {
            playFromIndexInternal(currentTrackIndex - 1)
        }

        else -> {
            exo.seekTo(0)
        }
    }
    checkUpcomingTracksForUrls(lookaheadCount)
}

suspend fun TrackPlayerCore.setRepeatMode(mode: RepeatMode) = withPlayerContext { setRepeatModeOnQueue(mode) }

internal fun TrackPlayerCore.setRepeatModeOnQueue(mode: RepeatMode) {
    val previousMode = currentRepeatMode
    currentRepeatMode = mode
    applyBackendRepeatMode()
    if (!isCastingField && previousMode != mode &&
        (previousMode == RepeatMode.PLAYLIST || mode == RepeatMode.PLAYLIST)
    ) {
        rebuildQueueFromCurrentPosition()
    }
}

/** True while the playing item was removed from the playlist and is finishing. */
internal fun TrackPlayerCore.isTransientPlayOut(): Boolean {
    if (!isExoInitialized || currentTemporaryType != TrackPlayerCore.TemporaryType.NONE) return false
    val item = exo.currentMediaItem ?: return false
    return findTrack(item) == null
}

/** Follows the user's mode except during a transient play-out, which must finish once. */
internal fun TrackPlayerCore.backendRepeatMode(): Int =
    when {
        isTransientPlayOut() -> Player.REPEAT_MODE_OFF
        currentRepeatMode == RepeatMode.TRACK -> Player.REPEAT_MODE_ONE
        else -> Player.REPEAT_MODE_OFF
    }

internal fun TrackPlayerCore.applyBackendRepeatMode() {
    if (!isExoInitialized) return
    val desired = backendRepeatMode()
    if (exo.player.repeatMode != desired) exo.setRepeatMode(desired)
}

fun TrackPlayerCore.getRepeatMode(): RepeatMode = currentRepeatMode

suspend fun TrackPlayerCore.setVolume(volume: Double) = withPlayerContext { setVolumeOnQueue(volume) }

internal fun TrackPlayerCore.setVolumeOnQueue(volume: Double) {
    val clamped = volume.coerceIn(0.0, 100.0)
    exo.setVolume((clamped / 100.0).toFloat())
}

suspend fun TrackPlayerCore.configure(config: PlayerConfig) = withPlayerContext { configureOnQueue(config) }

internal fun TrackPlayerCore.configureOnQueue(config: PlayerConfig) {
    config.androidAutoEnabled?.let { NitroPlayerMediaBrowserService.isAndroidAutoEnabled = it }
    config.lookaheadCount?.let { lookaheadCount = it.toInt() }
    config.androidNotificationIcon?.let { NitroPlayerPlaybackService.notificationSmallIconResName = it }
    remoteSkipIntervalMs(config.remoteSkipForwardInterval)?.let { remoteSkipForwardIntervalMs = it }
    remoteSkipIntervalMs(config.remoteSkipBackwardInterval)?.let { remoteSkipBackwardIntervalMs = it }
    applyRemoteSkipIntervals()
    mediaSessionManager?.configure(
        config.androidAutoEnabled,
        config.carPlayEnabled,
        config.showInNotification,
        remoteSkipForwardIntervalMs,
        remoteSkipBackwardIntervalMs,
    )
}

// Resolved from the cast controller: mid-cast `exo` is the CastPlayer, whose increments are fixed
@OptIn(UnstableApi::class)
internal fun TrackPlayerCore.applyRemoteSkipIntervals() {
    val local = castSessionController?.localPlayer ?: if (isExoInitialized) exo.player else null
    (local as? ExoPlayer)?.let {
        it.setSeekBackIncrementMs(remoteSkipBackwardIntervalMs)
        it.setSeekForwardIncrementMs(remoteSkipForwardIntervalMs)
    }
}

private fun remoteSkipIntervalMs(intervalSeconds: Double?): Long? {
    if (intervalSeconds == null || !intervalSeconds.isFinite() || intervalSeconds <= 0.0) return null
    return (intervalSeconds * 1000.0).toLong().coerceAtLeast(1L)
}

suspend fun TrackPlayerCore.playSong(
    songId: String,
    fromPlaylist: String?,
) = withPlayerContext {
    playSongInternal(songId, fromPlaylist)
}

internal fun TrackPlayerCore.playSongInternal(
    songId: String,
    fromPlaylist: String?,
) {
    playNextStack.clear()
    upNextQueue.clear()
    currentTemporaryType = TrackPlayerCore.TemporaryType.NONE

    var targetPlaylistId: String? = null
    var songIndex: Int = -1

    if (fromPlaylist != null) {
        val playlist = playlistManager.getPlaylist(fromPlaylist)
        if (playlist != null) {
            songIndex = playlist.tracks.indexOfFirst { it.id == songId }
            if (songIndex >= 0) targetPlaylistId = fromPlaylist else return
        } else {
            return
        }
    } else {
        if (currentPlaylistId != null) {
            val cp = playlistManager.getPlaylist(currentPlaylistId!!)
            if (cp != null) {
                songIndex = cp.tracks.indexOfFirst { it.id == songId }
                if (songIndex >= 0) targetPlaylistId = currentPlaylistId
            }
        }
        if (songIndex == -1) {
            for (playlist in playlistManager.getAllPlaylists()) {
                songIndex = playlist.tracks.indexOfFirst { it.id == songId }
                if (songIndex >= 0) {
                    targetPlaylistId = playlist.id
                    break
                }
            }
        }
        if (songIndex == -1) {
            val all = playlistManager.getAllPlaylists()
            if (all.isNotEmpty()) {
                targetPlaylistId = all[0].id
                songIndex = 0
            }
        }
    }

    if (targetPlaylistId == null || songIndex < 0) return

    playlistManager.setCurrentPlaylistId(targetPlaylistId)
    if (currentPlaylistId != targetPlaylistId) {
        val playlist = playlistManager.getPlaylist(targetPlaylistId) ?: return
        currentPlaylistId = targetPlaylistId
        updatePlayerQueue(playlist.tracks)
    }
    playFromIndexInternal(songIndex)
}

// ── State emission (called from player thread) ─────────────────────────────

internal fun TrackPlayerCore.emitStateChange(reason: Reason? = null) {
    if (!isExoInitialized) return
    val state =
        when (exo.playbackState) {
            Player.STATE_IDLE -> TrackPlayerState.STOPPED
            Player.STATE_BUFFERING -> if (exo.playWhenReady) TrackPlayerState.BUFFERING else TrackPlayerState.PAUSED
            Player.STATE_READY -> if (exo.isPlaying) TrackPlayerState.PLAYING else TrackPlayerState.PAUSED
            Player.STATE_ENDED -> TrackPlayerState.STOPPED
            else -> TrackPlayerState.STOPPED
        }
    val actualReason = reason ?: if (exo.playbackState == Player.STATE_ENDED) Reason.END else null
    notifyPlaybackStateChange(state, actualReason)
    mediaSessionManager?.onPlaybackStateChanged(state == TrackPlayerState.PLAYING)
}

// ── Playback speed ────────────────────────────────────────────────────────

suspend fun TrackPlayerCore.setPlayBackSpeed(speed: Double) = withPlayerContext { setPlayBackSpeedOnQueue(speed) }

internal fun TrackPlayerCore.setPlayBackSpeedOnQueue(speed: Double) {
    if (!speed.isFinite() || speed <= 0.0) {
        throw IllegalArgumentException("Speed must be finite and greater than 0")
    }
    if (isExoInitialized) exo.setPlaybackSpeed(speed.toFloat())
}

suspend fun TrackPlayerCore.getPlayBackSpeed(): Double =
    withPlayerContext {
        if (isExoInitialized) exo.getPlaybackSpeed().toDouble() else 1.0
    }
