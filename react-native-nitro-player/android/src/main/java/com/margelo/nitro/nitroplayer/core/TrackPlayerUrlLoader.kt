@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import androidx.media3.common.Player
import com.margelo.nitro.nitroplayer.TrackItem

/**
 * Lazy URL loading support, track queries, and playback speed.
 * All public functions are suspend and execute on the player thread.
 */

// ── Track updates (URL resolution) ────────────────────────────────────────

suspend fun TrackPlayerCore.updateTracks(tracks: List<TrackItem>) =
    withPlayerContext {
        val currentTrack = getCurrentTrack()
        val currentTrackId = currentTrack?.id
        val currentTrackIsEmpty = currentTrack?.url.isNullOrEmpty()
        val currentTrackUpdate = if (currentTrackId != null) tracks.find { it.id == currentTrackId } else null

        val safeTracks =
            tracks.filter { track ->
                when {
                    track.id == currentTrackId && !currentTrackIsEmpty -> false

                    // preserve gapless
                    track.id == currentTrackId && currentTrackIsEmpty -> track.url.isNotEmpty()

                    track.url.isEmpty() -> false

                    else -> true
                }
            }
        if (safeTracks.isEmpty()) return@withPlayerContext

        val affectedPlaylists: Map<String, Int> = playlistManager.updateTracks(safeTracks)

        // Replace current track's MediaItem if it was empty-URL and now has a URL
        if (currentTrackUpdate != null && currentTrackIsEmpty && currentTrackUpdate.url.isNotEmpty()) {
            val exoIndex = exo.currentMediaItemIndex
            if (exoIndex >= 0) {
                val playlistId = currentPlaylistId ?: ""
                val mediaId = if (playlistId.isNotEmpty()) "$playlistId:${currentTrackUpdate.id}" else currentTrackUpdate.id
                exo.replaceMediaItem(exoIndex, makeMediaItem(currentTrackUpdate, mediaId))
                if (exo.playbackState == Player.STATE_IDLE) exo.prepare()
            }
        }

        if (currentPlaylistId != null && affectedPlaylists.containsKey(currentPlaylistId)) {
            val refreshedPlaylist = playlistManager.getPlaylist(currentPlaylistId!!)
            if (refreshedPlaylist != null) {
                currentTracks = refreshedPlaylist.tracks
                val updatedById = currentTracks.associateBy { it.id }
                playNextStack.forEachIndexed { i, t -> updatedById[t.id]?.let { if (it !== t) playNextStack[i] = it } }
                upNextQueue.forEachIndexed { i, t -> updatedById[t.id]?.let { if (it !== t) upNextQueue[i] = it } }
            }
            rebuildQueueFromCurrentPosition()
        }
    }

// ── Track queries ─────────────────────────────────────────────────────────

suspend fun TrackPlayerCore.getTracksById(trackIds: List<String>): List<TrackItem> = withPlayerContext { playlistManager.getTracksById(trackIds) as List<TrackItem> }

suspend fun TrackPlayerCore.getTracksNeedingUrls(): List<TrackItem> = withPlayerContext { getTracksNeedingUrlsInternal() }

internal fun TrackPlayerCore.getTracksNeedingUrlsInternal(): List<TrackItem> {
    val pid = currentPlaylistId ?: return emptyList()
    return playlistManager.getPlaylist(pid)?.tracks?.filter { it.url.isEmpty() } ?: emptyList()
}

suspend fun TrackPlayerCore.getNextTracks(count: Int): List<TrackItem> = withPlayerContext { getNextTracksInternal(count) }

internal fun TrackPlayerCore.getNextTracksInternal(count: Int): List<TrackItem> {
    val actualQueue = getActualQueueInternal()
    if (actualQueue.isEmpty()) return emptyList()
    val currentIdx = actualQueue.indexOfFirst { it.id == getCurrentTrack()?.id }
    if (currentIdx == -1) return emptyList()
    val start = currentIdx + 1
    val end = minOf(start + count, actualQueue.size)
    return if (start < actualQueue.size) actualQueue.subList(start, end) else emptyList()
}

suspend fun TrackPlayerCore.getCurrentTrackIndex(): Int = withPlayerContext { currentTrackIndex }

// ── URL lookahead ─────────────────────────────────────────────────────────

internal fun TrackPlayerCore.checkUpcomingTracksForUrls(lookahead: Int = 5) {
    val upcomingTracks =
        if (currentTrackIndex < 0) {
            currentTracks.take(lookahead)
        } else {
            getNextTracksInternal(lookahead)
        }
    val currentTrack = getCurrentTrack()
    val currentNeedsUrl = currentTrack != null && currentTrack.url.isEmpty()
    val candidates = if (currentNeedsUrl) listOf(currentTrack!!) + upcomingTracks else upcomingTracks
    val needUrls = candidates.filter { it.url.isEmpty() }
    if (needUrls.isNotEmpty()) notifyTracksNeedUpdate(needUrls, lookahead)
}
