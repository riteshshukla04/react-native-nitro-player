package com.margelo.nitro.nitroplayer.media

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
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
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.core.loadPlaylist
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MediaSessionManager(
    private val context: Context,
    private val player: ExoPlayer,
    private val playlistManager: PlaylistManager,
) {
    private var trackPlayerCore: TrackPlayerCore? = null

    fun setTrackPlayerCore(core: TrackPlayerCore) {
        trackPlayerCore = core
    }

    var mediaSession: MediaSession? = null // Make public so MediaBrowserService can access it
        private set
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    @Volatile private var currentTrack: TrackItem? = null

    @Volatile private var isPlaying: Boolean = false

    private var androidAutoEnabled: Boolean = false
    private var carPlayEnabled: Boolean = false
    private var showInNotification: Boolean = true

    companion object {
        private const val CHANNEL_ID = "nitro_player_channel"
        private const val CHANNEL_NAME = "Music Player"
    }

    init {
        setupMediaSession()
        createNotificationChannel()
    }

    fun configure(
        androidAutoEnabled: Boolean?,
        carPlayEnabled: Boolean?,
        showInNotification: Boolean?,
    ) {
        androidAutoEnabled?.let { this.androidAutoEnabled = it }
        carPlayEnabled?.let { this.carPlayEnabled = it }
        showInNotification?.let {
            this.showInNotification = it
            if (!it) {
                stopPlaybackService()
            }
        }
    }

    private fun setupMediaSession() {
        try {
            mediaSession =
                MediaSession
                    .Builder(context, player)
                    .setCallback(
                        object : MediaSession.Callback {
                            override fun onConnect(
                                session: MediaSession,
                                controller: MediaSession.ControllerInfo,
                            ): MediaSession.ConnectionResult {
                                // Accept all connections with default commands
                                // Media3 automatically handles play, pause, skip, etc. through the player
                                return MediaSession.ConnectionResult
                                    .AcceptedResultBuilder(session)
                                    .setAvailableSessionCommands(
                                        MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS,
                                    ).setAvailablePlayerCommands(
                                        MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS,
                                    ).build()
                            }

                            override fun onAddMediaItems(
                                mediaSession: MediaSession,
                                controller: MediaSession.ControllerInfo,
                                mediaItems: MutableList<MediaItem>,
                            ): ListenableFuture<MutableList<MediaItem>> {
                                // This is called when Android Auto requests to play a track
                                NitroPlayerLogger.log("MediaSessionManager") { "🎵 MediaSessionManager: onAddMediaItems called with ${mediaItems.size} items" }

                                if (mediaItems.isEmpty()) {
                                    return Futures.immediateFuture(mutableListOf())
                                }

                                val updatedMediaItems = mutableListOf<MediaItem>()

                                for (requestedMediaItem in mediaItems) {
                                    // Get the mediaId from requestMetadata or mediaId
                                    val mediaId =
                                        requestedMediaItem.requestMetadata.mediaUri?.toString()
                                            ?: requestedMediaItem.mediaId

                                    NitroPlayerLogger.log("MediaSessionManager") { "🎵 MediaSessionManager: Processing mediaId: $mediaId" }

                                    try {
                                        // Parse mediaId format: "playlistId:trackId"
                                        if (mediaId.contains(':')) {
                                            val colonIndex = mediaId.indexOf(':')
                                            val playlistId = mediaId.substring(0, colonIndex)
                                            val trackId = mediaId.substring(colonIndex + 1)

                                            NitroPlayerLogger.log("MediaSessionManager") { "🎵 MediaSessionManager: Parsed playlistId: $playlistId, trackId: $trackId" }

                                            // Get the playlist and track
                                            val playlist = playlistManager.getPlaylist(playlistId)
                                            if (playlist != null) {
                                                val track = playlist.tracks.find { it.id == trackId }
                                                if (track != null) {
                                                    // Create a proper MediaItem with all metadata
                                                    val resolvedMediaItem = createMediaItem(track, mediaId)
                                                    updatedMediaItems.add(resolvedMediaItem)
                                                    NitroPlayerLogger.log("MediaSessionManager") { "✅ MediaSessionManager: Resolved track: ${track.title}" }
                                                } else {
                                                    NitroPlayerLogger.log("MediaSessionManager") { "⚠️ MediaSessionManager: Track $trackId not found in playlist" }
                                                    updatedMediaItems.add(requestedMediaItem)
                                                }
                                            } else {
                                                NitroPlayerLogger.log("MediaSessionManager") { "⚠️ MediaSessionManager: Playlist $playlistId not found" }
                                                updatedMediaItems.add(requestedMediaItem)
                                            }
                                        } else {
                                            NitroPlayerLogger.log("MediaSessionManager") { "⚠️ MediaSessionManager: Invalid mediaId format: $mediaId" }
                                            updatedMediaItems.add(requestedMediaItem)
                                        }
                                    } catch (e: Exception) {
                                        NitroPlayerLogger.log("MediaSessionManager") { "❌ MediaSessionManager: Error processing mediaId - ${e.message}" }
                                        e.printStackTrace()
                                        updatedMediaItems.add(requestedMediaItem)
                                    }
                                }

                                NitroPlayerLogger.log("MediaSessionManager") { "🎵 MediaSessionManager: Returning ${updatedMediaItems.size} resolved media items" }
                                return Futures.immediateFuture(updatedMediaItems)
                            }

                            override fun onSetMediaItems(
                                mediaSession: MediaSession,
                                controller: MediaSession.ControllerInfo,
                                mediaItems: MutableList<MediaItem>,
                                startIndex: Int,
                                startPositionMs: Long,
                            ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
                                // This is called when Android Auto wants to set and play media items
                                NitroPlayerLogger.log("MediaSessionManager") { "🎵 MediaSessionManager: onSetMediaItems called with ${mediaItems.size} items, startIndex: $startIndex" }

                                if (mediaItems.isEmpty()) {
                                    return Futures.immediateFuture(
                                        MediaSession.MediaItemsWithStartPosition(
                                            mutableListOf(),
                                            0,
                                            0,
                                        ),
                                    )
                                }

                                try {
                                    // Get the first item's mediaId to determine the playlist
                                    val firstMediaId = mediaItems[0].mediaId
                                    NitroPlayerLogger.log("MediaSessionManager") { "🎵 MediaSessionManager: First mediaId: $firstMediaId" }

                                    // Parse mediaId format: "playlistId:trackId"
                                    if (firstMediaId.contains(':')) {
                                        val colonIndex = firstMediaId.indexOf(':')
                                        val playlistId = firstMediaId.substring(0, colonIndex)
                                        val trackId = firstMediaId.substring(colonIndex + 1)

                                        NitroPlayerLogger.log("MediaSessionManager") { "🎵 MediaSessionManager: Loading full playlist: $playlistId, starting at track: $trackId" }

                                        // Get the full playlist
                                        val playlist = playlistManager.getPlaylist(playlistId)
                                        if (playlist != null) {
                                            // Find the track index in the full playlist
                                            val trackIndex = playlist.tracks.indexOfFirst { it.id == trackId }

                                            if (trackIndex >= 0) {
                                                // Load the entire playlist into TrackPlayerCore
                                                trackPlayerCore?.let { core -> scope.launch { core.loadPlaylist(playlistId) } }

                                                // Create MediaItems for the entire playlist
                                                val playlistMediaItems =
                                                    playlist.tracks
                                                        .map { track ->
                                                            val trackMediaId = "$playlistId:${track.id}"
                                                            createMediaItem(track, trackMediaId)
                                                        }.toMutableList()

                                                NitroPlayerLogger.log("MediaSessionManager") { "✅ MediaSessionManager: Loaded ${playlistMediaItems.size} tracks, starting at index $trackIndex" }

                                                // Return the full playlist with the correct start index
                                                return Futures.immediateFuture(
                                                    MediaSession.MediaItemsWithStartPosition(
                                                        playlistMediaItems,
                                                        trackIndex,
                                                        startPositionMs,
                                                    ),
                                                )
                                            } else {
                                                NitroPlayerLogger.log("MediaSessionManager", "⚠️ MediaSessionManager: Track not found in playlist")
                                            }
                                        } else {
                                            NitroPlayerLogger.log("MediaSessionManager", "⚠️ MediaSessionManager: Playlist not found")
                                        }
                                    }
                                } catch (e: Exception) {
                                    NitroPlayerLogger.log("MediaSessionManager") { "❌ MediaSessionManager: Error in onSetMediaItems - ${e.message}" }
                                    e.printStackTrace()
                                }

                                // Fallback: use the provided media items
                                NitroPlayerLogger.log("MediaSessionManager", "🎵 MediaSessionManager: Using fallback - provided media items")
                                return Futures.immediateFuture(
                                    MediaSession.MediaItemsWithStartPosition(
                                        mediaItems,
                                        startIndex,
                                        startPositionMs,
                                    ),
                                )
                            }

                            override fun onCustomCommand(
                                session: MediaSession,
                                controller: MediaSession.ControllerInfo,
                                customCommand: SessionCommand,
                                args: android.os.Bundle,
                            ): ListenableFuture<SessionResult> {
                                // Handle custom commands if needed
                                return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                            }
                        },
                    ).build()

            // Wire the session into the PlaybackService so it can be promoted to foreground
            NitroPlayerPlaybackService.mediaSession = mediaSession
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel =
                NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Media playback controls"
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
            manager.createNotificationChannel(channel)
        }
    }

    private fun startPlaybackService() {
        try {
            val intent = Intent(context, NitroPlayerPlaybackService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (e: Exception) {
            NitroPlayerLogger.log("MediaSessionManager") { "Failed to start PlaybackService: ${e.message}" }
        }
    }

    private fun stopPlaybackService() {
        try {
            val intent = Intent(context, NitroPlayerPlaybackService::class.java)
            context.stopService(intent)
        } catch (e: Exception) {
            NitroPlayerLogger.log("MediaSessionManager") { "Failed to stop PlaybackService: ${e.message}" }
        }
    }

    fun onTrackChanged(track: TrackItem?) {
        currentTrack = track
    }

    fun onPlaybackStateChanged(playing: Boolean) {
        isPlaying = playing
        if (playing && showInNotification) {
            startPlaybackService()
        } else if (!playing) {
            stopPlaybackService()
        }
    }

    fun release() {
        stopPlaybackService()
        NitroPlayerPlaybackService.mediaSession = null
        mediaSession?.release()
        mediaSession = null
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
            } catch (e: Exception) {
                NitroPlayerLogger.log("MediaSessionManager") { "⚠️ MediaSessionManager: Invalid artwork URI: $artworkUrl" }
            }
        }

        return MediaItem
            .Builder()
            .setMediaId(mediaId)
            .setUri(track.url)
            .setMediaMetadata(metadataBuilder.build())
            .build()
    }
}
