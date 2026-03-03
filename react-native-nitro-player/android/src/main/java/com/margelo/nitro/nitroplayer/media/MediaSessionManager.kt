package com.margelo.nitro.nitroplayer.media

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Log
import android.util.LruCache
import androidx.core.app.NotificationCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URL

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
    private var notificationManager: NotificationManager? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val artworkCache = object : LruCache<String, Bitmap>(20) {
        override fun sizeOf(key: String, value: Bitmap): Int = 1
    }

    private var androidAutoEnabled: Boolean = false
    private var carPlayEnabled: Boolean = false
    private var showInNotification: Boolean = true

    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "nitro_player_channel"
        private const val CHANNEL_NAME = "Music Player"
        const val ACTION_PLAY = "com.margelo.nitro.nitroplayer.PLAY"
        const val ACTION_PAUSE = "com.margelo.nitro.nitroplayer.PAUSE"
        const val ACTION_NEXT = "com.margelo.nitro.nitroplayer.NEXT"
        const val ACTION_PREVIOUS = "com.margelo.nitro.nitroplayer.PREVIOUS"
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
            if (it) {
                updateNotification()
            } else {
                hideNotification()
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
                                                trackPlayerCore?.loadPlaylist(playlistId)

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
            // MediaSession is active by default in Media3
            updateMediaSessionMetadata()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun updateMediaSessionMetadata() {
        // MediaSession will automatically use the metadata from player's current MediaItem
        // No need to manually update here as TrackPlayerCore already sets metadata
    }

    private suspend fun loadArtworkBitmap(artworkUrl: String?): Bitmap? {
        if (artworkUrl.isNullOrEmpty()) return null

        // Check cache first
        artworkCache.get(artworkUrl)?.let { return it }

        return try {
            val bitmap =
                withContext(Dispatchers.IO) {
                    val url = URL(artworkUrl)
                    BitmapFactory.decodeStream(url.openConnection().getInputStream())
                }
            // Cache the bitmap
            if (bitmap != null) {
                artworkCache.put(artworkUrl, bitmap)
            }
            bitmap
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun createNotificationChannel() {
        notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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

            notificationManager?.createNotificationChannel(channel)
        }
    }

    private fun getCurrentTrack(): TrackItem? {
        val currentMediaItem = player.currentMediaItem ?: return null
        val mediaId = currentMediaItem.mediaId

        // Parse mediaId format: "playlistId:trackId" or just "trackId"
        val trackId =
            if (mediaId.contains(':')) {
                mediaId.substring(mediaId.indexOf(':') + 1)
            } else {
                mediaId
            }

        // Find track in current playlist or all playlists
        return trackPlayerCore?.getCurrentPlaylistId()?.let { playlistId ->
            playlistManager.getPlaylist(playlistId)?.tracks?.find { it.id == trackId }
        } ?: run {
            for (playlist in playlistManager.getAllPlaylists()) {
                playlist.tracks.find { it.id == trackId }?.let { return it }
            }
            null
        }
    }

    private fun updateNotification() {
        if (!showInNotification) return

        val currentTrack = getCurrentTrack()
        val notification = buildNotification(currentTrack)
        notificationManager?.notify(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(track: TrackItem?): Notification {
        val mediaSession = this.mediaSession ?: return createEmptyNotification()

        // Launch intent
        val contentIntent =
            PendingIntent.getActivity(
                context,
                0,
                context.packageManager.getLaunchIntentForPackage(context.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        val builder =
            NotificationCompat
                .Builder(context, CHANNEL_ID)
                .setContentTitle(track?.title ?: "Unknown Title")
                .setContentText(track?.artist ?: "Unknown Artist")
                .setSubText(track?.album ?: "")
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentIntent(contentIntent)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(player.isPlaying)
                .setShowWhen(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
        try {
            val compatToken =
                android.support.v4.media.session.MediaSessionCompat.Token
                    .fromToken(mediaSession.platformToken)
            builder.setStyle(
                androidx.media.app.NotificationCompat
                    .MediaStyle()
                    .setMediaSession(compatToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )
        } catch (e: Exception) {
            NitroPlayerLogger.log("MediaSessionManager") { "Failed to set media session token: ${e.message}" }
        }

        // Add action buttons
        builder.addAction(
            android.R.drawable.ic_media_previous,
            "Previous",
            createMediaAction(ACTION_PREVIOUS),
        )

        if (player.isPlaying) {
            builder.addAction(
                android.R.drawable.ic_media_pause,
                "Pause",
                createMediaAction(ACTION_PAUSE),
            )
        } else {
            builder.addAction(
                android.R.drawable.ic_media_play,
                "Play",
                createMediaAction(ACTION_PLAY),
            )
        }

        builder.addAction(
            android.R.drawable.ic_media_next,
            "Next",
            createMediaAction(ACTION_NEXT),
        )

        // Load artwork asynchronously and update notification
        track?.artwork?.asSecondOrNull()?.let { artworkUrl ->
            scope.launch {
                val bitmap = loadArtworkBitmap(artworkUrl)
                if (bitmap != null) {
                    builder.setLargeIcon(bitmap)
                    notificationManager?.notify(NOTIFICATION_ID, builder.build())
                }
            }
        }

        return builder.build()
    }

    private fun createEmptyNotification(): Notification =
        NotificationCompat
            .Builder(context, CHANNEL_ID)
            .setContentTitle("Music Player")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .build()

    private fun createMediaAction(action: String): PendingIntent {
        val intent =
            Intent(action).apply {
                setPackage(context.packageName)
            }
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun hideNotification() {
        notificationManager?.cancel(NOTIFICATION_ID)
    }

    fun onTrackChanged() {
        // Preload artwork for better notification display
        val currentTrack = getCurrentTrack()
        if (currentTrack != null) {
            scope.launch {
                currentTrack.artwork?.asSecondOrNull()?.let { artworkUrl ->
                    loadArtworkBitmap(artworkUrl)
                }
                updateNotification()
            }
        } else {
            updateNotification()
        }
    }

    fun onPlaybackStateChanged() {
        updateNotification()
    }

    fun release() {
        hideNotification()
        mediaSession?.release()
        mediaSession = null
        artworkCache.evictAll()
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
