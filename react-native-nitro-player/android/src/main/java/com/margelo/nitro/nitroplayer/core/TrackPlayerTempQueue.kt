@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import com.margelo.nitro.nitroplayer.TrackItem

/**
 * Temporary queue management (playNext stack + upNext queue) and playlist loading.
 * All public functions are suspend and execute on the player thread.
 */

// ── Playlist loading ──────────────────────────────────────────────────────

suspend fun TrackPlayerCore.loadPlaylist(
    playlistId: String,
    startIndex: Int? = null,
) = withPlayerContext { loadPlaylistOnQueue(playlistId, startIndex) }

internal fun TrackPlayerCore.loadPlaylistOnQueue(
    playlistId: String,
    startIndex: Int? = null,
) {
    run {
        playNextStack.clear()
        upNextQueue.clear()
        currentTemporaryType = TrackPlayerCore.TemporaryType.NONE
        val playlist = playlistManager.getPlaylist(playlistId) ?: return@run

        val targetIndex =
            if (startIndex != null) {
                if (startIndex < 0 || startIndex >= playlist.tracks.size) return@run
                startIndex
            } else {
                0
            }

        currentPlaylistId = playlistId
        if (targetIndex == 0) {
            updatePlayerQueue(playlist.tracks)
        } else {
            // Bypass updatePlayerQueue to avoid emitting a spurious onTrackChange for index 0.
            // Set currentTracks directly so rebuildQueueAndPlayFromIndex can use them.
            currentTracks = playlist.tracks
            rebuildQueueAndPlayFromIndex(targetIndex)
        }
        checkUpcomingTracksForUrls(lookaheadCount)
        notifyTemporaryQueueChange()
    }
}

/**
 * Debounced update — coalesces rapid back-to-back mutations into one player rebuild.
 * Called by HybridPlayerQueue when playlist data changes.
 */
fun TrackPlayerCore.updatePlaylist(playlistId: String) {
    if (currentPlaylistId != playlistId) return
    playerHandler.removeCallbacks(updateCurrentPlaylistRunnable)
    playerHandler.post(updateCurrentPlaylistRunnable)
}

// ── playNext (LIFO) ────────────────────────────────────────────────────────

suspend fun TrackPlayerCore.playNext(trackId: String) = withPlayerContext { playNextInternal(trackId) }

internal fun TrackPlayerCore.playNextInternal(trackId: String) {
    val track =
        findTrackById(trackId)
            ?: throw IllegalArgumentException("Track $trackId not found")
    playNextStack.add(0, track)
    syncQueueAfterTempEdit()
    notifyTemporaryQueueChange()
}

// ── addToUpNext (FIFO) ────────────────────────────────────────────────────

suspend fun TrackPlayerCore.addToUpNext(trackId: String) = withPlayerContext { addToUpNextInternal(trackId) }

internal fun TrackPlayerCore.addToUpNextInternal(trackId: String) {
    val track =
        findTrackById(trackId)
            ?: throw IllegalArgumentException("Track $trackId not found")
    upNextQueue.add(track)
    syncQueueAfterTempEdit()
    notifyTemporaryQueueChange()
}

// ── Remove / clear ────────────────────────────────────────────────────────

suspend fun TrackPlayerCore.removeFromPlayNext(trackId: String): Boolean = withPlayerContext { removeFromPlayNextOnQueue(trackId) }

internal fun TrackPlayerCore.removeFromPlayNextOnQueue(trackId: String): Boolean {
    val idx = playNextStack.indexOfFirst { it.id == trackId }
    if (idx < 0) return false
    playNextStack.removeAt(idx)
    syncQueueAfterTempEdit()
    notifyTemporaryQueueChange()
    return true
}

suspend fun TrackPlayerCore.removeFromUpNext(trackId: String): Boolean = withPlayerContext { removeFromUpNextOnQueue(trackId) }

internal fun TrackPlayerCore.removeFromUpNextOnQueue(trackId: String): Boolean {
    val idx = upNextQueue.indexOfFirst { it.id == trackId }
    if (idx < 0) return false
    upNextQueue.removeAt(idx)
    syncQueueAfterTempEdit()
    notifyTemporaryQueueChange()
    return true
}

suspend fun TrackPlayerCore.clearPlayNext() = withPlayerContext { clearPlayNextOnQueue() }

internal fun TrackPlayerCore.clearPlayNextOnQueue() {
    playNextStack.clear()
    syncQueueAfterTempEdit()
    notifyTemporaryQueueChange()
}

suspend fun TrackPlayerCore.clearUpNext() = withPlayerContext { clearUpNextOnQueue() }

internal fun TrackPlayerCore.clearUpNextOnQueue() {
    upNextQueue.clear()
    syncQueueAfterTempEdit()
    notifyTemporaryQueueChange()
}

// ── Reorder ───────────────────────────────────────────────────────────────

/**
 * Reorder within the combined virtual list [playNextStack + upNextQueue].
 * newIndex is 0-based within that combined list.
 */
suspend fun TrackPlayerCore.reorderTemporaryTrack(
    trackId: String,
    newIndex: Int,
): Boolean = withPlayerContext { reorderTemporaryTrackOnQueue(trackId, newIndex) }

internal fun TrackPlayerCore.reorderTemporaryTrackOnQueue(
    trackId: String,
    newIndex: Int,
): Boolean {
    val combined = (playNextStack + upNextQueue).toMutableList()
    val fromIdx = combined.indexOfFirst { it.id == trackId }
    if (fromIdx < 0) return false
    val track = combined.removeAt(fromIdx)
    val clampedIndex = newIndex.coerceIn(0, combined.size)
    combined.add(clampedIndex, track)

    // Split back at original playNextStack.size boundary (reduced if an item was moved out)
    val pnSize = playNextStack.size
    playNextStack.clear()
    upNextQueue.clear()
    playNextStack.addAll(combined.take(pnSize))
    upNextQueue.addAll(combined.drop(pnSize))

    syncQueueAfterTempEdit()
    notifyTemporaryQueueChange()
    return true
}

// ── Read-only accessors ────────────────────────────────────────────────────

suspend fun TrackPlayerCore.getPlayNextQueue(): List<TrackItem> = withPlayerContext { playNextStack.toList() }

suspend fun TrackPlayerCore.getUpNextQueue(): List<TrackItem> = withPlayerContext { upNextQueue.toList() }

/** Applies a temporary-queue edit to the live queue, or to the Cast queue still waiting on its URLs. */
private fun TrackPlayerCore.syncQueueAfterTempEdit() {
    if (!isExoInitialized) return
    when {
        // The receiver hasn't reported a queue change yet (its timeline is stale); that report applies this edit
        isCastingField && castLoadInFlight -> Unit
        exo.currentMediaItem != null -> rebuildQueueFromCurrentPosition()
        isCastingField && castPendingList != null -> refreshCastPendingList()
    }
}
