@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.media

import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger
import com.margelo.nitro.nitroplayer.core.loadPlaylist
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Creates the [MediaSession.Callback] used by both notification controllers and
 * Android Auto.  Extracted from the old MediaSessionManager so the service can
 * own session creation while keeping callback logic isolated.
 */
object MediaSessionCallbackFactory {

    fun create(
        service: NitroPlayerPlaybackService,
        playlistManager: PlaylistManager,
    ): MediaSession.Callback {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

        return object : MediaSession.Callback {
            override fun onConnect(
                session: MediaSession,
                controller: MediaSession.ControllerInfo,
            ): MediaSession.ConnectionResult =
                MediaSession.ConnectionResult
                    .AcceptedResultBuilder(session)
                    .setAvailableSessionCommands(
                        MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS,
                    ).setAvailablePlayerCommands(
                        MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS,
                    ).build()

            override fun onAddMediaItems(
                mediaSession: MediaSession,
                controller: MediaSession.ControllerInfo,
                mediaItems: MutableList<MediaItem>,
            ): ListenableFuture<MutableList<MediaItem>> {
                NitroPlayerLogger.log("MediaSessionCallback") { "onAddMediaItems called with ${mediaItems.size} items" }
                if (mediaItems.isEmpty()) return Futures.immediateFuture(mutableListOf())

                val updated = mutableListOf<MediaItem>()
                for (requested in mediaItems) {
                    val mediaId =
                        requested.requestMetadata.mediaUri?.toString()
                            ?: requested.mediaId
                    try {
                        if (mediaId.contains(':')) {
                            val colonIdx = mediaId.indexOf(':')
                            val playlistId = mediaId.substring(0, colonIdx)
                            val trackId = mediaId.substring(colonIdx + 1)
                            val playlist = playlistManager.getPlaylist(playlistId)
                            val track = playlist?.tracks?.find { it.id == trackId }
                            if (track != null) {
                                updated.add(createMediaItem(track, mediaId))
                            } else {
                                updated.add(requested)
                            }
                        } else {
                            updated.add(requested)
                        }
                    } catch (e: Exception) {
                        NitroPlayerLogger.log("MediaSessionCallback") { "Error processing mediaId: ${e.message}" }
                        updated.add(requested)
                    }
                }
                return Futures.immediateFuture(updated)
            }

            override fun onSetMediaItems(
                mediaSession: MediaSession,
                controller: MediaSession.ControllerInfo,
                mediaItems: MutableList<MediaItem>,
                startIndex: Int,
                startPositionMs: Long,
            ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
                NitroPlayerLogger.log("MediaSessionCallback") { "onSetMediaItems called with ${mediaItems.size} items, startIndex: $startIndex" }
                if (mediaItems.isEmpty()) {
                    return Futures.immediateFuture(
                        MediaSession.MediaItemsWithStartPosition(mutableListOf(), 0, 0),
                    )
                }
                try {
                    val firstMediaId = mediaItems[0].mediaId
                    if (firstMediaId.contains(':')) {
                        val colonIdx = firstMediaId.indexOf(':')
                        val playlistId = firstMediaId.substring(0, colonIdx)
                        val trackId = firstMediaId.substring(colonIdx + 1)
                        val playlist = playlistManager.getPlaylist(playlistId)
                        if (playlist != null) {
                            val trackIndex = playlist.tracks.indexOfFirst { it.id == trackId }
                            if (trackIndex >= 0) {
                                service.trackPlayerCore?.let { core ->
                                    scope.launch { core.loadPlaylist(playlistId) }
                                }
                                val playlistMediaItems =
                                    playlist.tracks
                                        .map { track -> createMediaItem(track, "$playlistId:${track.id}") }
                                        .toMutableList()
                                return Futures.immediateFuture(
                                    MediaSession.MediaItemsWithStartPosition(
                                        playlistMediaItems,
                                        trackIndex,
                                        startPositionMs,
                                    ),
                                )
                            }
                        }
                    }
                } catch (e: Exception) {
                    NitroPlayerLogger.log("MediaSessionCallback") { "Error in onSetMediaItems: ${e.message}" }
                }
                return Futures.immediateFuture(
                    MediaSession.MediaItemsWithStartPosition(mediaItems, startIndex, startPositionMs),
                )
            }

            override fun onCustomCommand(
                session: MediaSession,
                controller: MediaSession.ControllerInfo,
                customCommand: SessionCommand,
                args: android.os.Bundle,
            ): ListenableFuture<SessionResult> =
                Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
        }
    }

    private fun createMediaItem(
        track: TrackItem,
        mediaId: String,
    ): MediaItem {
        val metadataBuilder =
            MediaMetadata
                .Builder()
                .setTitle(track.title)
                .setArtist(track.artist)
                .setAlbumTitle(track.album)

        track.artwork?.asSecondOrNull()?.let { artworkUrl ->
            try {
                metadataBuilder.setArtworkUri(Uri.parse(artworkUrl))
            } catch (_: Exception) {}
        }

        return MediaItem
            .Builder()
            .setMediaId(mediaId)
            .setUri(track.url)
            .setMediaMetadata(metadataBuilder.build())
            .build()
    }
}
