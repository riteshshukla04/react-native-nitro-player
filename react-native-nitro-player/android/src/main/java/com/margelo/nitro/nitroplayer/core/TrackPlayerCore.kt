@file:Suppress("ktlint:standard:max-line-length", "ktlint:standard:if-else-wrapping")

package com.margelo.nitro.nitroplayer.core

import android.content.Context
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import com.margelo.nitro.core.NullType
import com.margelo.nitro.nitroplayer.NitroPlayerPackage
import com.margelo.nitro.nitroplayer.PlayerState
import com.margelo.nitro.nitroplayer.Reason
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.TrackPlayerState
import com.margelo.nitro.nitroplayer.Variant_NullType_String
import com.margelo.nitro.nitroplayer.Variant_NullType_TrackItem
import com.margelo.nitro.nitroplayer.connection.AndroidAutoConnectionDetector
import com.margelo.nitro.nitroplayer.media.MediaSessionManager
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class TrackPlayerCore private constructor(
    private val context: Context,
) {
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private lateinit var player: ExoPlayer
    private val playlistManager = PlaylistManager.getInstance(context)
    private var mediaSessionManager: MediaSessionManager? = null
    private var currentPlaylistId: String? = null
    private var isManuallySeeked = false
    private var isAndroidAutoConnected: Boolean = false
    private var androidAutoConnectionDetector: AndroidAutoConnectionDetector? = null
    var onAndroidAutoConnectionChange: ((Boolean) -> Unit)? = null
    private val progressUpdateRunnable =
        object : Runnable {
            override fun run() {
                if (::player.isInitialized && player.playbackState != Player.STATE_IDLE) {
                    val position = player.currentPosition / 1000.0
                    val duration = if (player.duration > 0) player.duration / 1000.0 else 0.0
                    onPlaybackProgressChange?.invoke(position, duration, if (isManuallySeeked) true else null)
                    isManuallySeeked = false
                }
                handler.postDelayed(this, 250) // Update every 250ms
            }
        }

    var onChangeTrack: ((TrackItem, Reason?) -> Unit)? = null
    var onPlaybackStateChange: ((TrackPlayerState, Reason?) -> Unit)? = null
    var onSeek: ((Double, Double) -> Unit)? = null
    var onPlaybackProgressChange: ((Double, Double, Boolean?) -> Unit)? = null

    companion object {
        @Volatile
        @Suppress("ktlint:standard:property-naming")
        private var INSTANCE: TrackPlayerCore? = null

        fun getInstance(context: Context): TrackPlayerCore =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: TrackPlayerCore(context).also { INSTANCE = it }
            }
    }

    init {
        handler.post {
            // Configure LoadControl for gapless playback
            // This enables pre-buffering of the next track for seamless transitions
            val loadControl =
                DefaultLoadControl
                    .Builder()
                    .setBufferDurationsMs(
                        DefaultLoadControl.DEFAULT_MIN_BUFFER_MS, // Minimum buffer: 1.5s
                        DefaultLoadControl.DEFAULT_MAX_BUFFER_MS, // Maximum buffer: 5s
                        DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS, // Buffer for playback: 2.5s
                        DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS, // Buffer after rebuffer: 5s
                    ).setBackBuffer(DefaultLoadControl.DEFAULT_BACK_BUFFER_DURATION_MS, true) // Keep back buffer for seamless transitions
                    .setPrioritizeTimeOverSizeThresholds(true) // Prioritize time-based buffering
                    .build()

            player =
                ExoPlayer
                    .Builder(context)
                    .setLoadControl(loadControl)
                    .build()
            mediaSessionManager =
                MediaSessionManager(context, player, playlistManager).apply {
                    setTrackPlayerCore(this@TrackPlayerCore)
                }

            // Set references for MediaBrowserService
            NitroPlayerMediaBrowserService.trackPlayerCore = this
            NitroPlayerMediaBrowserService.mediaSessionManager = mediaSessionManager

            // Initialize Android Auto connection detector
            androidAutoConnectionDetector =
                AndroidAutoConnectionDetector(context).apply {
                    onConnectionChanged = { connected, connectionType ->
                        handler.post {
                            isAndroidAutoConnected = connected
                            NitroPlayerMediaBrowserService.isAndroidAutoConnected = connected

                            // Notify JavaScript
                            onAndroidAutoConnectionChange?.invoke(connected)

                            println("🚗 Android Auto connection changed: connected=$connected, type=$connectionType")
                        }
                    }
                    registerCarConnectionReceiver()
                }

            player.addListener(
                object : Player.Listener {
                    override fun onMediaItemTransition(
                        mediaItem: MediaItem?,
                        reason: Int,
                    ) {
                        // Handle playlist switching if needed
                        mediaItem?.mediaId?.let { mediaId ->
                            if (mediaId.contains(':')) {
                                val colonIndex = mediaId.indexOf(':')
                                val playlistId = mediaId.substring(0, colonIndex)
                                if (playlistId != currentPlaylistId) {
                                    // Track from different playlist - ensure playlist is loaded
                                    val playlist = playlistManager.getPlaylist(playlistId)
                                    if (playlist != null && currentPlaylistId != playlistId) {
                                        // This shouldn't happen if playlists are loaded correctly,
                                        // but handle it as a safety measure
                                        println(
                                            "⚠️ TrackPlayerCore: Detected track from different playlist, updating...",
                                        )
                                    }
                                }
                            }
                        }

                        val track = findTrack(mediaItem)
                        if (track != null) {
                            val r =
                                when (reason) {
                                    Player.MEDIA_ITEM_TRANSITION_REASON_AUTO -> Reason.END
                                    Player.MEDIA_ITEM_TRANSITION_REASON_SEEK -> Reason.USER_ACTION
                                    Player.MEDIA_ITEM_TRANSITION_REASON_PLAYLIST_CHANGED -> Reason.USER_ACTION
                                    else -> null
                                }
                            onChangeTrack?.invoke(track, r)
                            mediaSessionManager?.onTrackChanged()
                        }
                    }

                    override fun onTimelineChanged(
                        timeline: androidx.media3.common.Timeline,
                        reason: Int,
                    ) {
                        if (reason == Player.TIMELINE_CHANGE_REASON_PLAYLIST_CHANGED) {
                            // Playlist changed - update MediaBrowserService
                            NitroPlayerMediaBrowserService.getInstance()?.onPlaylistsUpdated()
                        }
                    }

                    override fun onPlayWhenReadyChanged(
                        playWhenReady: Boolean,
                        reason: Int,
                    ) {
                        val r =
                            when (reason) {
                                Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST -> Reason.USER_ACTION
                                else -> null
                            }
                        emitStateChange(r)
                    }

                    override fun onPlaybackStateChanged(playbackState: Int) {
                        emitStateChange()
                    }

                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        emitStateChange()
                    }

                    override fun onPositionDiscontinuity(
                        oldPosition: Player.PositionInfo,
                        newPosition: Player.PositionInfo,
                        reason: Int,
                    ) {
                        if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                            isManuallySeeked = true
                            onSeek?.invoke(newPosition.positionMs / 1000.0, player.duration / 1000.0)
                        }
                    }
                },
            )

            // Start progress updates
            handler.post(progressUpdateRunnable)
        }
    }

    /**
     * Load a playlist for playback using ExoPlayer's native playlist API
     * Based on: https://developer.android.com/media/media3/exoplayer/playlists
     */
    fun loadPlaylist(playlistId: String) {
        handler.post {
            val playlist = playlistManager.getPlaylist(playlistId)
            if (playlist != null) {
                currentPlaylistId = playlistId
                updatePlayerQueue(playlist.tracks)
            }
        }
    }

    /**
     * Play a specific track from a playlist (for Android Auto)
     * MediaId format: "playlistId:trackId"
     */
    fun playFromPlaylistTrack(mediaId: String) {
        handler.post {
            try {
                // Parse mediaId: "playlistId:trackId"
                val colonIndex = mediaId.indexOf(':')
                if (colonIndex > 0 && colonIndex < mediaId.length - 1) {
                    val playlistId = mediaId.substring(0, colonIndex)
                    val trackId = mediaId.substring(colonIndex + 1)

                    val playlist = playlistManager.getPlaylist(playlistId)
                    if (playlist != null) {
                        val trackIndex = playlist.tracks.indexOfFirst { it.id == trackId }
                        if (trackIndex >= 0) {
                            // Load playlist if not already loaded
                            if (currentPlaylistId != playlistId) {
                                loadPlaylist(playlistId)
                                // Wait a bit for playlist to load, then seek
                                handler.postDelayed({
                                    playFromIndex(trackIndex)
                                }, 100)
                            } else {
                                // Playlist already loaded, just seek to track
                                playFromIndex(trackIndex)
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                println("❌ TrackPlayerCore: Error playing from playlist track - ${e.message}")
                e.printStackTrace()
            }
        }
    }

    /**
     * Update the player queue when playlist changes
     */
    fun updatePlaylist(playlistId: String) {
        handler.post {
            if (currentPlaylistId == playlistId) {
                val playlist = playlistManager.getPlaylist(playlistId)
                if (playlist != null) {
                    updatePlayerQueue(playlist.tracks)
                }
            }
        }
    }

    /**
     * Get current playlist ID
     */
    fun getCurrentPlaylistId(): String? = currentPlaylistId

    /**
     * Get playlist manager (for access from other classes like Google Cast)
     */
    fun getPlaylistManager(): PlaylistManager = playlistManager

    private fun emitStateChange(reason: Reason? = null) {
        val state =
            when (player.playbackState) {
                Player.STATE_IDLE -> TrackPlayerState.STOPPED
                Player.STATE_BUFFERING -> if (player.playWhenReady) TrackPlayerState.PLAYING else TrackPlayerState.PAUSED
                Player.STATE_READY -> if (player.isPlaying) TrackPlayerState.PLAYING else TrackPlayerState.PAUSED
                Player.STATE_ENDED -> TrackPlayerState.STOPPED
                else -> TrackPlayerState.STOPPED
            }

        val actualReason = reason ?: if (player.playbackState == Player.STATE_ENDED) Reason.END else null
        onPlaybackStateChange?.invoke(state, actualReason)
        mediaSessionManager?.onPlaybackStateChanged()
    }

    private fun updatePlayerQueue(tracks: List<TrackItem>) {
        // Create MediaItems with playlist info in mediaId for Android Auto
        val mediaItems =
            tracks.mapIndexed { index, track ->
                val playlistId = currentPlaylistId ?: ""
                // Format: "playlistId:trackId" so we can identify playlist and track
                val mediaId = if (playlistId.isNotEmpty()) "$playlistId:${track.id}" else track.id
                track.toMediaItem(mediaId)
            }

        player.setMediaItems(mediaItems, false)
        if (player.playbackState == Player.STATE_IDLE && mediaItems.isNotEmpty()) {
            player.prepare()
        }
    }

    private fun TrackItem.toMediaItem(customMediaId: String? = null): MediaItem {
        val metadataBuilder =
            MediaMetadata
                .Builder()
                .setTitle(title)
                .setArtist(artist)
                .setAlbumTitle(album)

        artwork?.asSecondOrNull()?.let { artworkUrl ->
            try {
                metadataBuilder.setArtworkUri(Uri.parse(artworkUrl))
            } catch (e: Exception) {
                // Ignore invalid artwork URI
            }
        }

        return MediaItem
            .Builder()
            .setMediaId(customMediaId ?: id)
            .setUri(url)
            .setMediaMetadata(metadataBuilder.build())
            .build()
    }

    private fun findTrack(mediaItem: MediaItem?): TrackItem? {
        if (mediaItem == null) return null

        val mediaId = mediaItem.mediaId
        val trackId =
            if (mediaId.contains(':')) {
                // Format: "playlistId:trackId"
                mediaId.substring(mediaId.indexOf(':') + 1)
            } else {
                mediaId
            }

        val playlist = currentPlaylistId?.let { playlistManager.getPlaylist(it) }
        return playlist?.tracks?.find { it.id == trackId }
    }

    fun play() {
        handler.post { player.play() }
    }

    fun pause() {
        handler.post { player.pause() }
    }

    fun playSong(
        songId: String,
        fromPlaylist: String?,
    ) {
        println("🎵 TrackPlayerCore: playSong() called - songId: $songId, fromPlaylist: $fromPlaylist")

        handler.post {
            var targetPlaylistId: String? = null
            var songIndex: Int = -1

            // Case 1: If fromPlaylist is provided, use that playlist
            if (fromPlaylist != null) {
                println("🎵 TrackPlayerCore: Looking for song in specified playlist: $fromPlaylist")
                val playlist = playlistManager.getPlaylist(fromPlaylist)
                if (playlist != null) {
                    songIndex = playlist.tracks.indexOfFirst { it.id == songId }
                    if (songIndex >= 0) {
                        targetPlaylistId = fromPlaylist
                        println("✅ Found song at index $songIndex in playlist $fromPlaylist")
                    } else {
                        println("⚠️ Song $songId not found in specified playlist $fromPlaylist")
                        return@post
                    }
                } else {
                    println("⚠️ Playlist $fromPlaylist not found")
                    return@post
                }
            }
            // Case 2: If fromPlaylist is not provided, search in current/loaded playlist first
            else {
                println("🎵 TrackPlayerCore: No playlist specified, checking current playlist")

                // Check if song exists in currently loaded playlist
                if (currentPlaylistId != null) {
                    val currentPlaylist = playlistManager.getPlaylist(currentPlaylistId!!)
                    if (currentPlaylist != null) {
                        songIndex = currentPlaylist.tracks.indexOfFirst { it.id == songId }
                        if (songIndex >= 0) {
                            targetPlaylistId = currentPlaylistId
                            println("✅ Found song at index $songIndex in current playlist $currentPlaylistId")
                        }
                    }
                }

                // If not found in current playlist, search in all playlists
                if (songIndex == -1) {
                    println("🔍 Song not found in current playlist, searching all playlists...")
                    val allPlaylists = playlistManager.getAllPlaylists()

                    for (playlist in allPlaylists) {
                        songIndex = playlist.tracks.indexOfFirst { it.id == songId }
                        if (songIndex >= 0) {
                            targetPlaylistId = playlist.id
                            println("✅ Found song at index $songIndex in playlist ${playlist.id}")
                            break
                        }
                    }

                    // If still not found, just use the first playlist if available
                    if (songIndex == -1 && allPlaylists.isNotEmpty()) {
                        targetPlaylistId = allPlaylists[0].id
                        songIndex = 0
                        println("⚠️ Song not found in any playlist, using first playlist and starting at index 0")
                    }
                }
            }

            // Now play the song
            if (targetPlaylistId == null || songIndex < 0) {
                println("❌ Could not determine playlist or song index")
                return@post
            }

            // Load playlist if it's different from current
            if (currentPlaylistId != targetPlaylistId) {
                println("🔄 Loading new playlist: $targetPlaylistId")
                val playlist = playlistManager.getPlaylist(targetPlaylistId)
                if (playlist != null) {
                    currentPlaylistId = targetPlaylistId
                    updatePlayerQueue(playlist.tracks)

                    // Wait a bit for playlist to load, then play from index
                    handler.postDelayed({
                        println("▶️ Playing from index: $songIndex")
                        playFromIndex(songIndex)
                    }, 100)
                }
            } else {
                // Playlist already loaded, just play from index
                println("▶️ Playing from index: $songIndex")
                playFromIndex(songIndex)
            }
        }
    }

    fun skipToNext() {
        handler.post {
            if (player.hasNextMediaItem()) {
                player.seekToNextMediaItem()
            }
        }
    }

    fun skipToPrevious() {
        handler.post {
            if (player.hasPreviousMediaItem()) {
                player.seekToPreviousMediaItem()
            }
        }
    }

    fun seek(position: Double) {
        handler.post {
            isManuallySeeked = true
            player.seekTo((position * 1000).toLong())
        }
    }

    fun getState(): PlayerState {
        // Check if we're already on the main thread
        if (android.os.Looper.myLooper() == handler.looper) {
            return getStateInternal()
        }

        // Use CountDownLatch to wait for the result on the main thread
        val latch = CountDownLatch(1)
        var result: PlayerState? = null

        handler.post {
            try {
                result = getStateInternal()
            } finally {
                latch.countDown()
            }
        }

        try {
            // Wait up to 5 seconds for the result
            latch.await(5, TimeUnit.SECONDS)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        }

        return result ?: getStateInternal()
    }

    private fun getStateInternal(): PlayerState =
        if (::player.isInitialized) {
            val currentMediaItem = player.currentMediaItem
            val track =
                if (currentMediaItem != null) {
                    findTrack(currentMediaItem)
                } else {
                    null
                }

            // Convert nullable TrackItem to Variant_NullType_TrackItem
            val currentTrack: Variant_NullType_TrackItem? =
                if (track != null) {
                    Variant_NullType_TrackItem.create(track)
                } else {
                    null
                }

            val currentPosition = player.currentPosition / 1000.0
            val totalDuration = if (player.duration > 0) player.duration / 1000.0 else 0.0

            val currentState =
                when (player.playbackState) {
                    Player.STATE_IDLE -> TrackPlayerState.STOPPED
                    Player.STATE_BUFFERING -> if (player.playWhenReady) TrackPlayerState.PLAYING else TrackPlayerState.PAUSED
                    Player.STATE_READY -> if (player.isPlaying) TrackPlayerState.PLAYING else TrackPlayerState.PAUSED
                    Player.STATE_ENDED -> TrackPlayerState.STOPPED
                    else -> TrackPlayerState.STOPPED
                }

            // Get current playlist
            val currentPlaylist = currentPlaylistId?.let { playlistManager.getPlaylist(it) }

            // Use ExoPlayer's currentMediaItemIndex
            val currentIndex =
                if (player.currentMediaItemIndex >= 0) {
                    player.currentMediaItemIndex.toDouble()
                } else {
                    -1.0
                }

            PlayerState(
                currentTrack = currentTrack,
                currentPosition = currentPosition,
                totalDuration = totalDuration,
                currentState = currentState,
                currentPlaylistId = currentPlaylistId?.let { Variant_NullType_String.create(it) },
                currentIndex = currentIndex,
            )
        } else {
            // Return default state if player is not initialized
            PlayerState(
                currentTrack = null,
                currentPosition = 0.0,
                totalDuration = 0.0,
                currentState = TrackPlayerState.STOPPED,
                currentPlaylistId = currentPlaylistId?.let { Variant_NullType_String.create(it) },
                currentIndex = -1.0,
            )
        }

    fun configure(
        androidAutoEnabled: Boolean?,
        carPlayEnabled: Boolean?,
        showInNotification: Boolean?,
    ) {
        handler.post {
            androidAutoEnabled?.let {
                NitroPlayerMediaBrowserService.isAndroidAutoEnabled = it
            }
            mediaSessionManager?.configure(
                androidAutoEnabled,
                carPlayEnabled,
                showInNotification,
            )
        }
    }

    // Public method to get all playlists (for MediaBrowserService and other classes)
    fun getAllPlaylists(): List<com.margelo.nitro.nitroplayer.playlist.Playlist> = playlistManager.getAllPlaylists()

    // Public method to get current track for MediaBrowserService
    fun getCurrentTrack(): TrackItem? {
        if (!::player.isInitialized) return null
        val currentMediaItem = player.currentMediaItem ?: return null
        return findTrack(currentMediaItem)
    }

    // Public method to play from a specific index (for Android Auto)
    fun playFromIndex(index: Int) {
        handler.post {
            if (::player.isInitialized && index >= 0 && index < player.mediaItemCount) {
                player.seekToDefaultPosition(index)
                player.playWhenReady = true
            }
        }
    }

    // Clean up resources
    fun destroy() {
        handler.post {
            androidAutoConnectionDetector?.unregisterCarConnectionReceiver()
            handler.removeCallbacks(progressUpdateRunnable)
        }
    }

    // Check if Android Auto is connected
    fun isAndroidAutoConnected(): Boolean = isAndroidAutoConnected
}
