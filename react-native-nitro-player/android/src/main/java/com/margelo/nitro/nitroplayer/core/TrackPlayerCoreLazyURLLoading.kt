@file:Suppress("ktlint:standard:max-line-length", "ktlint:standard:if-else-wrapping")

package com.margelo.nitro.nitroplayer.core

import com.margelo.nitro.nitroplayer.TrackItem
import java.lang.ref.WeakReference
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

// MARK: - Lazy URL Loading Support
// Extension functions for lazy URL loading functionality.
// Stored property `onTracksNeedUpdateListeners` lives in TrackPlayerCore class body.

/**
 * Callback interface for tracks needing URL update
 */
fun interface OnTracksNeedUpdateListener {
    fun onTracksNeedUpdate(
        tracks: List<TrackItem>,
        lookahead: Int,
    )
}

/**
 * Update entire track objects and rebuild queue if needed.
 * Skips currently playing track to preserve gapless playback.
 */
fun TrackPlayerCore.updateTracks(tracks: List<TrackItem>) {
    handler.post {
        NitroPlayerLogger.log("TrackPlayerCore", "🔄 updateTracks: ${tracks.size} updates")

        // Get current track ID to avoid updating it (preserves gapless playback)
        val currentTrackId = getCurrentTrack()?.id

        // Filter out current track and validate
        val safeTracks =
            tracks.filter { track ->
                when {
                    track.id == currentTrackId -> {
                        NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Skipping update for currently playing track: ${track.id} (preserves gapless)")
                        false
                    }

                    track.url.isEmpty() -> {
                        NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Skipping track with empty URL: ${track.id}")
                        false
                    }

                    else -> {
                        true
                    }
                }
            }

        if (safeTracks.isEmpty()) {
            NitroPlayerLogger.log("TrackPlayerCore", "✅ No valid updates to apply")
            return@post
        }

        // Update in PlaylistManager
        val affectedPlaylists = playlistManager.updateTracks(safeTracks)

        // Rebuild queue if current playlist was affected
        if (currentPlaylistId != null && affectedPlaylists.containsKey(currentPlaylistId)) {
            NitroPlayerLogger.log("TrackPlayerCore", "🔄 Rebuilding queue - ${affectedPlaylists[currentPlaylistId]} tracks updated in current playlist")

            // This method preserves current item and gapless buffering
            rebuildQueueFromCurrentPosition()

            NitroPlayerLogger.log("TrackPlayerCore", "✅ Queue rebuilt, gapless playback preserved")
        }

        NitroPlayerLogger.log("TrackPlayerCore", "✅ Track updates complete - ${affectedPlaylists.size} playlists affected")
    }
}

/**
 * Get tracks by IDs from all playlists
 */
fun TrackPlayerCore.getTracksById(trackIds: List<String>): List<TrackItem> {
    if (android.os.Looper.myLooper() == handler.looper) {
        return playlistManager.getTracksById(trackIds)
    }

    val latch = CountDownLatch(1)
    var result: List<TrackItem>? = null

    handler.post {
        try {
            result = playlistManager.getTracksById(trackIds)
        } finally {
            latch.countDown()
        }
    }

    try {
        latch.await(5, TimeUnit.SECONDS)
    } catch (e: InterruptedException) {
        Thread.currentThread().interrupt()
    }

    return result ?: emptyList()
}

/**
 * Get tracks needing URLs from current playlist
 */
fun TrackPlayerCore.getTracksNeedingUrls(): List<TrackItem> {
    if (android.os.Looper.myLooper() == handler.looper) {
        return getTracksNeedingUrlsInternal()
    }

    val latch = CountDownLatch(1)
    var result: List<TrackItem>? = null

    handler.post {
        try {
            result = getTracksNeedingUrlsInternal()
        } finally {
            latch.countDown()
        }
    }

    try {
        latch.await(5, TimeUnit.SECONDS)
    } catch (e: InterruptedException) {
        Thread.currentThread().interrupt()
    }

    return result ?: emptyList()
}

private fun TrackPlayerCore.getTracksNeedingUrlsInternal(): List<TrackItem> {
    if (currentPlaylistId == null) return emptyList()

    val playlist = playlistManager.getPlaylist(currentPlaylistId!!)
    return playlist?.tracks?.filter { it.url.isEmpty() } ?: emptyList()
}

/**
 * Get next N tracks from current position
 */
fun TrackPlayerCore.getNextTracks(count: Int): List<TrackItem> {
    if (android.os.Looper.myLooper() == handler.looper) {
        return getNextTracksInternal(count)
    }

    val latch = CountDownLatch(1)
    var result: List<TrackItem>? = null

    handler.post {
        try {
            result = getNextTracksInternal(count)
        } finally {
            latch.countDown()
        }
    }

    try {
        latch.await(5, TimeUnit.SECONDS)
    } catch (e: InterruptedException) {
        Thread.currentThread().interrupt()
    }

    return result ?: emptyList()
}

private fun TrackPlayerCore.getNextTracksInternal(count: Int): List<TrackItem> {
    val actualQueue = getActualQueueInternal()
    if (actualQueue.isEmpty()) return emptyList()

    val currentIndex = actualQueue.indexOfFirst { it.id == getCurrentTrack()?.id }
    if (currentIndex == -1) return emptyList()

    val startIndex = currentIndex + 1
    val endIndex = minOf(startIndex + count, actualQueue.size)

    return if (startIndex < actualQueue.size) {
        actualQueue.subList(startIndex, endIndex)
    } else {
        emptyList()
    }
}

/**
 * Get current track index in playlist
 */
fun TrackPlayerCore.getCurrentTrackIndex(): Int {
    if (android.os.Looper.myLooper() == handler.looper) {
        return currentTrackIndex
    }

    val latch = CountDownLatch(1)
    var result = -1

    handler.post {
        try {
            result = currentTrackIndex
        } finally {
            latch.countDown()
        }
    }

    try {
        latch.await(5, TimeUnit.SECONDS)
    } catch (e: InterruptedException) {
        Thread.currentThread().interrupt()
    }

    return result
}

/**
 * Register listener for when tracks need URL updates
 */
fun TrackPlayerCore.addOnTracksNeedUpdateListener(listener: OnTracksNeedUpdateListener) {
    handler.post {
        onTracksNeedUpdateListeners.add(WeakReference(listener))
    }
}

/**
 * Remove listener
 */
fun TrackPlayerCore.removeOnTracksNeedUpdateListener(listener: OnTracksNeedUpdateListener) {
    handler.post {
        onTracksNeedUpdateListeners.removeAll { it.get() == listener || it.get() == null }
    }
}

/**
 * Notify listeners that tracks need updating.
 * Called internally when moving to next track and upcoming tracks have empty URLs.
 */
private fun TrackPlayerCore.notifyTracksNeedUpdate(
    tracks: List<TrackItem>,
    lookahead: Int,
) {
    val liveCallbacks =
        synchronized(onTracksNeedUpdateListeners) {
            onTracksNeedUpdateListeners.removeAll { it.get() == null }
            onTracksNeedUpdateListeners.mapNotNull { it.get() }
        }

    handler.post {
        for (callback in liveCallbacks) {
            try {
                callback.onTracksNeedUpdate(tracks, lookahead)
            } catch (e: Exception) {
                NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Error in onTracksNeedUpdate listener: ${e.message}")
            }
        }
    }
}

/**
 * Check if upcoming tracks need URLs and notify listeners.
 * Call this in onMediaItemTransition or after skipTo operations.
 */
internal fun TrackPlayerCore.checkUpcomingTracksForUrls(lookahead: Int = 5) {
    val nextTracks = getNextTracksInternal(lookahead)
    val tracksNeedingUrls = nextTracks.filter { it.url.isEmpty() }

    if (tracksNeedingUrls.isNotEmpty()) {
        NitroPlayerLogger.log("TrackPlayerCore", "⚠️ ${tracksNeedingUrls.size} upcoming tracks need URLs")
        notifyTracksNeedUpdate(tracksNeedingUrls, lookahead)
    }
}
