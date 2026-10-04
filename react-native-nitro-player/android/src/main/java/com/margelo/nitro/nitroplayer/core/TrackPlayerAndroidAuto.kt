@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import com.margelo.nitro.nitroplayer.connection.AndroidAutoConnectionDetector
import com.margelo.nitro.nitroplayer.media.MediaItem
import com.margelo.nitro.nitroplayer.media.MediaLibraryParser
import com.margelo.nitro.nitroplayer.media.MediaType
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService

/**
 * Android Auto integration — detector setup runs on the main thread (receiver
 * registration), playback commands are suspend and run on the player thread.
 */

/** Called on the main thread from TrackPlayerCore.init via handler.post. */
internal fun TrackPlayerCore.setupAndroidAutoDetector() {
    // The car may have bound the browser before this core existed (cold start from the car)
    if (NitroPlayerMediaBrowserService.isAndroidAutoConnected) setAndroidAutoConnected(true)
    androidAutoConnectionDetector =
        AndroidAutoConnectionDetector(context).apply {
            onConnectionChanged = { connected, _ ->
                handler.post { setAndroidAutoConnected(connected) }
            }
            registerCarConnectionReceiver()
        }
}

/** Android Auto binding the browser is proof of a connection, whatever the provider query said. */
internal fun TrackPlayerCore.onAndroidAutoBrowserConnected() {
    handler.post { setAndroidAutoConnected(true) }
}

private fun TrackPlayerCore.setAndroidAutoConnected(connected: Boolean) {
    NitroPlayerMediaBrowserService.isAndroidAutoConnected = connected
    if (isAndroidAutoConnectedField == connected) return
    isAndroidAutoConnectedField = connected
    updateJsKeepAlive()
    notifyAndroidAutoConnection(connected)
}

/** Routes a controller's "playlistId:trackId" pick through the logical queue (window + lazy URLs); false for unknown ids. */
internal fun TrackPlayerCore.playFromMediaId(mediaId: String): Boolean {
    val colonIndex = mediaId.indexOf(':')
    if (colonIndex <= 0) return false
    val playlistId = mediaId.substring(0, colonIndex)
    val trackRef = mediaId.substring(colonIndex + 1)
    if (playlistManager.indexOfTrackRef(playlistId, trackRef) < 0) return false
    startJsRuntimeIfNeeded()
    enqueue {
        val index = playlistManager.indexOfTrackRef(playlistId, trackRef)
        // Resuming what is already loaded keeps its position; a failed item is reloaded instead
        if (currentPlaylistId == playlistId && currentTrackIndex == index && exo.player.playerError == null) {
            // Tapping a song still waiting for its URL asks the app for it again
            if (getCurrentTrack()?.url.isNullOrEmpty()) checkUpcomingTracksForUrls(lookaheadCount, force = true)
            return@enqueue
        }
        if (index >= 0 && playlistManager.loadPlaylist(playlistId, index)) loadPlaylistOnQueue(playlistId, index)
    }
    return true
}

private fun folderIds(items: List<MediaItem>?): List<String> = items.orEmpty().filter { it.mediaType == MediaType.FOLDER }.flatMap { listOf(it.id) + folderIds(it.children) }

suspend fun TrackPlayerCore.setAndroidAutoMediaLibrary(libraryJson: String) =
    withPlayerContext {
        val library = MediaLibraryParser.fromJson(libraryJson)
        val previous = folderIds(mediaLibraryManager.getMediaLibrary()?.rootItems)
        mediaLibraryManager.setMediaLibrary(library)
        NitroPlayerMediaBrowserService.getInstance()?.onLibraryUpdated(previous + folderIds(library.rootItems) + mediaLibraryManager.loadedFolderIds)
    }

suspend fun TrackPlayerCore.clearAndroidAutoMediaLibrary() =
    withPlayerContext {
        val previous = folderIds(mediaLibraryManager.getMediaLibrary()?.rootItems)
        mediaLibraryManager.clear()
        NitroPlayerMediaBrowserService.getInstance()?.onLibraryUpdated(previous + mediaLibraryManager.loadedFolderIds)
    }
