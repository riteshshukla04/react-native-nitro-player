@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.media

import android.net.Uri
import android.provider.MediaStore
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
import com.margelo.nitro.nitroplayer.playlist.Playlist
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

                // Voice search ("Add X to the queue") lands here too.
                val voiceMatch = resolveVoiceSearch(mediaItems, playlistManager)
                if (voiceMatch != null) {
                    return Futures.immediateFuture(voiceMatch.items.toMutableList())
                }

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

                // Voice search ("Hey Google, play X on …") routes here with a
                // MediaItem whose requestMetadata.searchQuery is set. Resolve
                // it against loaded playlists before falling through.
                val voiceMatch = resolveVoiceSearch(mediaItems, playlistManager)
                if (voiceMatch != null) {
                    val (playlistId, items, trackIndex) = voiceMatch
                    service.trackPlayerCore?.let { core ->
                        scope.launch { core.loadPlaylist(playlistId, trackIndex) }
                    }
                    return Futures.immediateFuture(
                        MediaSession.MediaItemsWithStartPosition(items, trackIndex, startPositionMs),
                    )
                }

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
                                    scope.launch { core.loadPlaylist(playlistId, trackIndex) }
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

                // If a voice query was issued but found nothing, return an
                // explicit failure so the controller (Assistant) surfaces a
                // spoken error instead of silently no-oping. Without this the
                // Auto QA bot reports "no music played or error message shown".
                if (mediaItems.isNotEmpty() && mediaItems[0].requestMetadata.searchQuery != null) {
                    return Futures.immediateFailedFuture(
                        UnsupportedOperationException("No matching tracks for voice search"),
                    )
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

    private data class VoiceMatch(
        val playlistId: String,
        val items: List<MediaItem>,
        val startIndex: Int,
    )

    /**
     * Resolves a voice-search MediaItem into a concrete playlist + start index.
     *
     * Triggered when Google Assistant ("Hey Google, play X on …") sends a
     * MediaItem with `requestMetadata.searchQuery`. Honors the
     * `MediaStore.EXTRA_MEDIA_FOCUS` bundle so artist/album/genre/playlist/title
     * queries narrow the search appropriately. Empty queries fall back to the
     * current or first available playlist (Assistant: "Play music").
     */
    @Suppress("DEPRECATION") // MediaStore.Audio.Playlists constants — Assistant still sends them.
    private fun resolveVoiceSearch(
        mediaItems: List<MediaItem>,
        playlistManager: PlaylistManager,
    ): VoiceMatch? {
        val first = mediaItems.firstOrNull() ?: return null
        val request = first.requestMetadata
        val rawQuery = request.searchQuery ?: return null
        val query = rawQuery.trim()
        val extras = request.extras

        // Empty query → "play music"-style resume. Prefer current playlist,
        // otherwise the first non-empty playlist.
        if (query.isEmpty()) {
            val fallback =
                playlistManager.getCurrentPlaylist()
                    ?: playlistManager.getAllPlaylists().firstOrNull { it.tracks.isNotEmpty() }
                    ?: return null
            val items =
                fallback.tracks.map { createMediaItem(it, "${fallback.id}:${it.id}") }
            return VoiceMatch(fallback.id, items, 0)
        }

        val focus = extras?.getString(MediaStore.EXTRA_MEDIA_FOCUS)
        val artist = extras?.getString(MediaStore.EXTRA_MEDIA_ARTIST)
        val album = extras?.getString(MediaStore.EXTRA_MEDIA_ALBUM)
        val title = extras?.getString(MediaStore.EXTRA_MEDIA_TITLE)
        val playlistName = extras?.getString(MediaStore.EXTRA_MEDIA_PLAYLIST)
        val genre = extras?.getString(MediaStore.EXTRA_MEDIA_GENRE)

        val all = playlistManager.getAllPlaylists()
        if (all.isEmpty()) return null

        // Playlist-focused query: best match by playlist name.
        if (focus == MediaStore.Audio.Playlists.ENTRY_CONTENT_TYPE && !playlistName.isNullOrBlank()) {
            val matched = bestPlaylistByName(all, playlistName) ?: bestPlaylistByName(all, query)
            if (matched != null && matched.tracks.isNotEmpty()) {
                val items = matched.tracks.map { createMediaItem(it, "${matched.id}:${it.id}") }
                return VoiceMatch(matched.id, items, 0)
            }
        }

        // Score every track across every playlist; play the best track in the
        // context of its playlist so "next/previous" still work naturally.
        var bestPlaylist: Playlist? = null
        var bestIndex = -1
        var bestScore = 0

        for (playlist in all) {
            playlist.tracks.forEachIndexed { idx, track ->
                val score = scoreTrack(track, query, focus, title, artist, album, genre)
                if (score > bestScore) {
                    bestScore = score
                    bestPlaylist = playlist
                    bestIndex = idx
                }
            }
        }

        val match = bestPlaylist
        if (match == null || bestIndex < 0 || bestScore <= 0) return null

        val items = match.tracks.map { createMediaItem(it, "${match.id}:${it.id}") }
        return VoiceMatch(match.id, items, bestIndex)
    }

    private fun bestPlaylistByName(
        playlists: List<Playlist>,
        name: String,
    ): Playlist? {
        val q = name.lowercase().trim()
        if (q.isEmpty()) return null
        return playlists
            .map { it to it.name.lowercase() }
            .filter { (_, n) -> n.contains(q) || q.contains(n) }
            .minByOrNull { (_, n) -> kotlin.math.abs(n.length - q.length) }
            ?.first
    }

    private fun scoreTrack(
        track: TrackItem,
        query: String,
        focus: String?,
        title: String?,
        artist: String?,
        album: String?,
        genre: String?,
    ): Int {
        val q = query.lowercase()
        val titleL = track.title.lowercase()
        val artistL = track.artist.lowercase()
        val albumL = track.album.lowercase()

        var score = 0

        when (focus) {
            MediaStore.Audio.Artists.ENTRY_CONTENT_TYPE -> {
                if (!artist.isNullOrBlank() && artistL.contains(artist.lowercase())) score += 80
                if (artistL.contains(q)) score += 40
            }
            MediaStore.Audio.Albums.ENTRY_CONTENT_TYPE -> {
                if (!album.isNullOrBlank() && albumL.contains(album.lowercase())) score += 80
                if (albumL.contains(q)) score += 40
            }
            MediaStore.Audio.Genres.ENTRY_CONTENT_TYPE -> {
                if (!genre.isNullOrBlank()) {
                    val g = genre.lowercase()
                    if (titleL.contains(g) || albumL.contains(g) || artistL.contains(g)) score += 40
                }
            }
            else -> {
                if (!title.isNullOrBlank() && titleL.contains(title.lowercase())) score += 80
                if (!artist.isNullOrBlank() && artistL.contains(artist.lowercase())) score += 50
                if (!album.isNullOrBlank() && albumL.contains(album.lowercase())) score += 30
            }
        }

        // Token-overlap fallback against the whole free-text query.
        val tokens = q.split(' ', ',', '-').filter { it.length >= 2 }
        for (t in tokens) {
            if (titleL.contains(t)) score += 10
            if (artistL.contains(t)) score += 6
            if (albumL.contains(t)) score += 3
        }
        if (titleL == q || artistL == q || albumL == q) score += 100
        return score
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
