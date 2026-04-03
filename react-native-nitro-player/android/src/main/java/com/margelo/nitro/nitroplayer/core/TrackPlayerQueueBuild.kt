@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import com.margelo.nitro.nitroplayer.TrackItem

/**
 * Queue-building helpers — called exclusively on the player thread.
 * Surgical rebuild (removeMediaItems + addMediaItems) preserves the current item
 * for gapless playback; full rebuild (clearMediaItems + setMediaItems) is used only
 * when jumping to a specific index.
 */

// ── Full rebuild (jump to index) ───────────────────────────────────────────

internal fun TrackPlayerCore.rebuildQueueAndPlayFromIndex(index: Int) {
    if (!isExoInitialized) return
    if (index < 0 || index >= currentTracks.size) return

    val playlistId = currentPlaylistId ?: ""
    val mediaItems =
        currentTracks.subList(index, currentTracks.size).map { track ->
            val mediaId = if (playlistId.isNotEmpty()) "$playlistId:${track.id}" else track.id
            makeMediaItem(track, mediaId)
        }

    currentTrackIndex = index
    exo.clearMediaItems()
    exo.setMediaItems(mediaItems)
    exo.seekToDefaultPosition(0)
    exo.playWhenReady = true
    exo.prepare()
}

// ── Surgical rebuild (preserve current item) ──────────────────────────────

internal fun TrackPlayerCore.rebuildQueueFromCurrentPosition() {
    if (!isExoInitialized) return
    val currentIndex = exo.currentMediaItemIndex
    if (currentIndex < 0) return

    // If current track was removed from the playlist, jump to best substitute
    val currentTrackId = exo.currentMediaItem?.mediaId?.let { extractTrackId(it) }

    if (
        currentTrackId != null && 
        currentTracks.none { it.id == currentTrackId } &&
        currentTemporaryType == TrackPlayerCore.TemporaryType.NONE
    ) {
        if (currentTracks.isEmpty()) return
        playFromIndexInternal(minOf(currentTrackIndex, currentTracks.size - 1))
        return
    }

    // Keep the logical playlist pointer in sync after playlist mutations.
    // Without this, getActualQueue/getState can report a stale index until the next track transition.
    if (currentTemporaryType == TrackPlayerCore.TemporaryType.NONE && currentTrackId != null) {
        val resolvedIndex = currentTracks.indexOfFirst { it.id == currentTrackId }
        if (resolvedIndex >= 0) {
            currentTrackIndex = resolvedIndex
        }
    }

    val newQueueTracks = ArrayList<TrackItem>(playNextStack.size + upNextQueue.size + currentTracks.size)
    val currentId = exo.currentMediaItem?.mediaId?.let { extractTrackId(it) }

    // playNext stack — skip the currently playing track by ID (not position)
    if (currentTemporaryType == TrackPlayerCore.TemporaryType.PLAY_NEXT && currentId != null) {
        var skipped = false
        for (track in playNextStack) {
            if (!skipped && track.id == currentId) {
                skipped = true
                continue
            }
            newQueueTracks.add(track)
        }
    } else if (currentTemporaryType != TrackPlayerCore.TemporaryType.PLAY_NEXT) {
        newQueueTracks.addAll(playNextStack)
    }

    // upNext queue — skip the currently playing track by ID (not position)
    if (currentTemporaryType == TrackPlayerCore.TemporaryType.UP_NEXT && currentId != null) {
        var skipped = false
        for (track in upNextQueue) {
            if (!skipped && track.id == currentId) {
                skipped = true
                continue
            }
            newQueueTracks.add(track)
        }
    } else if (currentTemporaryType != TrackPlayerCore.TemporaryType.UP_NEXT) {
        newQueueTracks.addAll(upNextQueue)
    }

    // Remaining original tracks (after currentTrackIndex, not after ExoPlayer's currentIndex)
    if (currentTrackIndex + 1 < currentTracks.size) {
        newQueueTracks.addAll(currentTracks.subList(currentTrackIndex + 1, currentTracks.size))
    }

    val playlistId = currentPlaylistId ?: ""
    val newMediaItems =
        newQueueTracks.map { track ->
            val mediaId = if (playlistId.isNotEmpty()) "$playlistId:${track.id}" else track.id
            makeMediaItem(track, mediaId)
        }

    if (exo.mediaItemCount > currentIndex + 1) {
        exo.removeMediaItems(currentIndex + 1, exo.mediaItemCount)
    }
    exo.addMediaItems(newMediaItems)
}

// ── Full queue set (initial load or no active item) ───────────────────────

internal fun TrackPlayerCore.updatePlayerQueue(tracks: List<TrackItem>) {
    currentTracks = tracks
    val playlistId = currentPlaylistId ?: ""
    val mediaItems =
        tracks.map { track ->
            val mediaId = if (playlistId.isNotEmpty()) "$playlistId:${track.id}" else track.id
            makeMediaItem(track, mediaId)
        }
    exo.setMediaItems(mediaItems, false)
    if (exo.playbackState == Player.STATE_IDLE && mediaItems.isNotEmpty()) {
        exo.prepare()
    }
}

// ── MediaItem construction (member extension to access downloadManager) ────

internal fun TrackPlayerCore.makeMediaItem(
    track: TrackItem,
    customMediaId: String? = null,
): MediaItem {
    val metaBuilder =
        MediaMetadata
            .Builder()
            .setTitle(track.title)
            .setArtist(track.artist)
            .setAlbumTitle(track.album)

    track.artwork?.asSecondOrNull()?.let { artworkUrl ->
        try {
            metaBuilder.setArtworkUri(Uri.parse(artworkUrl))
        } catch (_: Exception) {
        }
    }

    val effectiveUrl = downloadManager.getEffectiveUrl(track)

    return MediaItem
        .Builder()
        .setMediaId(customMediaId ?: track.id)
        .setUri(effectiveUrl)
        .setMediaMetadata(metaBuilder.build())
        .build()
}

// ── Track lookup helpers ───────────────────────────────────────────────────

internal fun TrackPlayerCore.findTrack(mediaItem: MediaItem?): TrackItem? {
    if (mediaItem == null) return null
    val trackId = extractTrackId(mediaItem.mediaId)
    return currentTracks.find { it.id == trackId }
}

internal fun TrackPlayerCore.findTrackById(trackId: String): TrackItem? {
    currentTracks.find { it.id == trackId }?.let { return it }
    for (playlist in playlistManager.getAllPlaylists()) {
        playlist.tracks.find { it.id == trackId }?.let { return it }
    }
    return null
}

internal fun TrackPlayerCore.getCurrentTrack(): TrackItem? {
    if (!isExoInitialized) return null
    val currentMediaItem = exo.currentMediaItem ?: return null
    if (currentTemporaryType != TrackPlayerCore.TemporaryType.NONE) {
        val trackId = extractTrackId(currentMediaItem.mediaId)
        return when (currentTemporaryType) {
            TrackPlayerCore.TemporaryType.PLAY_NEXT -> playNextStack.firstOrNull { it.id == trackId }
            TrackPlayerCore.TemporaryType.UP_NEXT -> upNextQueue.firstOrNull { it.id == trackId }
            else -> null
        }
    }
    return findTrack(currentMediaItem)
}

internal fun TrackPlayerCore.determineCurrentTemporaryType(): TrackPlayerCore.TemporaryType {
    val currentItem = exo.currentMediaItem ?: return TrackPlayerCore.TemporaryType.NONE
    val trackId = extractTrackId(currentItem.mediaId)
    if (playNextStack.any { it.id == trackId }) return TrackPlayerCore.TemporaryType.PLAY_NEXT
    if (upNextQueue.any { it.id == trackId }) return TrackPlayerCore.TemporaryType.UP_NEXT
    return TrackPlayerCore.TemporaryType.NONE
}

internal fun TrackPlayerCore.extractTrackId(mediaId: String): String = if (mediaId.contains(':')) mediaId.substring(mediaId.indexOf(':') + 1) else mediaId
