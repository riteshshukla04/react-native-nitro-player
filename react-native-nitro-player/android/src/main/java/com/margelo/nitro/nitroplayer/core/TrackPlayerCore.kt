@file:Suppress("ktlint:standard:max-line-length", "ktlint:standard:if-else-wrapping")

package com.margelo.nitro.nitroplayer.core

import android.content.Context
import android.net.Uri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import com.margelo.nitro.core.NullType
import com.margelo.nitro.nitroplayer.CurrentPlayingType
import com.margelo.nitro.nitroplayer.NitroPlayerPackage
import com.margelo.nitro.nitroplayer.PlayerState
import com.margelo.nitro.nitroplayer.Reason
import com.margelo.nitro.nitroplayer.RepeatMode
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.TrackPlayerState
import com.margelo.nitro.nitroplayer.Variant_NullType_String
import com.margelo.nitro.nitroplayer.Variant_NullType_TrackItem
import com.margelo.nitro.nitroplayer.connection.AndroidAutoConnectionDetector
import com.margelo.nitro.nitroplayer.download.DownloadManagerCore
import com.margelo.nitro.nitroplayer.equalizer.EqualizerCore
import com.margelo.nitro.nitroplayer.media.MediaLibrary
import com.margelo.nitro.nitroplayer.media.MediaLibraryManager
import com.margelo.nitro.nitroplayer.media.MediaLibraryParser
import com.margelo.nitro.nitroplayer.media.MediaSessionManager
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager
import java.lang.ref.WeakReference
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class TrackPlayerCore private constructor(
    private val context: Context,
) {
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private lateinit var player: ExoPlayer
    private val playlistManager = PlaylistManager.getInstance(context)

    // Named Runnable so handler.removeCallbacks() can coalesce rapid playlist
    // mutations (e.g. N individual removes followed by a batch add during shuffle)
    // into a single player update, preventing audio gaps on Android.
    private val updateCurrentPlaylistRunnable = Runnable {
        val playlistId = currentPlaylistId ?: return@Runnable
        val playlist = playlistManager.getPlaylist(playlistId) ?: return@Runnable

        // Always update the canonical track list first.
        currentTracks = playlist.tracks

        if (::player.isInitialized && player.currentMediaItem != null && player.currentMediaItemIndex >= 0) {
            // Something is actively playing — rebuild only the items AFTER the
            // current position using surgical removeMediaItems/addMediaItems.
            // This avoids setMediaItems() which replaces the entire ExoPlayer
            // queue (including the current item) and causes an audible gap.
            rebuildQueueFromCurrentPosition()
        } else {
            // Nothing playing yet — safe to do a full replace.
            updatePlayerQueue(playlist.tracks)
        }
    }
    private val downloadManager = DownloadManagerCore.getInstance(context)
    private val mediaLibraryManager = MediaLibraryManager.getInstance(context)
    private var mediaSessionManager: MediaSessionManager? = null
    @Volatile private var currentPlaylistId: String? = null
    private var isManuallySeeked = false
    @Volatile private var isAndroidAutoConnected: Boolean = false
    private var androidAutoConnectionDetector: AndroidAutoConnectionDetector? = null
    var onAndroidAutoConnectionChange: ((Boolean) -> Unit)? = null
    private var previousMediaItem: MediaItem? = null

    private val progressUpdateRunnable =
        object : Runnable {
            override fun run() {
                if (::player.isInitialized && player.playbackState != Player.STATE_IDLE) {
                    val position = player.currentPosition / 1000.0
                    val duration = if (player.duration > 0) player.duration / 1000.0 else 0.0
                    notifyPlaybackProgress(position, duration, if (isManuallySeeked) true else null)
                    isManuallySeeked = false
                }
                handler.postDelayed(this, 250) // Update every 250ms
            }
        }

    // Weak callback wrapper for auto-cleanup
    private data class WeakCallbackBox<T>(
        private val ownerRef: WeakReference<Any>,
        val callback: T,
    ) {
        val isAlive: Boolean get() = ownerRef.get() != null
    }

    // Event listeners - support multiple listeners with auto-cleanup
    private val onChangeTrackListeners =
        Collections.synchronizedList(mutableListOf<WeakCallbackBox<(TrackItem, Reason?) -> Unit>>())
    private val onPlaybackStateChangeListeners =
        Collections.synchronizedList(mutableListOf<WeakCallbackBox<(TrackPlayerState, Reason?) -> Unit>>())
    private val onSeekListeners =
        Collections.synchronizedList(mutableListOf<WeakCallbackBox<(Double, Double) -> Unit>>())
    private val onPlaybackProgressChangeListeners =
        Collections.synchronizedList(mutableListOf<WeakCallbackBox<(Double, Double, Boolean?) -> Unit>>())

    @Volatile private var currentRepeatMode: RepeatMode = RepeatMode.OFF
    private var lookaheadCount: Int = 5 // Number of tracks to preload ahead
    private var playerListener: Player.Listener? = null

    // Temporary tracks for addToUpNext and playNext
    private var playNextStack: MutableList<TrackItem> = mutableListOf() // LIFO - last added plays first
    private var upNextQueue: MutableList<TrackItem> = mutableListOf() // FIFO - first added plays first
    private var currentTemporaryType: TemporaryType = TemporaryType.NONE
    private var currentTracks: List<TrackItem> = emptyList()
    private var currentTrackIndex: Int = -1 // Index in the original playlist (currentTracks)

    // Enum to track what type of track is currently playing
    private enum class TemporaryType {
        NONE, // Playing from original playlist
        PLAY_NEXT, // Currently in playNextStack
        UP_NEXT, // Currently in upNextQueue
    }

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
        // Run synchronously on main thread to avoid deadlock
        // when awaitInitialization is called from main thread
        val initRunnable =
            Runnable {
                // ============================================================
                // GAPLESS PLAYBACK CONFIGURATION
                // ============================================================
                // Configure LoadControl for maximum gapless playback
                // Large buffers ensure next track is fully ready before current ends
                val loadControl =
                    DefaultLoadControl
                        .Builder()
                        .setBufferDurationsMs(
                            30_000, // MIN_BUFFER_MS: 30 seconds minimum buffer
                            120_000, // MAX_BUFFER_MS: 2 minutes maximum buffer (enables preloading next tracks)
                            2_500, // BUFFER_FOR_PLAYBACK_MS: 2.5s before playback starts
                            5_000, // BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS: 5s after rebuffer
                        ).setBackBuffer(30_000, true) // Keep 30s back buffer for seamless seek-back
                        .setTargetBufferBytes(C.LENGTH_UNSET) // No size limit - prioritize time
                        .setPrioritizeTimeOverSizeThresholds(true) // Prioritize time-based buffering
                        .build()

                // Configure audio attributes for optimal music playback
                // This enables gapless audio processing in the audio pipeline
                val audioAttributes =
                    AudioAttributes
                        .Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                        .build()

                player =
                    ExoPlayer
                        .Builder(context)
                        .setLoadControl(loadControl)
                        .setAudioAttributes(audioAttributes, true) // handleAudioFocus = true for gapless
                        .setHandleAudioBecomingNoisy(true) // Pause when headphones disconnected
                        .setPauseAtEndOfMediaItems(false) // Don't pause between items - key for gapless!
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

                                NitroPlayerLogger.log("TrackPlayerCore") { "🚗 Android Auto connection changed: connected=$connected, type=$connectionType" }
                            }
                        }
                        registerCarConnectionReceiver()
                    }

                val listener = object : Player.Listener {
                        override fun onMediaItemTransition(
                            mediaItem: MediaItem?,
                            reason: Int,
                        ) {
                            NitroPlayerLogger.log("TrackPlayerCore") { "\n🔄 onMediaItemTransition called" }
                            NitroPlayerLogger.log("TrackPlayerCore") {
                                "   reason: ${when (reason) {
                                    Player.MEDIA_ITEM_TRANSITION_REASON_AUTO -> "AUTO (track ended)"
                                    Player.MEDIA_ITEM_TRANSITION_REASON_SEEK -> "SEEK"
                                    Player.MEDIA_ITEM_TRANSITION_REASON_PLAYLIST_CHANGED -> "PLAYLIST_CHANGED"
                                    else -> "UNKNOWN($reason)"
                                }}"
                            }
                            NitroPlayerLogger.log("TrackPlayerCore") { "   previousMediaItem: ${previousMediaItem?.mediaId}" }
                            NitroPlayerLogger.log("TrackPlayerCore") { "   new mediaItem: ${mediaItem?.mediaId}" }
                            NitroPlayerLogger.log("TrackPlayerCore") { "   playNextStack: ${playNextStack.map { it.id }}" }
                            NitroPlayerLogger.log("TrackPlayerCore") { "   upNextQueue: ${upNextQueue.map { it.id }}" }

                            // TRACK repeat: REPEAT_MODE_ONE fires this callback every loop — skip entirely
                            if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_REPEAT) {
                                NitroPlayerLogger.log("TrackPlayerCore") { "   🔁 TRACK repeat loop — skipping notifyTrackChange" }
                                return
                            }

                            // Remove finished track from temporary lists
                            // Handle AUTO (natural end) and SEEK (skip next) transitions
                            if ((
                                    reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO ||
                                        reason == Player.MEDIA_ITEM_TRANSITION_REASON_SEEK
                                ) &&
                                previousMediaItem != null
                            ) {
                                previousMediaItem?.mediaId?.let { mediaId ->
                                    val trackId = extractTrackId(mediaId)
                                    NitroPlayerLogger.log("TrackPlayerCore") { "🏁 Track finished/skipped, checking for removal: $trackId" }

                                    // Find and remove from playNext stack (like iOS does)
                                    val playNextIndex = playNextStack.indexOfFirst { it.id == trackId }
                                    if (playNextIndex >= 0) {
                                        val track = playNextStack.removeAt(playNextIndex)
                                        NitroPlayerLogger.log("TrackPlayerCore") { "   ✅ Removed from playNext stack: ${track.title}" }
                                    } else {
                                        // Find and remove from upNext queue
                                        val upNextIndex = upNextQueue.indexOfFirst { it.id == trackId }
                                        if (upNextIndex >= 0) {
                                            val track = upNextQueue.removeAt(upNextIndex)
                                            NitroPlayerLogger.log("TrackPlayerCore") { "   ✅ Removed from upNext queue: ${track.title}" }
                                        } else {
                                            NitroPlayerLogger.log("TrackPlayerCore") { "   ℹ️  Was an original playlist track" }
                                        }
                                    }
                                }
                            } else {
                                NitroPlayerLogger.log("TrackPlayerCore") { "   ⏭️  Skipping removal (reason=$reason, prev=${previousMediaItem != null})" }
                            }

                            // Store current item as previous for next transition
                            previousMediaItem = mediaItem

                            // Update temporary type for current track
                            currentTemporaryType = determineCurrentTemporaryType()
                            NitroPlayerLogger.log("TrackPlayerCore") { "   Updated currentTemporaryType: $currentTemporaryType" }

                            // Update currentTrackIndex when we land on an original playlist track
                            if (currentTemporaryType == TemporaryType.NONE && mediaItem != null) {
                                val trackId = extractTrackId(mediaItem.mediaId)
                                val newIndex = currentTracks.indexOfFirst { it.id == trackId }
                                if (newIndex >= 0 && newIndex != currentTrackIndex) {
                                    NitroPlayerLogger.log("TrackPlayerCore") { "   📍 Updating currentTrackIndex from $currentTrackIndex to $newIndex" }
                                    currentTrackIndex = newIndex
                                }
                            }

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
                                            NitroPlayerLogger.log(
                                                "TrackPlayerCore",
                                                "⚠️ TrackPlayerCore: Detected track from different playlist, updating...",
                                            )
                                        }
                                    }
                                }
                            }

                            // Use getCurrentTrack() which handles temporary tracks properly
                            val track = getCurrentTrack()
                            if (track != null) {
                                val r =
                                    when (reason) {
                                        Player.MEDIA_ITEM_TRANSITION_REASON_AUTO -> Reason.END
                                        Player.MEDIA_ITEM_TRANSITION_REASON_SEEK -> Reason.USER_ACTION
                                        Player.MEDIA_ITEM_TRANSITION_REASON_PLAYLIST_CHANGED -> Reason.USER_ACTION
                                        else -> null
                                    }
                                notifyTrackChange(track, r)
                                mediaSessionManager?.onTrackChanged()

                                // Check if upcoming tracks need URLs
                                checkUpcomingTracksForUrls(lookahead = lookaheadCount)
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
                            if (playbackState == Player.STATE_ENDED && currentRepeatMode == RepeatMode.PLAYLIST) {
                                NitroPlayerLogger.log("TrackPlayerCore") { "🔁 PLAYLIST repeat — rebuilding original queue and restarting" }
                                handler.post {
                                    playNextStack.clear()
                                    upNextQueue.clear()
                                    currentTemporaryType = TemporaryType.NONE
                                    // Rebuild ExoPlayer queue from beginning of original playlist
                                    rebuildQueueAndPlayFromIndex(0)
                                    val firstTrack = currentTracks.getOrNull(0)
                                    if (firstTrack != null) notifyTrackChange(firstTrack, Reason.REPEAT)
                                }
                                return
                            }
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
                                notifySeek(newPosition.positionMs / 1000.0, player.duration / 1000.0)
                            }
                        }

                        override fun onAudioSessionIdChanged(audioSessionId: Int) {
                            if (audioSessionId != 0) {
                                try {
                                    EqualizerCore.getInstance(context).initialize(audioSessionId)
                                } catch (e: Exception) {
                                    // Equalizer initialization failed - non-critical
                                }
                            }
                        }
                }
                playerListener = listener
                player.addListener(listener)

                // Start progress updates
                handler.post(progressUpdateRunnable)
            }

        // Execute on main thread: if already on main thread, run synchronously to avoid deadlock
        if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
            initRunnable.run()
        } else {
            handler.post(initRunnable)
        }
    }

    /**
     * Load a playlist for playback using ExoPlayer's native playlist API
     * Based on: https://developer.android.com/media/media3/exoplayer/playlists
     */
    fun loadPlaylist(playlistId: String) {
        handler.post {
            // Clear temporary tracks when loading new playlist
            playNextStack.clear()
            upNextQueue.clear()
            currentTemporaryType = TemporaryType.NONE
            NitroPlayerLogger.log("TrackPlayerCore", "   🧹 Cleared temporary tracks")

            val playlist = playlistManager.getPlaylist(playlistId)
            if (playlist != null) {
                currentPlaylistId = playlistId
                updatePlayerQueue(playlist.tracks)

                // Check if upcoming tracks need URLs
                checkUpcomingTracksForUrls(lookahead = lookaheadCount)
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
                NitroPlayerLogger.log("TrackPlayerCore") { "❌ TrackPlayerCore: Error playing from playlist track - ${e.message}" }
                e.printStackTrace()
            }
        }
    }

    /**
     * Update the player queue when playlist changes
     */
    fun updatePlaylist(playlistId: String) {
        // Debounce: rapid back-to-back calls (e.g. removing N tracks then adding
        // the shuffled replacement) are coalesced into a single setMediaItems call.
        // removeCallbacks cancels any pending-but-not-yet-executed callback so only
        // the final playlist state triggers a player rebuild.
        if (currentPlaylistId != playlistId) return
        handler.removeCallbacks(updateCurrentPlaylistRunnable)
        handler.post(updateCurrentPlaylistRunnable)
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
        notifyPlaybackStateChange(state, actualReason)
        mediaSessionManager?.onPlaybackStateChanged()
    }

    private fun updatePlayerQueue(tracks: List<TrackItem>) {
        // Store the original tracks
        currentTracks = tracks

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

        // Use downloadManager.getEffectiveUrl to automatically get local path if downloaded
        val effectiveUrl = downloadManager.getEffectiveUrl(this)

        return MediaItem
            .Builder()
            .setMediaId(customMediaId ?: id)
            .setUri(effectiveUrl)
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

        // currentTracks is already the cached tracks for currentPlaylistId — no need to
        // re-fetch from PlaylistManager on every call.
        return currentTracks.find { it.id == trackId }
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
        handler.post {
            playSongInternal(songId, fromPlaylist)
        }
    }

    private fun playSongInternal(
        songId: String,
        fromPlaylist: String?,
    ) {
        // Clear temporary tracks when directly playing a song
        playNextStack.clear()
        upNextQueue.clear()
        currentTemporaryType = TemporaryType.NONE
        NitroPlayerLogger.log("TrackPlayerCore", "   🧹 Cleared temporary tracks")

        var targetPlaylistId: String? = null
        var songIndex: Int = -1

        // Case 1: If fromPlaylist is provided, use that playlist
        if (fromPlaylist != null) {
            NitroPlayerLogger.log("TrackPlayerCore") { "🎵 TrackPlayerCore: Looking for song in specified playlist: $fromPlaylist" }
            val playlist = playlistManager.getPlaylist(fromPlaylist)
            if (playlist != null) {
                songIndex = playlist.tracks.indexOfFirst { it.id == songId }
                if (songIndex >= 0) {
                    targetPlaylistId = fromPlaylist
                    NitroPlayerLogger.log("TrackPlayerCore") { "✅ Found song at index $songIndex in playlist $fromPlaylist" }
                } else {
                    NitroPlayerLogger.log("TrackPlayerCore") { "⚠️ Song $songId not found in specified playlist $fromPlaylist" }
                    return
                }
            } else {
                NitroPlayerLogger.log("TrackPlayerCore") { "⚠️ Playlist $fromPlaylist not found" }
                return
            }
        }
        // Case 2: If fromPlaylist is not provided, search in current/loaded playlist first
        else {
            NitroPlayerLogger.log("TrackPlayerCore", "🎵 TrackPlayerCore: No playlist specified, checking current playlist")

            // Check if song exists in currently loaded playlist
            if (currentPlaylistId != null) {
                val currentPlaylist = playlistManager.getPlaylist(currentPlaylistId!!)
                if (currentPlaylist != null) {
                    songIndex = currentPlaylist.tracks.indexOfFirst { it.id == songId }
                    if (songIndex >= 0) {
                        targetPlaylistId = currentPlaylistId
                        NitroPlayerLogger.log("TrackPlayerCore") { "✅ Found song at index $songIndex in current playlist $currentPlaylistId" }
                    }
                }
            }

            // If not found in current playlist, search in all playlists
            if (songIndex == -1) {
                NitroPlayerLogger.log("TrackPlayerCore", "🔍 Song not found in current playlist, searching all playlists...")
                val allPlaylists = playlistManager.getAllPlaylists()

                for (playlist in allPlaylists) {
                    songIndex = playlist.tracks.indexOfFirst { it.id == songId }
                    if (songIndex >= 0) {
                        targetPlaylistId = playlist.id
                        NitroPlayerLogger.log("TrackPlayerCore") { "✅ Found song at index $songIndex in playlist ${playlist.id}" }
                        break
                    }
                }

                // If still not found, just use the first playlist if available
                if (songIndex == -1 && allPlaylists.isNotEmpty()) {
                    targetPlaylistId = allPlaylists[0].id
                    songIndex = 0
                    NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Song not found in any playlist, using first playlist and starting at index 0")
                }
            }
        }

        // Now play the song
        if (targetPlaylistId == null || songIndex < 0) {
            NitroPlayerLogger.log("TrackPlayerCore", "❌ Could not determine playlist or song index")
            return
        }

        // Load playlist if it's different from current
        if (currentPlaylistId != targetPlaylistId) {
            NitroPlayerLogger.log("TrackPlayerCore") { "🔄 Loading new playlist: $targetPlaylistId" }
            val playlist = playlistManager.getPlaylist(targetPlaylistId)
            if (playlist != null) {
                currentPlaylistId = targetPlaylistId
                updatePlayerQueue(playlist.tracks)

                // Wait a bit for playlist to load, then play from index
                // Note: Removed postDelayed to avoid race conditions with subsequent queue operations
                NitroPlayerLogger.log("TrackPlayerCore") { "▶️ Playing from index: $songIndex" }
                playFromIndex(songIndex)
            }
        } else {
            // Playlist already loaded, just play from index
            NitroPlayerLogger.log("TrackPlayerCore") { "▶️ Playing from index: $songIndex" }
            playFromIndex(songIndex)
        }
    }

    fun skipToNext() {
        handler.post {
            if (player.hasNextMediaItem()) {
                player.seekToNextMediaItem()

                // Check if upcoming tracks need URLs
                checkUpcomingTracksForUrls(lookahead = lookaheadCount)
            }
        }
    }

    fun skipToPrevious() {
        handler.post {
            val currentPosition = player.currentPosition // milliseconds

            if (currentPosition > 2000) {
                // More than 2 seconds in, restart current track
                NitroPlayerLogger.log("TrackPlayerCore", "🔄 TrackPlayerCore: Past threshold, restarting current track")
                player.seekTo(0)
            } else if (currentTemporaryType != TemporaryType.NONE) {
                // Playing temporary track within threshold — remove from its list, go back to original
                NitroPlayerLogger.log("TrackPlayerCore", "🔄 TrackPlayerCore: Removing temp track, going back to original")
                val currentMediaItem = player.currentMediaItem
                if (currentMediaItem != null) {
                    val trackId = extractTrackId(currentMediaItem.mediaId)
                    when (currentTemporaryType) {
                        TemporaryType.PLAY_NEXT -> {
                            val idx = playNextStack.indexOfFirst { it.id == trackId }
                            if (idx >= 0) playNextStack.removeAt(idx)
                        }

                        TemporaryType.UP_NEXT -> {
                            val idx = upNextQueue.indexOfFirst { it.id == trackId }
                            if (idx >= 0) upNextQueue.removeAt(idx)
                        }

                        else -> {}
                    }
                }
                currentTemporaryType = TemporaryType.NONE
                playFromIndexInternal(currentTrackIndex)
            } else if (currentTrackIndex > 0) {
                // Go to previous track in original playlist
                NitroPlayerLogger.log("TrackPlayerCore") { "🔄 TrackPlayerCore: Going to previous track, currentTrackIndex: $currentTrackIndex -> ${currentTrackIndex - 1}" }
                playFromIndexInternal(currentTrackIndex - 1)
            } else {
                // Already at first track, seek to beginning
                NitroPlayerLogger.log("TrackPlayerCore", "🔄 TrackPlayerCore: Already at first track, seeking to beginning")
                player.seekTo(0)
            }

            // Check if upcoming tracks need URLs
            checkUpcomingTracksForUrls(lookahead = lookaheadCount)
        }
    }

    fun seek(position: Double) {
        handler.post {
            isManuallySeeked = true
            player.seekTo((position * 1000).toLong())
        }
    }

    fun setRepeatMode(mode: RepeatMode): Boolean {
        currentRepeatMode = mode
        if (::player.isInitialized) {
            handler.post {
                player.repeatMode =
                    when (mode) {
                        RepeatMode.TRACK -> Player.REPEAT_MODE_ONE
                        else -> Player.REPEAT_MODE_OFF
                    }
            }
        }
        NitroPlayerLogger.log("TrackPlayerCore") { "🔁 setRepeatMode: $mode" }
        return true
    }

    fun getRepeatMode(): RepeatMode = currentRepeatMode

    fun getState(): PlayerState {
        // Called from Promise.async background thread
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

        return result ?: PlayerState(
            currentTrack = null,
            currentPosition = 0.0,
            totalDuration = 0.0,
            currentState = TrackPlayerState.STOPPED,
            currentPlaylistId = null,
            currentIndex = -1.0,
            currentPlayingType = CurrentPlayingType.NOT_PLAYING
        )
    }

    private fun getStateInternal(): PlayerState =
        if (::player.isInitialized) {
            // Use getCurrentTrack() which handles temporary tracks properly
            val track = getCurrentTrack()

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

            // Use ExoPlayer's currentMediaItemIndex
            val currentIndex =
                if (player.currentMediaItemIndex >= 0) {
                    player.currentMediaItemIndex.toDouble()
                } else {
                    -1.0
                }

            // Map internal temporary type to CurrentPlayingType
            val currentPlayingTypeValue =
                if (track == null) {
                    CurrentPlayingType.NOT_PLAYING
                } else {
                    when (currentTemporaryType) {
                        TemporaryType.NONE -> CurrentPlayingType.PLAYLIST
                        TemporaryType.PLAY_NEXT -> CurrentPlayingType.PLAY_NEXT
                        TemporaryType.UP_NEXT -> CurrentPlayingType.UP_NEXT
                    }
                }

            PlayerState(
                currentTrack = currentTrack,
                currentPosition = currentPosition,
                totalDuration = totalDuration,
                currentState = currentState,
                currentPlaylistId = currentPlaylistId?.let { Variant_NullType_String.create(it) },
                currentIndex = currentIndex,
                currentPlayingType = currentPlayingTypeValue,
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
                currentPlayingType = CurrentPlayingType.NOT_PLAYING,
            )
        }

    fun configure(
        androidAutoEnabled: Boolean?,
        carPlayEnabled: Boolean?,
        showInNotification: Boolean?,
        lookaheadCount: Int? = null,
    ) {
        handler.post {
            androidAutoEnabled?.let {
                NitroPlayerMediaBrowserService.isAndroidAutoEnabled = it
            }
            lookaheadCount?.let {
                this.lookaheadCount = it
                NitroPlayerLogger.log("TrackPlayerCore") { "🔄 Lookahead count set to: $it" }
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

        // If playing a temporary track, return that
        if (currentTemporaryType != TemporaryType.NONE) {
            val trackId = extractTrackId(currentMediaItem.mediaId)

            when (currentTemporaryType) {
                TemporaryType.PLAY_NEXT -> {
                    return playNextStack.firstOrNull { it.id == trackId }
                }

                TemporaryType.UP_NEXT -> {
                    return upNextQueue.firstOrNull { it.id == trackId }
                }

                else -> {}
            }
        }

        // Otherwise return from original playlist
        return findTrack(currentMediaItem)
    }

    private fun extractTrackId(mediaId: String): String =
        if (mediaId.contains(':')) {
            // Format: "playlistId:trackId"
            mediaId.substring(mediaId.indexOf(':') + 1)
        } else {
            mediaId
        }

    // Public method to play from a specific index (for Android Auto)
    // Public method to play from a specific index (for Android Auto)
    fun playFromIndex(index: Int) {
        if (android.os.Looper.myLooper() == handler.looper) {
            playFromIndexInternal(index)
        } else {
            handler.post {
                playFromIndexInternal(index)
            }
        }
    }

    // MARK: - Skip to Index in Actual Queue

    fun skipToIndex(index: Int): Boolean {
        // Check if we're already on the main thread
        if (android.os.Looper.myLooper() == handler.looper) {
            return skipToIndexInternal(index)
        }

        // Use CountDownLatch to wait for the result on the main thread
        val latch = CountDownLatch(1)
        var result = false

        handler.post {
            try {
                result = skipToIndexInternal(index)
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

        return result
    }

    private fun skipToIndexInternal(index: Int): Boolean {
        if (!::player.isInitialized) return false

        // Get actual queue to validate index and determine position
        val actualQueue = getActualQueueInternal()
        val totalQueueSize = actualQueue.size

        // Validate index
        if (index < 0 || index >= totalQueueSize) return false

        // Calculate queue section boundaries using effective sizes
        // (reduced by 1 when current track is from that temp list, matching getActualQueueInternal)
        // When temp is playing, the original track at currentTrackIndex is included in "before",
        // so the current playing position shifts by 1
        val currentPos =
            if (currentTemporaryType != TemporaryType.NONE) {
                currentTrackIndex + 1
            } else {
                currentTrackIndex
            }
        val effectivePlayNextSize =
            if (currentTemporaryType == TemporaryType.PLAY_NEXT) {
                maxOf(0, playNextStack.size - 1)
            } else {
                playNextStack.size
            }
        val effectiveUpNextSize =
            if (currentTemporaryType == TemporaryType.UP_NEXT) {
                maxOf(0, upNextQueue.size - 1)
            } else {
                upNextQueue.size
            }

        val playNextStart = currentPos + 1
        val playNextEnd = playNextStart + effectivePlayNextSize
        val upNextStart = playNextEnd
        val upNextEnd = upNextStart + effectiveUpNextSize
        val originalRemainingStart = upNextEnd

        // Case 1: Target is before current - use playFromIndex on original
        if (index < currentPos) {
            playFromIndexInternal(index)
            return true
        }

        // Case 2: Target is current - seek to beginning
        if (index == currentPos) {
            player.seekTo(0)
            return true
        }

        // Case 3: Target is in playNext section
        if (index >= playNextStart && index < playNextEnd) {
            val playNextIndex = index - playNextStart
            // Offset by 1 if current is from playNext (index 0 is already playing)
            val actualListIndex =
                if (currentTemporaryType == TemporaryType.PLAY_NEXT) {
                    playNextIndex + 1
                } else {
                    playNextIndex
                }

            // Remove tracks before the target from playNext (they're being skipped)
            if (actualListIndex > 0) {
                playNextStack.subList(0, actualListIndex).clear()
            }

            // Rebuild queue and advance
            rebuildQueueFromCurrentPosition()
            player.seekToNextMediaItem()
            return true
        }

        // Case 4: Target is in upNext section
        if (index >= upNextStart && index < upNextEnd) {
            val upNextIndex = index - upNextStart
            // Offset by 1 if current is from upNext (index 0 is already playing)
            val actualListIndex =
                if (currentTemporaryType == TemporaryType.UP_NEXT) {
                    upNextIndex + 1
                } else {
                    upNextIndex
                }

            // Clear all playNext tracks (they're being skipped)
            playNextStack.clear()

            // Remove tracks before target from upNext
            if (actualListIndex > 0) {
                upNextQueue.subList(0, actualListIndex).clear()
            }

            // Rebuild queue and advance
            rebuildQueueFromCurrentPosition()
            player.seekToNextMediaItem()
            return true
        }

        // Case 5: Target is in remaining original tracks
        if (index >= originalRemainingStart) {
            val targetTrack = actualQueue[index]

            // Find this track's index in the original playlist
            val originalIndex = currentTracks.indexOfFirst { it.id == targetTrack.id }
            if (originalIndex == -1) return false

            // Clear all temporary tracks (they're being skipped)
            playNextStack.clear()
            upNextQueue.clear()
            currentTemporaryType = TemporaryType.NONE

            rebuildQueueAndPlayFromIndex(originalIndex)

            // Check if upcoming tracks need URLs
            checkUpcomingTracksForUrls(lookahead = lookaheadCount)

            return true
        }

        // Check if upcoming tracks need URLs after any successful skip
        checkUpcomingTracksForUrls(lookahead = lookaheadCount)

        return false
    }

    private fun playFromIndexInternal(index: Int) {
        // Clear temporary tracks when jumping to specific index
        playNextStack.clear()
        upNextQueue.clear()
        currentTemporaryType = TemporaryType.NONE

        rebuildQueueAndPlayFromIndex(index)
    }

    /**
     * Rebuild the entire ExoPlayer queue from the original playlist starting at the given index
     * This clears all temporary tracks and rebuilds the queue fresh
     */
    private fun rebuildQueueAndPlayFromIndex(index: Int) {
        if (!::player.isInitialized) {
            NitroPlayerLogger.log("TrackPlayerCore", "   ❌ Player not initialized")
            return
        }

        if (index < 0 || index >= currentTracks.size) {
            NitroPlayerLogger.log("TrackPlayerCore") { "   ❌ Invalid index $index for currentTracks size ${currentTracks.size}" }
            return
        }

        NitroPlayerLogger.log("TrackPlayerCore") { "\n🔄 TrackPlayerCore: REBUILD QUEUE AND PLAY FROM INDEX $index" }
        NitroPlayerLogger.log("TrackPlayerCore") { "   currentTracks.size: ${currentTracks.size}" }
        NitroPlayerLogger.log("TrackPlayerCore") { "   currentTracks IDs: ${currentTracks.map { it.id }}" }

        // Build queue from the target index onwards
        val tracksToPlay = currentTracks.subList(index, currentTracks.size)
        NitroPlayerLogger.log("TrackPlayerCore") { "   tracksToPlay (${tracksToPlay.size}): ${tracksToPlay.map { it.id }}" }

        val playlistId = currentPlaylistId ?: ""
        val mediaItems =
            tracksToPlay.map { track ->
                val mediaId = if (playlistId.isNotEmpty()) "$playlistId:${track.id}" else track.id
                track.toMediaItem(mediaId)
            }

        // Update our internal tracking of the position in original playlist
        currentTrackIndex = index
        NitroPlayerLogger.log("TrackPlayerCore") { "   Setting currentTrackIndex to $index" }

        // Clear the entire player queue and set new items
        player.clearMediaItems()
        player.setMediaItems(mediaItems)
        player.seekToDefaultPosition(0) // Seek to first item (which is our target track)
        player.playWhenReady = true
        player.prepare()

        NitroPlayerLogger.log("TrackPlayerCore") { "   ✅ Queue rebuilt with ${player.mediaItemCount} items, playing from index 0 (track ${tracksToPlay.firstOrNull()?.id})" }
    }

    // MARK: - Temporary Track Management

    /**
     * Add a track to the up-next queue (FIFO - first added plays first)
     * Track will be inserted after currently playing track and any playNext tracks
     */
    fun addToUpNext(trackId: String) {
        handler.post {
            addToUpNextInternal(trackId)
        }
    }

    private fun addToUpNextInternal(trackId: String) {
        NitroPlayerLogger.log("TrackPlayerCore") { "📋 TrackPlayerCore: addToUpNext($trackId)" }

        // Find the track from current playlist or all playlists
        val track = findTrackById(trackId)
        if (track == null) {
            NitroPlayerLogger.log("TrackPlayerCore") { "❌ TrackPlayerCore: Track $trackId not found" }
            return
        }

        // Add to end of upNext queue (FIFO)
        upNextQueue.add(track)
        NitroPlayerLogger.log("TrackPlayerCore") { "   ✅ Added '${track.title}' to upNext queue (position: ${upNextQueue.size})" }

        // Rebuild the player queue if actively playing
        if (::player.isInitialized && player.currentMediaItem != null) {
            rebuildQueueFromCurrentPosition()
        }
    }

    /**
     * Add a track to play next (LIFO - last added plays first)
     * Track will be inserted immediately after currently playing track
     */
    fun playNext(trackId: String) {
        handler.post {
            playNextInternal(trackId)
        }
    }

    private fun playNextInternal(trackId: String) {
        NitroPlayerLogger.log("TrackPlayerCore") { "⏭️ TrackPlayerCore: playNext($trackId)" }

        // Find the track from current playlist or all playlists
        val track = findTrackById(trackId)
        if (track == null) {
            NitroPlayerLogger.log("TrackPlayerCore") { "❌ TrackPlayerCore: Track $trackId not found" }
            return
        }

        // Insert at beginning of playNext stack (LIFO)
        playNextStack.add(0, track)
        NitroPlayerLogger.log("TrackPlayerCore") { "   ✅ Added '${track.title}' to playNext stack (position: 1)" }

        // Rebuild the player queue if actively playing
        if (::player.isInitialized && player.currentMediaItem != null) {
            rebuildQueueFromCurrentPosition()
        }
    }

    /**
     * Rebuild the ExoPlayer queue from current position with temporary tracks
     * Order: [current] + [playNext stack] + [upNext queue] + [remaining original]
     */
    private fun rebuildQueueFromCurrentPosition() {
        if (!::player.isInitialized) return

        val currentIndex = player.currentMediaItemIndex
        if (currentIndex < 0) return

        // Handle removed-current-track case: if the currently playing media item is no longer
        // in currentTracks (e.g. the user removed it while it was playing), delegate to
        // playFromIndexInternal so the player immediately starts the next track.
        val currentTrackId = player.currentMediaItem?.mediaId?.let { extractTrackId(it) }
        if (currentTrackId != null && currentTracks.none { it.id == currentTrackId }) {
            val targetIndex = when {
                currentTracks.isEmpty() -> return
                currentTrackIndex < currentTracks.size -> currentTrackIndex
                else -> currentTracks.size - 1
            }
            playFromIndexInternal(targetIndex)
            return
        }

        val newQueueTracks = ArrayList<TrackItem>(playNextStack.size + upNextQueue.size + currentTracks.size)

        // Add playNext stack (LIFO - most recently added plays first)
        // Skip index 0 if current track is from playNext (it's already playing)
        if (currentTemporaryType == TemporaryType.PLAY_NEXT && playNextStack.size > 1) {
            newQueueTracks.addAll(playNextStack.subList(1, playNextStack.size))
        } else if (currentTemporaryType != TemporaryType.PLAY_NEXT) {
            newQueueTracks.addAll(playNextStack)
        }

        // Add upNext queue (in order, FIFO)
        // Skip index 0 if current track is from upNext (it's already playing)
        if (currentTemporaryType == TemporaryType.UP_NEXT && upNextQueue.size > 1) {
            newQueueTracks.addAll(upNextQueue.subList(1, upNextQueue.size))
        } else if (currentTemporaryType != TemporaryType.UP_NEXT) {
            newQueueTracks.addAll(upNextQueue)
        }

        // Add remaining original tracks — use currentTrackIndex (original playlist position)
        if (currentTrackIndex + 1 < currentTracks.size) {
            val remaining = currentTracks.subList(currentTrackIndex + 1, currentTracks.size)
            newQueueTracks.addAll(remaining)
        }

        // Create MediaItems for new tracks
        val playlistId = currentPlaylistId ?: ""
        val newMediaItems =
            newQueueTracks.map { track ->
                val mediaId = if (playlistId.isNotEmpty()) "$playlistId:${track.id}" else track.id
                track.toMediaItem(mediaId)
            }

        // Remove all items after current in one batch (single timeline event vs N events)
        if (player.mediaItemCount > currentIndex + 1) {
            player.removeMediaItems(currentIndex + 1, player.mediaItemCount)
        }

        // Add new items
        player.addMediaItems(newMediaItems)
    }

    /**
     * Find a track by ID from current playlist or all playlists
     */
    private fun findTrackById(trackId: String): TrackItem? {
        // First check current playlist
        currentTracks.find { it.id == trackId }?.let { return it }

        // Then check all playlists
        val allPlaylists = playlistManager.getAllPlaylists()
        for (playlist in allPlaylists) {
            playlist.tracks.find { it.id == trackId }?.let { return it }
        }

        return null
    }

    /**
     * Determine what type of track is currently playing
     */
    private fun determineCurrentTemporaryType(): TemporaryType {
        val currentItem = player.currentMediaItem ?: return TemporaryType.NONE
        val trackId =
            if (currentItem.mediaId.contains(':')) {
                currentItem.mediaId.substring(currentItem.mediaId.indexOf(':') + 1)
            } else {
                currentItem.mediaId
            }

        // Check if in playNext stack
        if (playNextStack.any { it.id == trackId }) {
            return TemporaryType.PLAY_NEXT
        }

        // Check if in upNext queue
        if (upNextQueue.any { it.id == trackId }) {
            return TemporaryType.UP_NEXT
        }

        return TemporaryType.NONE
    }

    // Clean up resources
    fun destroy() {
        handler.post {
            androidAutoConnectionDetector?.unregisterCarConnectionReceiver()
            handler.removeCallbacks(progressUpdateRunnable)
            playerListener?.let { player.removeListener(it) }
            playerListener = null
        }
    }

    // Check if Android Auto is connected
    fun isAndroidAutoConnected(): Boolean = isAndroidAutoConnected

    // Set the Android Auto media library structure from JSON
    fun setAndroidAutoMediaLibrary(libraryJson: String) {
        handler.post {
            try {
                val library = MediaLibraryParser.fromJson(libraryJson)
                mediaLibraryManager.setMediaLibrary(library)
                // Notify Android Auto to refresh
                NitroPlayerMediaBrowserService.getInstance()?.onPlaylistsUpdated()
                NitroPlayerLogger.log("TrackPlayerCore", "✅ TrackPlayerCore: Android Auto media library set successfully")
            } catch (e: Exception) {
                NitroPlayerLogger.log("TrackPlayerCore") { "❌ TrackPlayerCore: Error setting media library - ${e.message}" }
                e.printStackTrace()
            }
        }
    }

    // Clear the Android Auto media library
    fun clearAndroidAutoMediaLibrary() {
        handler.post {
            mediaLibraryManager.clear()
            NitroPlayerMediaBrowserService.getInstance()?.onPlaylistsUpdated()
        }
    }

    // Set volume (0-100 range, converted to 0.0-1.0 for ExoPlayer)
    fun setVolume(volume: Double): Boolean =
        if (::player.isInitialized) {
            handler.post {
                // Clamp volume to 0-100 range
                val clampedVolume = volume.coerceIn(0.0, 100.0)
                // Convert to 0.0-1.0 range for ExoPlayer
                val normalizedVolume = (clampedVolume / 100.0).toFloat()
                player.volume = normalizedVolume
                NitroPlayerLogger.log("TrackPlayerCore") { "🔊 TrackPlayerCore: Volume set to $clampedVolume% (normalized: $normalizedVolume)" }
            }
            true
        } else {
            NitroPlayerLogger.log("TrackPlayerCore", "⚠️ TrackPlayerCore: Cannot set volume - player not initialized")
            false
        }

    // Add event listeners
    fun addOnChangeTrackListener(callback: (TrackItem, Reason?) -> Unit) {
        val box = WeakCallbackBox(WeakReference(this), callback)
        onChangeTrackListeners.add(box)
    }

    fun addOnPlaybackStateChangeListener(callback: (TrackPlayerState, Reason?) -> Unit) {
        val box = WeakCallbackBox(WeakReference(this), callback)
        onPlaybackStateChangeListeners.add(box)
    }

    fun addOnSeekListener(callback: (Double, Double) -> Unit) {
        val box = WeakCallbackBox(WeakReference(this), callback)
        onSeekListeners.add(box)
    }

    fun addOnPlaybackProgressChangeListener(callback: (Double, Double, Boolean?) -> Unit) {
        val box = WeakCallbackBox(WeakReference(this), callback)
        onPlaybackProgressChangeListeners.add(box)
    }

    // Notification helpers with auto-cleanup
    private fun notifyTrackChange(
        track: TrackItem,
        reason: Reason?,
    ) {
        val liveCallbacks =
            synchronized(onChangeTrackListeners) {
                onChangeTrackListeners.removeAll { !it.isAlive }
                onChangeTrackListeners.map { it.callback }
            }

        handler.post {
            for (callback in liveCallbacks) {
                try {
                    callback(track, reason)
                } catch (e: Exception) {
                    NitroPlayerLogger.log("TrackPlayerCore") { "⚠️ Error in track change listener: ${e.message}" }
                }
            }
        }
    }

    private fun notifyPlaybackStateChange(
        state: TrackPlayerState,
        reason: Reason?,
    ) {
        val liveCallbacks =
            synchronized(onPlaybackStateChangeListeners) {
                onPlaybackStateChangeListeners.removeAll { !it.isAlive }
                onPlaybackStateChangeListeners.map { it.callback }
            }

        handler.post {
            for (callback in liveCallbacks) {
                try {
                    callback(state, reason)
                } catch (e: Exception) {
                    NitroPlayerLogger.log("TrackPlayerCore") { "⚠️ Error in playback state listener: ${e.message}" }
                }
            }
        }
    }

    private fun notifySeek(
        position: Double,
        duration: Double,
    ) {
        val liveCallbacks =
            synchronized(onSeekListeners) {
                onSeekListeners.removeAll { !it.isAlive }
                onSeekListeners.map { it.callback }
            }

        handler.post {
            for (callback in liveCallbacks) {
                try {
                    callback(position, duration)
                } catch (e: Exception) {
                    NitroPlayerLogger.log("TrackPlayerCore") { "⚠️ Error in seek listener: ${e.message}" }
                }
            }
        }
    }

    private var progressNotifyCounter = 0
    private val progressCallbackScratch = ArrayList<(Double, Double, Boolean?) -> Unit>(4)

    private fun notifyPlaybackProgress(
        position: Double,
        duration: Double,
        isPlaying: Boolean?,
    ) {
        progressCallbackScratch.clear()
        synchronized(onPlaybackProgressChangeListeners) {
            if (++progressNotifyCounter % 10 == 0) {
                onPlaybackProgressChangeListeners.removeAll { !it.isAlive }
            }
            for (box in onPlaybackProgressChangeListeners) {
                if (box.isAlive) progressCallbackScratch.add(box.callback)
            }
        }

        if (progressCallbackScratch.isEmpty()) return

        handler.post {
            for (callback in progressCallbackScratch) {
                try {
                    callback(position, duration, isPlaying)
                } catch (e: Exception) {
                    NitroPlayerLogger.log("TrackPlayerCore") { "⚠️ Error in playback progress listener: ${e.message}" }
                }
            }
        }
    }

    /**
     * Get the actual queue with temporary tracks
     * Returns: [original_before_current] + [current] + [playNext_stack] + [upNext_queue] + [original_after_current]
     */
    fun getActualQueue(): List<TrackItem> {
        // Called from Promise.async background thread
        // Check if we're already on the main thread
        if (android.os.Looper.myLooper() == handler.looper) {
            return getActualQueueInternal()
        }

        // Use CountDownLatch to wait for the result on the main thread
        val latch = CountDownLatch(1)
        var result: List<TrackItem>? = null

        handler.post {
            try {
                result = getActualQueueInternal()
            } finally {
                latch.countDown()
            }
        }

        try {
            // Wait up to 5 seconds for the result
            latch.await(5, TimeUnit.SECONDS)
        } catch (e: InterruptedException) {
            NitroPlayerLogger.log("TrackPlayerCore", "⚠️ TrackPlayerCore: Interrupted while waiting for actual queue")
        }

        return result ?: emptyList()
    }

    private fun getActualQueueInternal(): List<TrackItem> {
        val capacity = currentTracks.size + playNextStack.size + upNextQueue.size
        val queue = ArrayList<TrackItem>(capacity)

        if (!::player.isInitialized) return emptyList()

        val currentIndex = currentTrackIndex
        if (currentIndex < 0) return emptyList()

        // Add tracks before current (original playlist)
        // When a temp track is playing, include the original track at currentTrackIndex
        // (it already played before the temp track started)
        val beforeEnd =
            if (currentTemporaryType != TemporaryType.NONE) {
                minOf(currentIndex + 1, currentTracks.size)
            } else {
                currentIndex
            }
        if (beforeEnd > 0) {
            queue.addAll(currentTracks.subList(0, beforeEnd))
        }

        // Add current track (temp or original)
        getCurrentTrack()?.let { queue.add(it) }

        // Add playNext stack (LIFO - most recently added plays first)
        // Skip index 0 if current track is from playNext (it's already added as current)
        if (currentTemporaryType == TemporaryType.PLAY_NEXT && playNextStack.size > 1) {
            queue.addAll(playNextStack.subList(1, playNextStack.size))
        } else if (currentTemporaryType != TemporaryType.PLAY_NEXT) {
            queue.addAll(playNextStack)
        }

        // Add upNext queue (in order, FIFO)
        // Skip index 0 if current track is from upNext (it's already added as current)
        if (currentTemporaryType == TemporaryType.UP_NEXT && upNextQueue.size > 1) {
            queue.addAll(upNextQueue.subList(1, upNextQueue.size))
        } else if (currentTemporaryType != TemporaryType.UP_NEXT) {
            queue.addAll(upNextQueue)
        }

        // Add remaining original tracks
        if (currentIndex + 1 < currentTracks.size) {
            queue.addAll(currentTracks.subList(currentIndex + 1, currentTracks.size))
        }

        return queue
    }

    // MARK: - Lazy URL Loading Support

    /**
     * Update entire track objects and rebuild queue if needed
     * Skips currently playing track to preserve gapless playback
     */
    fun updateTracks(tracks: List<TrackItem>) {
        handler.post {
            NitroPlayerLogger.log("TrackPlayerCore") { "🔄 updateTracks: ${tracks.size} updates" }

            // Get current track to decide how to handle it
            val currentTrack = getCurrentTrack()
            val currentTrackId = currentTrack?.id

            // Separate the current-track update (if any) from the rest
            val currentTrackUpdate = if (currentTrackId != null) tracks.find { it.id == currentTrackId } else null
            val currentTrackIsEmpty = currentTrack?.url.isNullOrEmpty()

            // Filter out current track and validate
            val safeTracks =
                tracks.filter { track ->
                    when {
                        track.id == currentTrackId && !currentTrackIsEmpty -> {
                            // Has a real URL already — skip to preserve gapless playback
                            NitroPlayerLogger.log("TrackPlayerCore") { "⚠️ Skipping update for currently playing track: ${track.id} (preserves gapless)" }
                            false
                        }

                        track.id == currentTrackId && currentTrackIsEmpty -> {
                            // Empty URL — must not be playing, allow the update
                            NitroPlayerLogger.log("TrackPlayerCore") { "🔄 Updating current track with no URL: ${track.id}" }
                            track.url.isNotEmpty() // only include if the update actually provides a URL
                        }

                        track.url.isEmpty() -> {
                            NitroPlayerLogger.log("TrackPlayerCore") { "⚠️ Skipping track with empty URL: ${track.id}" }
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

            // If the current track was one of the updates (had no URL before), replace its
            // MediaItem in ExoPlayer directly — rebuildQueueFromCurrentPosition skips index 0.
            if (currentTrackUpdate != null && currentTrackIsEmpty && currentTrackUpdate.url.isNotEmpty()) {
                val exoIndex = player.currentMediaItemIndex
                if (exoIndex >= 0) {
                    val playlistId = currentPlaylistId ?: ""
                    val mediaId = if (playlistId.isNotEmpty()) "$playlistId:${currentTrackUpdate.id}" else currentTrackUpdate.id
                    val newMediaItem = currentTrackUpdate.toMediaItem(mediaId)
                    NitroPlayerLogger.log("TrackPlayerCore") { "🔄 Replacing MediaItem at index $exoIndex for current track with resolved URL" }
                    player.replaceMediaItem(exoIndex, newMediaItem)
                    // If ExoPlayer was in an error/idle state waiting for a URI, re-prepare
                    if (player.playbackState == Player.STATE_IDLE) {
                        player.prepare()
                    }
                }
            }

            // Rebuild queue for other updated tracks if current playlist was affected
            if (currentPlaylistId != null && affectedPlaylists.containsKey(currentPlaylistId)) {
                NitroPlayerLogger.log("TrackPlayerCore") { "🔄 Rebuilding queue - ${affectedPlaylists[currentPlaylistId]} tracks updated in current playlist" }

                // PlaylistManager.updateTracks() creates a new Playlist via .copy(tracks = newTracks),
                // so our currentTracks reference still points at the old list with empty URLs.
                // Refresh it now so rebuildQueueFromCurrentPosition builds MediaItems with the
                // resolved URLs, allowing ExoPlayer to pre-buffer the next track for gapless playback.
                val refreshedPlaylist = playlistManager.getPlaylist(currentPlaylistId!!)
                if (refreshedPlaylist != null) {
                    currentTracks = refreshedPlaylist.tracks

                    // Also reconcile any queued items that still reference old TrackItem instances
                    // from this playlist, so that gapless pre-buffering uses tracks with resolved URLs.
                    val updatedTrackById = currentTracks.associateBy { it.id }

                    // Update playNextStack entries to point at the refreshed TrackItem objects.
                    playNextStack.forEachIndexed { index, track ->
                        val updated = updatedTrackById[track.id]
                        if (updated != null && updated !== track) {
                            playNextStack[index] = updated
                        }
                    }

                    // Update upNextQueue entries to point at the refreshed TrackItem objects.
                    upNextQueue.forEachIndexed { index, track ->
                        val updated = updatedTrackById[track.id]
                        if (updated != null && updated !== track) {
                            upNextQueue[index] = updated
                        }
                    }
                }

                // This method preserves current item and gapless buffering
                rebuildQueueFromCurrentPosition()

                NitroPlayerLogger.log("TrackPlayerCore", "✅ Queue rebuilt, gapless playback preserved")
            }

            NitroPlayerLogger.log("TrackPlayerCore") { "✅ Track updates complete - ${affectedPlaylists.size} playlists affected" }
        }
    }

    /**
     * Get tracks by IDs from all playlists
     */
    fun getTracksById(trackIds: List<String>): List<TrackItem> {
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
    fun getTracksNeedingUrls(): List<TrackItem> {
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

    private fun getTracksNeedingUrlsInternal(): List<TrackItem> {
        if (currentPlaylistId == null) return emptyList()

        val playlist = playlistManager.getPlaylist(currentPlaylistId!!)
        return playlist?.tracks?.filter { it.url.isEmpty() } ?: emptyList()
    }

    /**
     * Get next N tracks from current position
     */
    fun getNextTracks(count: Int): List<TrackItem> {
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

    private fun getNextTracksInternal(count: Int): List<TrackItem> {
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
    fun getCurrentTrackIndex(): Int {
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
     * Callback interface for tracks needing update
     */
    fun interface OnTracksNeedUpdateListener {
        fun onTracksNeedUpdate(
            tracks: List<TrackItem>,
            lookahead: Int,
        )
    }

    // Add to class properties
    private val onTracksNeedUpdateListeners = mutableListOf<OnTracksNeedUpdateListener>()

    /**
     * Register listener for when tracks need update
     */
    fun addOnTracksNeedUpdateListener(listener: OnTracksNeedUpdateListener) {
        handler.post {
            onTracksNeedUpdateListeners.add(listener)
        }
    }

    /**
     * Remove listener
     */
    fun removeOnTracksNeedUpdateListener(listener: OnTracksNeedUpdateListener) {
        handler.post {
            onTracksNeedUpdateListeners.removeAll { it == listener }
        }
    }

    /**
     * Notify listeners that tracks need updating
     * Called internally when moving to next track and upcoming tracks have empty URLs
     */
    private fun notifyTracksNeedUpdate(
        tracks: List<TrackItem>,
        lookahead: Int,
    ) {
        val liveCallbacks =
            synchronized(onTracksNeedUpdateListeners) {
                onTracksNeedUpdateListeners.toList()
            }

        handler.post {
            for (callback in liveCallbacks) {
                try {
                    callback.onTracksNeedUpdate(tracks, lookahead)
                } catch (e: Exception) {
                    NitroPlayerLogger.log("TrackPlayerCore") { "⚠️ Error in onTracksNeedUpdate listener: ${e.message}" }
                }
            }
        }
    }

    /**
     * Check if upcoming tracks need URLs and notify listeners
     * Call this in onMediaItemTransition or after skipTo operations
     */
    private fun checkUpcomingTracksForUrls(lookahead: Int = 5) {
        val upcomingTracks = if (currentTrackIndex < 0) {
            // Playback hasn't started yet - check first N tracks from the loaded playlist
            currentTracks.take(lookahead)
        } else {
            // Playback is active - check upcoming tracks
            getNextTracksInternal(lookahead)
        }

        // Always include the current track if it has no URL — it can't play without one
        val currentTrack = getCurrentTrack()
        val currentNeedsUrl = currentTrack != null && currentTrack.url.isEmpty()
        val candidateTracks = if (currentNeedsUrl) listOf(currentTrack!!) + upcomingTracks else upcomingTracks

        val tracksNeedingUrls = candidateTracks.filter { it.url.isEmpty() }

        if (tracksNeedingUrls.isNotEmpty()) {
            NitroPlayerLogger.log("TrackPlayerCore") { "⚠️ ${tracksNeedingUrls.size} upcoming tracks need URLs" }
            notifyTracksNeedUpdate(tracksNeedingUrls, lookahead)
        }
    }

    fun setPlayBackSpeed(speed: Double) {
        if (android.os.Looper.myLooper() == handler.looper) {
            setPlayBackSpeedInternal(speed)
            return
        }
        val latch = CountDownLatch(1)
        handler.post {
            try {
                setPlayBackSpeedInternal(speed)
            } finally {
                latch.countDown()
            }
        }
        try {
            latch.await(5, TimeUnit.SECONDS)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    private fun setPlayBackSpeedInternal(speed: Double) {
        if (::player.isInitialized) {
            player.setPlaybackSpeed(speed.toFloat())
        }
    }

    fun getPlayBackSpeed(): Double {
        if (android.os.Looper.myLooper() == handler.looper) {
            return getPlayBackSpeedInternal()
        }
        val latch = CountDownLatch(1)
        var result = 1.0
        handler.post {
            try {
                result = getPlayBackSpeedInternal()
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

    private fun getPlayBackSpeedInternal(): Double =
        if (::player.isInitialized) {
            player.playbackParameters.speed.toDouble()
        } else {
            1.0
        }
}
