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
 *
 * Cast mode: a Cast receiver auto-advances past items it fails to load (unlike
 * ExoPlayer, which errors and waits — the behaviour the lazy-URL flow relies on).
 * So while casting we only ever enqueue the contiguous prefix of *castable* tracks
 * (non-empty remote URLs); unresolved tracks are requested via onTracksNeedUpdate
 * and the cast queue is reloaded once updateTracks supplies their URLs.
 */

// ── Cast-safety helpers ────────────────────────────────────────────────────

/** A track the Cast receiver can actually load: non-empty remote (non-local) URL. */
internal fun TrackPlayerCore.isTrackCastable(track: TrackItem): Boolean =
    track.url.isNotEmpty() &&
        !track.url.startsWith("/") &&
        !track.url.startsWith("file:")

/**
 * The run of tracks safe to enqueue on the receiver:
 * - castable tracks are kept;
 * - local-only tracks (downloaded file paths — nothing will ever resolve them
 *   remotely) are skipped, mirroring the receiver's own fail-and-advance;
 * - the first lazy track (empty URL) STOPS the run — its URL resolution is coming
 *   via onTracksNeedUpdate/updateTracks, which then extends/reloads the queue.
 */
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
            // Target's URL is not resolved yet (lazy). Silence the receiver and wait —
            // updateTracks reloads once onTracksNeedUpdate supplies the URL. Dedup the
            // announcement so re-entries while still unresolved don't spam JS.
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

    val mediaItems =
        currentTracks.subList(index, currentTracks.size).map { track ->
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
        // Only receiver-loadable tracks may follow the current item remotely.
        newQueueTracks = castableUpcoming(newQueueTracks)

        // Every queue edit is a receiver RPC — skip the rebuild entirely when the
        // remote queue already matches the desired upcoming list.
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

    val newMediaItems = newQueueTracks.map { makeMediaItem(it, mediaIdFor(it)) }

    if (exo.mediaItemCount > currentIndex + 1) {
        exo.removeMediaItems(currentIndex + 1, exo.mediaItemCount)
    }
    exo.addMediaItems(newMediaItems)
}

/**
 * The desired upcoming track list after the currently playing track:
 * [playNext stack] + [upNext queue] + [remaining original tracks], with the
 * currently playing temp track (identified by [currentId]) skipped from its list.
 */
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
            // First track has no castable URL yet — silence the receiver and wait for
            // updateTracks to supply URLs (JS is notified via onTracksNeedUpdate).
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

    val mediaItems = tracks.map { makeMediaItem(it, mediaIdFor(it)) }
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

    // Cast: the receiver fetches the media itself, so a downloaded track's local
    // path is unplayable there — always hand it the remote URL while casting.
    val effectiveUrl = if (isCastingField) track.url else downloadManager.getEffectiveUrl(track)

    // Register custom HTTP headers (e.g. Authorization) from extraPayload.headers so they are
    // injected into the request for this URL. Applies to remote streams only — see ExoPlayerBuilder.
    track.extraPayload?.let { payload ->
        try {
            val headersRaw = payload.toHashMap()["headers"]
            if (headersRaw is Map<*, *>) {
                val headers = headersRaw
                    .mapNotNull { (k, v) -> if (k is String && v is String) k to v else null }
                    .toMap()
                if (headers.isNotEmpty()) {
                    com.margelo.nitro.nitroplayer.media.AuthAwareHttpDataSourceFactory
                        .setHeadersForUrl(effectiveUrl, headers)
                }
            }
        } catch (_: Exception) {}
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
