@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import com.margelo.nitro.nitroplayer.connection.AndroidAutoConnectionDetector
import com.margelo.nitro.nitroplayer.media.MediaLibraryParser
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService

/**
 * Android Auto integration — detector setup runs on the main thread (receiver
 * registration), playback commands are suspend and run on the player thread.
 */

/** Called on the main thread from TrackPlayerCore.init via handler.post. */
internal fun TrackPlayerCore.setupAndroidAutoDetector() {
    androidAutoConnectionDetector =
        AndroidAutoConnectionDetector(context).apply {
            onConnectionChanged = { connected, _ ->
                handler.post {
                    isAndroidAutoConnectedField = connected
                    NitroPlayerMediaBrowserService.isAndroidAutoConnected = connected
                    notifyAndroidAutoConnection(connected)
                }
            }
            registerCarConnectionReceiver()
        }
}

/** Called by MediaBrowserService when the user picks a track in Android Auto. */
suspend fun TrackPlayerCore.playFromPlaylistTrack(mediaId: String) =
    withPlayerContext {
        try {
            val colonIndex = mediaId.indexOf(':')
            if (colonIndex <= 0 || colonIndex >= mediaId.length - 1) return@withPlayerContext
            val playlistId = mediaId.substring(0, colonIndex)
            val trackId = mediaId.substring(colonIndex + 1)
            val playlist = playlistManager.getPlaylist(playlistId) ?: return@withPlayerContext
            val trackIndex = playlist.tracks.indexOfFirst { it.id == trackId }
            if (trackIndex < 0) return@withPlayerContext
            if (currentPlaylistId != playlistId) {
                loadPlaylistInternal(playlistId)
            }
            playFromIndexInternal(trackIndex)
        } catch (_: Exception) {
        }
    }

private fun TrackPlayerCore.loadPlaylistInternal(playlistId: String) {
    playNextStack.clear()
    upNextQueue.clear()
    currentTemporaryType = TrackPlayerCore.TemporaryType.NONE
    val playlist = playlistManager.getPlaylist(playlistId) ?: return
    currentPlaylistId = playlistId
    updatePlayerQueue(playlist.tracks)
}

suspend fun TrackPlayerCore.setAndroidAutoMediaLibrary(libraryJson: String) =
    withPlayerContext {
        val library = MediaLibraryParser.fromJson(libraryJson)
        mediaLibraryManager.setMediaLibrary(library)
        NitroPlayerMediaBrowserService.getInstance()?.onPlaylistsUpdated()
    }

suspend fun TrackPlayerCore.clearAndroidAutoMediaLibrary() =
    withPlayerContext {
        mediaLibraryManager.clear()
        NitroPlayerMediaBrowserService.getInstance()?.onPlaylistsUpdated()
    }
