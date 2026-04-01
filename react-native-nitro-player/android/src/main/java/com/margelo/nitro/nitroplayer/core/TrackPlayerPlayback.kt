@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import androidx.media3.common.Player
import com.margelo.nitro.nitroplayer.PlayerConfig
import com.margelo.nitro.nitroplayer.Reason
import com.margelo.nitro.nitroplayer.RepeatMode
import com.margelo.nitro.nitroplayer.TrackPlayerState
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService

/**
 * Playback control — all public functions are suspend and execute on the player thread
 * via withPlayerContext.
 */

suspend fun TrackPlayerCore.play() = withPlayerContext { exo.play() }

suspend fun TrackPlayerCore.pause() = withPlayerContext { exo.pause() }

suspend fun TrackPlayerCore.seek(position: Double) =
    withPlayerContext {
        isManuallySeeked = true
        exo.seekTo((position * 1000).toLong())
    }

suspend fun TrackPlayerCore.skipToNext() =
    withPlayerContext {
        if (exo.hasNextMediaItem()) {
            exo.seekToNext()
            checkUpcomingTracksForUrls(lookaheadCount)
        }
    }

suspend fun TrackPlayerCore.skipToPrevious() =
    withPlayerContext {
        val currentPosition = exo.currentPosition
        when {
            currentPosition > 2000 -> {
                exo.seekTo(0)
            }

            currentTemporaryType != TrackPlayerCore.TemporaryType.NONE -> {
                val trackId = exo.currentMediaItem?.mediaId?.let { extractTrackId(it) }
                if (trackId != null) {
                    when (currentTemporaryType) {
                        TrackPlayerCore.TemporaryType.PLAY_NEXT -> {
                            val idx = playNextStack.indexOfFirst { it.id == trackId }
                            if (idx >= 0) playNextStack.removeAt(idx)
                        }

                        TrackPlayerCore.TemporaryType.UP_NEXT -> {
                            val idx = upNextQueue.indexOfFirst { it.id == trackId }
                            if (idx >= 0) upNextQueue.removeAt(idx)
                        }

                        else -> {}
                    }
                }
                currentTemporaryType = TrackPlayerCore.TemporaryType.NONE
                playFromIndexInternal(currentTrackIndex)
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

suspend fun TrackPlayerCore.setRepeatMode(mode: RepeatMode) =
    withPlayerContext {
        currentRepeatMode = mode
        exo.setRepeatMode(
            when (mode) {
                RepeatMode.TRACK -> Player.REPEAT_MODE_ONE
                else -> Player.REPEAT_MODE_OFF
            },
        )
    }

fun TrackPlayerCore.getRepeatMode(): RepeatMode = currentRepeatMode

suspend fun TrackPlayerCore.setVolume(volume: Double) =
    withPlayerContext {
        val clamped = volume.coerceIn(0.0, 100.0)
        exo.setVolume((clamped / 100.0).toFloat())
    }

suspend fun TrackPlayerCore.configure(config: PlayerConfig) =
    withPlayerContext {
        config.androidAutoEnabled?.let { NitroPlayerMediaBrowserService.isAndroidAutoEnabled = it }
        config.lookaheadCount?.let { lookaheadCount = it.toInt() }
        mediaSessionManager?.configure(config.androidAutoEnabled, config.carPlayEnabled, config.showInNotification)
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
            Player.STATE_BUFFERING -> if (exo.playWhenReady) TrackPlayerState.PLAYING else TrackPlayerState.PAUSED
            Player.STATE_READY -> if (exo.isPlaying) TrackPlayerState.PLAYING else TrackPlayerState.PAUSED
            Player.STATE_ENDED -> TrackPlayerState.STOPPED
            else -> TrackPlayerState.STOPPED
        }
    val actualReason = reason ?: if (exo.playbackState == Player.STATE_ENDED) Reason.END else null
    notifyPlaybackStateChange(state, actualReason)
    mediaSessionManager?.onPlaybackStateChanged(state == TrackPlayerState.PLAYING)
}

// ── Playback speed ────────────────────────────────────────────────────────

suspend fun TrackPlayerCore.setPlayBackSpeed(speed: Double) =
    withPlayerContext {
        if (speed <= 0.0) throw IllegalArgumentException("Speed must be greater than 0")
        if (isExoInitialized) exo.setPlaybackSpeed(speed.toFloat())
    }

suspend fun TrackPlayerCore.getPlayBackSpeed(): Double =
    withPlayerContext {
        if (isExoInitialized) exo.getPlaybackSpeed().toDouble() else 1.0
    }
