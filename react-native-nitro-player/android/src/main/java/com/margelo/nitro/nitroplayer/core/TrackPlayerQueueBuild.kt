@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import com.margelo.nitro.nitroplayer.Reason
import com.margelo.nitro.nitroplayer.TrackItem

/**
 * Queue-building helpers — called exclusively on the player thread.
 * Surgical rebuild (removeMediaItems + addMediaItems) preserves the current item
 * for gapless playback; full rebuild (clearMediaItems + setMediaItems) is used only
 * when jumping to a specific index.
 */

// ── Cast-safety helpers ────────────────────────────────────────────────────

/** A track the Cast receiver can actually load: non-empty remote (non-local) URL. */
internal fun TrackPlayerCore.isTrackCastable(track: TrackItem): Boolean =
    track.url.isNotEmpty() &&
        !track.url.startsWith("/") &&
        !track.url.startsWith("file:")

/** Receiver-safe run: keeps castable tracks, skips local-only ones, stops at the first lazy (empty-URL) track whose resolution is pending — receivers auto-skip failed loads instead of waiting like ExoPlayer. */
internal fun TrackPlayerCore.castableUpcoming(tracks: List<TrackItem>): List<TrackItem> {
    val result = ArrayList<TrackItem>(tracks.size)
    for (track in tracks) {
        when {
            isTrackCastable(track) -> result.add(track)
            track.url.isEmpty() -> break
            // local-only → skip and keep scanning
        }
    }
    return result
}

/**
 * Upcoming MediaItems kept materialized behind the current one. The logical queue
 * (currentTracks + temp lists) stays complete; only ExoPlayer's timeline is windowed,
 * and it is topped up on every item transition. Building a MediaItem is not free —
 * each one resolves the effective URL, which used to stat() the download record.
 */
internal const val QUEUE_WINDOW_SIZE = 4

internal fun TrackPlayerCore.mediaIdFor(track: TrackItem): String {
    val playlistId = currentPlaylistId ?: ""
    return if (playlistId.isNotEmpty()) "$playlistId:${track.id}" else track.id
}

// ── Full rebuild (jump to index) ───────────────────────────────────────────

internal fun TrackPlayerCore.rebuildQueueAndPlayFromIndex(index: Int) {
    if (!isExoInitialized) return
    if (index < 0 || index >= currentTracks.size) return

    if (isCastingField) {
        currentTrackIndex = index
        val target = currentTracks[index]
        val castTracks = castableUpcoming(currentTracks.subList(index, currentTracks.size))
        if (castTracks.isEmpty()) {
            // Lazy target — silence the receiver and wait for updateTracks to reload (dedup so re-entries don't spam JS).
            if (exo.mediaItemCount > 0) exo.clearMediaItems()
            if (lastCastWaitTrackId != target.id) {
                lastCastWaitTrackId = target.id
                notifyTrackChange(target, Reason.SKIP)
            }
            checkUpcomingTracksForUrls(lookaheadCount)
            return
        }
        lastCastWaitTrackId = null
        // Single atomic queueLoad — no separate clear (each queue op is a receiver RPC).
        exo.setMediaItems(castTracks.map { makeMediaItem(it, mediaIdFor(it)) }, true)
        exo.prepare()
        checkUpcomingTracksForUrls(lookaheadCount)
        return
    }

    val windowEnd = minOf(index + 1 + QUEUE_WINDOW_SIZE, currentTracks.size)
    val mediaItems =
        currentTracks.subList(index, windowEnd).map { track ->
            makeMediaItem(track, mediaIdFor(track))
        }

    currentTrackIndex = index
    exo.clearMediaItems()
    exo.setMediaItems(mediaItems, true)
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

    val currentId = exo.currentMediaItem?.mediaId?.let { extractTrackId(it) }
    var newQueueTracks: List<TrackItem> = buildUpcomingQueueTracks(currentId)

    if (isCastingField) {
        newQueueTracks = castableUpcoming(newQueueTracks)

        // Every queue edit is a receiver RPC — skip the rebuild when the remote queue already matches.
        val itemCount = exo.mediaItemCount
        if (itemCount - currentIndex - 1 == newQueueTracks.size) {
            var inSync = true
            for (i in newQueueTracks.indices) {
                val existingId = extractTrackId(exo.getMediaItemAt(currentIndex + 1 + i).mediaId)
                if (existingId != newQueueTracks[i].id) {
                    inSync = false
                    break
                }
            }
            if (inSync) return
        }
    }

    // Window the materialized timeline; onMediaItemTransition tops it back up.
    // NOT while casting: the receiver holds the whole queue (rebuildQueueAndPlayFromIndex
    // loads it unwindowed), so truncating here would cut it down to the window size.
    if (!isCastingField && newQueueTracks.size > QUEUE_WINDOW_SIZE) {
        newQueueTracks = newQueueTracks.subList(0, QUEUE_WINDOW_SIZE)
    }

    // Keep the longest matching prefix of already-buffered items and rebuild only from
    // the first divergence. A pure append (the common window top-up) touches nothing
    // ExoPlayer has already prepared, so gapless transitions survive.
    val existingCount = exo.mediaItemCount - currentIndex - 1
    var commonPrefix = 0
    while (commonPrefix < existingCount && commonPrefix < newQueueTracks.size &&
        extractTrackId(exo.getMediaItemAt(currentIndex + 1 + commonPrefix).mediaId) == newQueueTracks[commonPrefix].id
    ) {
        commonPrefix++
    }

    if (exo.mediaItemCount > currentIndex + 1 + commonPrefix) {
        exo.removeMediaItems(currentIndex + 1 + commonPrefix, exo.mediaItemCount)
    }
    if (commonPrefix < newQueueTracks.size) {
        exo.addMediaItems(
            newQueueTracks.subList(commonPrefix, newQueueTracks.size).map { makeMediaItem(it, mediaIdFor(it)) },
        )
    }
}

/** Desired upcoming list after the current track: playNext + upNext + remaining originals, with the playing temp track ([currentId]) skipped. */
internal fun TrackPlayerCore.buildUpcomingQueueTracks(currentId: String?): List<TrackItem> {
    val newQueueTracks = ArrayList<TrackItem>(playNextStack.size + upNextQueue.size + currentTracks.size)

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

    // Remaining original tracks (after currentTrackIndex, not after the player's currentIndex)
    if (currentTrackIndex + 1 < currentTracks.size) {
        newQueueTracks.addAll(currentTracks.subList(currentTrackIndex + 1, currentTracks.size))
    }
    return newQueueTracks
}

// ── Full queue set (initial load or no active item) ───────────────────────

internal fun TrackPlayerCore.updatePlayerQueue(tracks: List<TrackItem>) {
    currentTracks = tracks

    if (isCastingField) {
        currentTrackIndex = 0
        val castTracks = castableUpcoming(tracks)
        if (castTracks.isEmpty()) {
            // Lazy first track — silence the receiver and wait for updateTracks to supply URLs.
            if (exo.mediaItemCount > 0) exo.clearMediaItems()
            val first = tracks.firstOrNull()
            if (first != null && lastCastWaitTrackId != first.id) {
                lastCastWaitTrackId = first.id
                notifyTrackChange(first, null)
            }
            checkUpcomingTracksForUrls(lookaheadCount)
            return
        }
        lastCastWaitTrackId = null
        exo.setMediaItems(castTracks.map { makeMediaItem(it, mediaIdFor(it)) }, true)
        exo.prepare()
        return
    }

    currentTrackIndex = 0
    val mediaItems = tracks.take(1 + QUEUE_WINDOW_SIZE).map { makeMediaItem(it, mediaIdFor(it)) }
    exo.setMediaItems(mediaItems, true)
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

    // The receiver fetches media itself, so local download paths are unplayable there — cast uses the remote URL.
    val effectiveUrl = if (isCastingField) track.url else downloadManager.getEffectiveUrl(track)

    // Register custom HTTP headers (e.g. Authorization) from extraPayload.headers so they are
    // injected into the request for this URL. Applies to remote streams only — see ExoPlayerBuilder.
    track.extraPayload?.let { payload ->
        try {
            val headersRaw = payload.toHashMap()["headers"]
            if (headersRaw is Map<*, *>) {
                val headers =
                    headersRaw
                        .mapNotNull { (k, v) -> if (k is String && v is String) k to v else null }
                        .toMap()
                if (headers.isNotEmpty()) {
                    com.margelo.nitro.nitroplayer.media.AuthAwareHttpDataSourceFactory
                        .setHeadersForUrl(effectiveUrl, headers)
                }
            }
        } catch (_: Exception) {
        }
    }

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
