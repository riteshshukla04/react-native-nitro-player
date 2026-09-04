@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import com.margelo.nitro.nitroplayer.TrackItem
import kotlin.random.Random

internal fun TrackPlayerCore.seedShuffleOrder(
    tracks: List<TrackItem>,
    firstId: String? = null,
) {
    val rest = tracks.map { it.id }.filter { it != firstId }.shuffled()
    shuffleOrder = (listOfNotNull(firstId) + rest).toMutableList()
}

/** Identity when shuffle is off; otherwise reorders [tracks] by [shuffleOrder] — stale ids drop out, new ids join a random upcoming slot. */
internal fun TrackPlayerCore.applyShuffleOrder(tracks: List<TrackItem>): List<TrackItem> {
    if (!shuffleEnabled) return tracks
    val byId = tracks.associateBy { it.id } // ponytail: duplicate ids collapse to one entry, already unsupported everywhere else
    shuffleOrder.retainAll(byId.keys)
    val known = shuffleOrder.toHashSet()
    val lo = (currentTrackIndex + 1).coerceIn(0, shuffleOrder.size)
    for (track in tracks) {
        if (known.add(track.id)) shuffleOrder.add(Random.nextInt(lo, shuffleOrder.size + 1), track.id)
    }
    return shuffleOrder.mapNotNull { byId[it] }
}

private fun TrackPlayerCore.applyShuffleState() {
    val source = currentPlaylistId?.let { playlistManager.getPlaylist(it)?.tracks } ?: currentTracks
    val anchorId = currentTracks.getOrNull(currentTrackIndex)?.id
    if (shuffleEnabled) seedShuffleOrder(source, anchorId)
    currentTracks = applyShuffleOrder(source)
    currentTrackIndex = anchorId?.let { id -> currentTracks.indexOfFirst { it.id == id } } ?: -1
    if (isExoInitialized && exo.currentMediaItem != null) rebuildQueueFromCurrentPosition()
    checkUpcomingTracksForUrls(lookaheadCount)
    // Mirror into the local ExoPlayer only (CastPlayer ignores it); the order itself is ours, see ExoPlayerBuilder.
    val local = castSessionController?.localPlayer ?: if (isExoInitialized) exo.player else null
    if (local != null && local.shuffleModeEnabled != shuffleEnabled) local.shuffleModeEnabled = shuffleEnabled
    notifyShuffleChange(shuffleEnabled)
}

internal fun TrackPlayerCore.setShuffleModeOnQueue(enabled: Boolean) {
    if (enabled == shuffleEnabled) return
    shuffleEnabled = enabled
    applyShuffleState()
}

internal fun TrackPlayerCore.reshuffleOnQueue() {
    shuffleEnabled = true
    applyShuffleState()
}

fun TrackPlayerCore.getShuffleMode(): Boolean = shuffleEnabled
