@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import androidx.media3.common.Player
import com.margelo.nitro.nitroplayer.TrackItem

/**
 * Lazy URL loading support, track queries, and playback speed.
 * All public functions are suspend and execute on the player thread.
 */

// ── Track updates (URL resolution) ────────────────────────────────────────

suspend fun TrackPlayerCore.updateTracks(tracks: List<TrackItem>) = withPlayerContext { updateTracksOnQueue(tracks) }

internal fun TrackPlayerCore.updateTracksOnQueue(tracks: List<TrackItem>) {
    run {
        val currentTrack = getCurrentTrack()
        val currentTrackId = currentTrack?.id
        val currentTrackIsEmpty = currentTrack?.url.isNullOrEmpty()
        val currentTrackUpdate = if (currentTrackId != null) tracks.find { it.id == currentTrackId } else null

        val safeTracks =
            tracks.filter { track ->
                when {
                    // Same URL is a metadata-only edit (a title or artwork refresh): it reaches
                    // the session without touching the media, so gapless is unaffected.
                    track.id == currentTrackId && !currentTrackIsEmpty -> track.url == currentTrack?.url

                    // preserve gapless
                    track.id == currentTrackId && currentTrackIsEmpty -> track.url.isNotEmpty()

                    track.url.isEmpty() -> false

                    else -> true
                }
            }
        if (safeTracks.isEmpty()) return@run

        val affectedPlaylists: Map<String, Int> = playlistManager.updateTracks(safeTracks)

        // Replace the current MediaItem when its URL just resolved (local only — the cast branch below reloads instead).
        val currentTrackResolvedNow = currentTrackUpdate != null && currentTrackIsEmpty && currentTrackUpdate.url.isNotEmpty()
        val currentMetadataChanged =
            currentTrackUpdate != null && !currentTrackIsEmpty && currentTrackUpdate.url == currentTrack?.url
        if (!isCastingField && (currentTrackResolvedNow || currentMetadataChanged)) {
            val exoIndex = exo.currentMediaItemIndex
            if (exoIndex >= 0) {
                val playlistId = currentPlaylistId ?: ""
                val mediaId = if (playlistId.isNotEmpty()) "$playlistId:${currentTrackUpdate!!.id}" else currentTrackUpdate!!.id
                exo.replaceMediaItem(exoIndex, makeMediaItem(currentTrackUpdate, mediaId))
                if (exo.playbackState == Player.STATE_IDLE) exo.prepare()
            }
        }

        if (currentPlaylistId != null && affectedPlaylists.containsKey(currentPlaylistId)) {
            val refreshedPlaylist = playlistManager.getPlaylist(currentPlaylistId!!)
            if (refreshedPlaylist != null) {
                assignCurrentTracks(refreshedPlaylist.tracks)
                val updatedById = currentTracks.associateBy { it.id }
                playNextStack.forEachIndexed { i, t -> updatedById[t.id]?.let { if (it !== t) playNextStack[i] = it } }
                upNextQueue.forEachIndexed { i, t -> updatedById[t.id]?.let { if (it !== t) upNextQueue[i] = it } }
            }

            if (isCastingField) {
                // Resolved current track (or empty receiver) → atomic reload from the current index; otherwise resync only the upcoming items.
                if (currentTrackResolvedNow || exo.mediaItemCount == 0) {
                    rebuildQueueAndPlayFromIndex(currentTrackIndex)
                } else {
                    rebuildQueueFromCurrentPosition()
                }
                return@run
            }

            rebuildQueueFromCurrentPosition()
        }
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

/**
 * Walks the queue structure directly instead of materializing the whole queue — this
 * runs on every skip and every progress tick, so it must not be O(playlist) just to
 * read the next few tracks.
 */
internal fun TrackPlayerCore.getNextTracksInternal(count: Int): List<TrackItem> {
    if (count <= 0) return emptyList()
    val out = ArrayList<TrackItem>(count)
    val currentId = if (isExoInitialized) exo.currentMediaItem?.mediaId?.let { extractTrackId(it) } else null

    var skippedPlayNext = currentTemporaryType != TrackPlayerCore.TemporaryType.PLAY_NEXT
    for (track in playNextStack) {
        if (!skippedPlayNext && track.id == currentId) {
            skippedPlayNext = true
            continue
        }
        out.add(track)
        if (out.size == count) return out
    }

    var skippedUpNext = currentTemporaryType != TrackPlayerCore.TemporaryType.UP_NEXT
    for (track in upNextQueue) {
        if (!skippedUpNext && track.id == currentId) {
            skippedUpNext = true
            continue
        }
        out.add(track)
        if (out.size == count) return out
    }

    var index = currentTrackIndex + 1
    while (index < currentTracks.size && out.size < count) {
        out.add(currentTracks[index])
        index++
    }
    return out
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
