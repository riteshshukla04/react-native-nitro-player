@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import androidx.media3.common.Player
import com.margelo.nitro.nitroplayer.CurrentPlayingType
import com.margelo.nitro.nitroplayer.PlayerState
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.TrackPlayerState
import com.margelo.nitro.nitroplayer.Variant_NullType_String
import com.margelo.nitro.nitroplayer.Variant_NullType_TrackItem

/**
 * State read + index-navigation — all public functions are suspend and run on the
 * player thread via withPlayerContext.
 */

// ── Player state ──────────────────────────────────────────────────────────

suspend fun TrackPlayerCore.getState(): PlayerState = withPlayerContext { getStateInternal() }

internal fun TrackPlayerCore.getStateInternal(): PlayerState {
    if (!isExoInitialized) {
        return PlayerState(
            currentTrack = null,
            currentPosition = 0.0,
            totalDuration = 0.0,
            currentState = TrackPlayerState.STOPPED,
            currentPlaylistId = currentPlaylistId?.let { Variant_NullType_String.create(it) },
            currentIndex = -1.0,
            currentPlayingType = CurrentPlayingType.NOT_PLAYING,
        )
    }
    val track = getCurrentTrack()
    val currentTrack: Variant_NullType_TrackItem? = track?.let { Variant_NullType_TrackItem.create(it) }
    val position = exo.currentPosition / 1000.0
    val duration = if (exo.duration > 0) exo.duration / 1000.0 else 0.0
    val state =
        when (exo.playbackState) {
            Player.STATE_IDLE -> TrackPlayerState.STOPPED
            Player.STATE_BUFFERING -> if (exo.playWhenReady) TrackPlayerState.PLAYING else TrackPlayerState.PAUSED
            Player.STATE_READY -> if (exo.isPlaying) TrackPlayerState.PLAYING else TrackPlayerState.PAUSED
            Player.STATE_ENDED -> TrackPlayerState.STOPPED
            else -> TrackPlayerState.STOPPED
        }
    val playingType =
        if (track == null) {
            CurrentPlayingType.NOT_PLAYING
        } else {
            when (currentTemporaryType) {
                TrackPlayerCore.TemporaryType.NONE -> CurrentPlayingType.PLAYLIST
                TrackPlayerCore.TemporaryType.PLAY_NEXT -> CurrentPlayingType.PLAY_NEXT
                TrackPlayerCore.TemporaryType.UP_NEXT -> CurrentPlayingType.UP_NEXT
            }
        }
    return PlayerState(
        currentTrack = currentTrack,
        currentPosition = position,
        totalDuration = duration,
        currentState = state,
        currentPlaylistId = currentPlaylistId?.let { Variant_NullType_String.create(it) },
        currentIndex = if (exo.currentMediaItemIndex >= 0) exo.currentMediaItemIndex.toDouble() else -1.0,
        currentPlayingType = playingType,
    )
}

// ── Actual queue ──────────────────────────────────────────────────────────

suspend fun TrackPlayerCore.getActualQueue(): List<TrackItem> = withPlayerContext { getActualQueueInternal() }

internal fun TrackPlayerCore.getActualQueueInternal(): List<TrackItem> {
    if (!isExoInitialized) return emptyList()
    val currentIndex = currentTrackIndex
    if (currentIndex < 0) return emptyList()

    val queue = ArrayList<TrackItem>(currentTracks.size + playNextStack.size + upNextQueue.size)

    // Tracks before current (include currentTrackIndex when a temp track is playing)
    val beforeEnd =
        if (currentTemporaryType != TrackPlayerCore.TemporaryType.NONE) {
            minOf(currentIndex + 1, currentTracks.size)
        } else {
            currentIndex
        }
    if (beforeEnd > 0) queue.addAll(currentTracks.subList(0, beforeEnd))

    // Current track
    getCurrentTrack()?.let { queue.add(it) }

    val currentId = exo.currentMediaItem?.mediaId?.let { extractTrackId(it) }

    // playNext — skip the currently playing track by ID (not position)
    if (currentTemporaryType == TrackPlayerCore.TemporaryType.PLAY_NEXT && currentId != null) {
        var skipped = false
        for (track in playNextStack) {
            if (!skipped && track.id == currentId) {
                skipped = true
                continue
            }
            queue.add(track)
        }
    } else if (currentTemporaryType != TrackPlayerCore.TemporaryType.PLAY_NEXT) {
        queue.addAll(playNextStack)
    }

    // upNext — skip the currently playing track by ID (not position)
    if (currentTemporaryType == TrackPlayerCore.TemporaryType.UP_NEXT && currentId != null) {
        var skipped = false
        for (track in upNextQueue) {
            if (!skipped && track.id == currentId) {
                skipped = true
                continue
            }
            queue.add(track)
        }
    } else if (currentTemporaryType != TrackPlayerCore.TemporaryType.UP_NEXT) {
        queue.addAll(upNextQueue)
    }

    // Remaining original tracks
    if (currentIndex + 1 < currentTracks.size) {
        queue.addAll(currentTracks.subList(currentIndex + 1, currentTracks.size))
    }
    return queue
}

// ── Index navigation ──────────────────────────────────────────────────────

suspend fun TrackPlayerCore.skipToIndex(index: Int): Boolean = withPlayerContext { skipToIndexInternal(index) }

private fun TrackPlayerCore.skipToIndexInternal(index: Int): Boolean {
    if (!isExoInitialized) return false
    val actualQueue = getActualQueueInternal()
    if (index < 0 || index >= actualQueue.size) return false

    val currentPos = if (currentTemporaryType != TrackPlayerCore.TemporaryType.NONE) currentTrackIndex + 1 else currentTrackIndex
    val effectivePlayNextSize = if (currentTemporaryType == TrackPlayerCore.TemporaryType.PLAY_NEXT) maxOf(0, playNextStack.size - 1) else playNextStack.size
    val effectiveUpNextSize = if (currentTemporaryType == TrackPlayerCore.TemporaryType.UP_NEXT) maxOf(0, upNextQueue.size - 1) else upNextQueue.size

    val playNextStart = currentPos + 1
    val playNextEnd = playNextStart + effectivePlayNextSize
    val upNextStart = playNextEnd
    val upNextEnd = upNextStart + effectiveUpNextSize
    val originalRemainingStart = upNextEnd

    if (index < currentPos) {
        playFromIndexInternal(index)
        return true
    }
    if (index == currentPos) {
        exo.seekTo(0)
        return true
    }

    if (index in playNextStart until playNextEnd) {
        val targetTrack = actualQueue[index]
        // Remove all playNext tracks before the target (by ID lookup, not position)
        val targetIdx = playNextStack.indexOfFirst { it.id == targetTrack.id }
        if (targetIdx > 0) playNextStack.subList(0, targetIdx).clear()
        rebuildQueueFromCurrentPosition()
        exo.seekToNext()
        return true
    }

    if (index in upNextStart until upNextEnd) {
        val targetTrack = actualQueue[index]
        playNextStack.clear()
        // Remove all upNext tracks before the target (by ID lookup, not position)
        val targetIdx = upNextQueue.indexOfFirst { it.id == targetTrack.id }
        if (targetIdx > 0) upNextQueue.subList(0, targetIdx).clear()
        rebuildQueueFromCurrentPosition()
        exo.seekToNext()
        return true
    }

    if (index >= originalRemainingStart) {
        val targetTrack = actualQueue[index]
        val originalIndex = currentTracks.indexOfFirst { it.id == targetTrack.id }
        if (originalIndex == -1) return false
        playNextStack.clear()
        upNextQueue.clear()
        currentTemporaryType = TrackPlayerCore.TemporaryType.NONE
        rebuildQueueAndPlayFromIndex(originalIndex)
        checkUpcomingTracksForUrls(lookaheadCount)
        return true
    }

    checkUpcomingTracksForUrls(lookaheadCount)
    return false
}

suspend fun TrackPlayerCore.playFromIndex(index: Int) = withPlayerContext { playFromIndexInternal(index) }

internal fun TrackPlayerCore.playFromIndexInternal(index: Int) {
    playNextStack.clear()
    upNextQueue.clear()
    currentTemporaryType = TrackPlayerCore.TemporaryType.NONE
    rebuildQueueAndPlayFromIndex(index)
}
