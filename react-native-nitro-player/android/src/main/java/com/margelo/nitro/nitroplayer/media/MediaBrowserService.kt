@file:Suppress("ktlint:standard:filename")

package com.margelo.nitro.nitroplayer.media

import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat
import androidx.media.MediaBrowserServiceCompat
import androidx.media.utils.MediaConstants
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.playlist.Playlist
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class NitroPlayerMediaBrowserService : MediaBrowserServiceCompat() {
    companion object {
        private const val ROOT_ID = "root"
        private const val EMPTY_ROOT_ID = "empty_root"
        private const val PLAYLIST_PREFIX = "playlist_"

        var trackPlayerCore: TrackPlayerCore? = null
        var mediaSessionManager: MediaSessionManager? = null
        var isAndroidAutoEnabled: Boolean = false
        var isAndroidAutoConnected: Boolean = false

        @Volatile
        private var instance: NitroPlayerMediaBrowserService? = null

        fun getInstance(): NitroPlayerMediaBrowserService? = instance
    }

    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var mediaLibraryManager: MediaLibraryManager

    override fun onCreate() {
        super.onCreate()

        instance = this
        mediaLibraryManager = MediaLibraryManager.getInstance(applicationContext)

        // Use the existing MediaSession from MediaSessionManager
        // This ensures the session is already connected to the ExoPlayer
        try {
            val session = mediaSessionManager?.mediaSession
            if (session != null) {
                // Convert Media3 MediaSession to MediaSessionCompat for MediaBrowserService
                sessionToken =
                    android.support.v4.media.session.MediaSessionCompat.Token
                        .fromToken(session.platformToken)
                NitroPlayerLogger.log("MediaBrowserService", "🎵 NitroPlayerMediaBrowserService: MediaSession token set successfully")
            } else {
                NitroPlayerLogger.log("MediaBrowserService", "⚠️ NitroPlayerMediaBrowserService: MediaSession not available yet")
            }
        } catch (e: Exception) {
            NitroPlayerLogger.log("MediaBrowserService", "❌ NitroPlayerMediaBrowserService: Error setting session token - ${e.message}")
            e.printStackTrace()
        }

        NitroPlayerLogger.log("MediaBrowserService", "🚀 NitroPlayerMediaBrowserService: Service created")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        serviceScope.cancel()
        NitroPlayerLogger.log("MediaBrowserService", "🛑 NitroPlayerMediaBrowserService: Service destroyed")
    }

    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: Bundle?,
    ): BrowserRoot? {
        NitroPlayerLogger.log("MediaBrowserService", "📂 NitroPlayerMediaBrowserService: onGetRoot called from $clientPackageName")

        // Check if Android Auto is enabled
        if (!isAndroidAutoEnabled) {
            NitroPlayerLogger.log("MediaBrowserService", "⚠️ NitroPlayerMediaBrowserService: Android Auto not enabled")
            return BrowserRoot(EMPTY_ROOT_ID, null)
        }

        // Allow Android Auto and other media browsers to connect
        // Enable grid layout for playlists at root level
        val extras =
            Bundle().apply {
                putInt(
                    MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_BROWSABLE,
                    MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM,
                )
            }
        NitroPlayerLogger.log("MediaBrowserService", "✅ NitroPlayerMediaBrowserService: Allowing connection from $clientPackageName with grid layout")
        return BrowserRoot(ROOT_ID, extras)
    }

    override fun onLoadChildren(
        parentId: String,
        result: Result<MutableList<MediaBrowserCompat.MediaItem>>,
    ) {
        NitroPlayerLogger.log("MediaBrowserService", "📂 NitroPlayerMediaBrowserService: onLoadChildren called for parentId: $parentId")

        if (!isAndroidAutoEnabled) {
            NitroPlayerLogger.log("MediaBrowserService", "⚠️ NitroPlayerMediaBrowserService: Android Auto not enabled, returning empty")
            result.sendResult(mutableListOf())
            return
        }

        when {
            parentId == ROOT_ID -> {
                // Return root items from media library
                result.detach()

                serviceScope.launch {
                    try {
                        val library = mediaLibraryManager.getMediaLibrary()

                        if (library == null) {
                            // Fallback: show playlists if no media library is set
                            NitroPlayerLogger.log("MediaBrowserService", "⚠️ NitroPlayerMediaBrowserService: No media library set, using fallback playlists")
                            val mediaItems = loadFallbackPlaylists()
                            result.sendResult(mediaItems)
                            return@launch
                        }

                        val mediaItems = mutableListOf<MediaBrowserCompat.MediaItem>()

                        library.rootItems.forEach { item ->
                            mediaItems.add(convertToMediaBrowserItem(item, library.layoutType))
                        }

                        NitroPlayerLogger.log("MediaBrowserService", "✅ NitroPlayerMediaBrowserService: Returning ${mediaItems.size} root items")
                        result.sendResult(mediaItems)
                    } catch (e: Exception) {
                        NitroPlayerLogger.log("MediaBrowserService", "❌ NitroPlayerMediaBrowserService: Error loading root items - ${e.message}")
                        e.printStackTrace()
                        result.sendResult(mutableListOf())
                    }
                }
            }

            parentId.startsWith(PLAYLIST_PREFIX) -> {
                // Return tracks in a specific playlist
                result.detach()

                val playlistId = parentId.removePrefix(PLAYLIST_PREFIX)

                serviceScope.launch {
                    try {
                        val playlist = trackPlayerCore?.getPlaylistManager()?.getPlaylist(playlistId)

                        if (playlist == null) {
                            NitroPlayerLogger.log("MediaBrowserService", "⚠️ NitroPlayerMediaBrowserService: Playlist '$playlistId' not found")
                            result.sendResult(mutableListOf())
                            return@launch
                        }

                        val mediaItems = mutableListOf<MediaBrowserCompat.MediaItem>()

                        playlist.tracks.forEachIndexed { index, track ->
                            val extras =
                                Bundle().apply {
                                    putString("playlistId", playlistId)
                                    putInt("trackIndex", index)
                                    putString("trackId", track.id)
                                }

                            val description =
                                MediaDescriptionCompat
                                    .Builder()
                                    .setMediaId("$playlistId:${track.id}")
                                    .setTitle(track.title)
                                    .setSubtitle(track.artist)
                                    .setDescription(track.album)
                                    .setIconUri(track.artwork?.asSecondOrNull()?.let { Uri.parse(it) })
                                    .setExtras(extras)
                                    .build()

                            mediaItems.add(
                                MediaBrowserCompat.MediaItem(
                                    description,
                                    MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
                                ),
                            )
                        }

                        NitroPlayerLogger.log("MediaBrowserService", "✅ NitroPlayerMediaBrowserService: Returning ${mediaItems.size} tracks from playlist '$playlistId'")
                        result.sendResult(mediaItems)
                    } catch (e: Exception) {
                        NitroPlayerLogger.log("MediaBrowserService", "❌ NitroPlayerMediaBrowserService: Error loading playlist tracks - ${e.message}")
                        e.printStackTrace()
                        result.sendResult(mutableListOf())
                    }
                }
            }

            parentId == EMPTY_ROOT_ID -> {
                result.sendResult(mutableListOf())
            }

            else -> {
                // Handle custom folder IDs from media library
                result.detach()

                serviceScope.launch {
                    try {
                        val children = mediaLibraryManager.getChildrenById(parentId)

                        if (children == null) {
                            NitroPlayerLogger.log("MediaBrowserService", "⚠️ NitroPlayerMediaBrowserService: No children found for parentId: $parentId")
                            result.sendResult(mutableListOf())
                            return@launch
                        }

                        val library = mediaLibraryManager.getMediaLibrary()
                        val defaultLayout = library?.layoutType ?: LayoutType.LIST
                        val mediaItems =
                            children
                                .map { item ->
                                    convertToMediaBrowserItem(item, defaultLayout)
                                }.toMutableList()

                        NitroPlayerLogger.log("MediaBrowserService", "✅ NitroPlayerMediaBrowserService: Returning ${mediaItems.size} items for parentId: $parentId")
                        result.sendResult(mediaItems)
                    } catch (e: Exception) {
                        NitroPlayerLogger.log("MediaBrowserService", "❌ NitroPlayerMediaBrowserService: Error loading children - ${e.message}")
                        e.printStackTrace()
                        result.sendResult(mutableListOf())
                    }
                }
            }
        }
    }

    fun onPlaylistsUpdated() {
        try {
            notifyChildrenChanged(ROOT_ID)
            NitroPlayerLogger.log("MediaBrowserService", "📢 NitroPlayerMediaBrowserService: Notified Android Auto of playlist update")
        } catch (e: Exception) {
            NitroPlayerLogger.log("MediaBrowserService", "⚠️ NitroPlayerMediaBrowserService: Error notifying children changed: ${e.message}")
        }
    }

    fun onPlaylistUpdated(playlistId: String) {
        try {
            notifyChildrenChanged("$PLAYLIST_PREFIX$playlistId")
            NitroPlayerLogger.log("MediaBrowserService", "📢 NitroPlayerMediaBrowserService: Notified Android Auto of playlist '$playlistId' update")
        } catch (e: Exception) {
            NitroPlayerLogger.log("MediaBrowserService", "⚠️ NitroPlayerMediaBrowserService: Error notifying playlist changed: ${e.message}")
        }
    }

    /**
     * Convert MediaLibrary MediaItem to Android Auto MediaBrowserCompat.MediaItem
     */
    private fun convertToMediaBrowserItem(
        item: MediaItem,
        defaultLayout: LayoutType,
    ): MediaBrowserCompat.MediaItem {
        val layoutType = item.layoutType ?: defaultLayout
        val contentStyle =
            when (layoutType) {
                LayoutType.GRID -> MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM
                LayoutType.LIST -> MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM
            }

        val extras =
            Bundle().apply {
                putInt(
                    MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_BROWSABLE,
                    contentStyle,
                )
            }

        // Determine the media ID based on item type
        val mediaId =
            when (item.mediaType) {
                MediaType.PLAYLIST -> {
                    // For playlist items, use the playlist reference
                    if (item.playlistId != null) {
                        "$PLAYLIST_PREFIX${item.playlistId}"
                    } else {
                        item.id
                    }
                }

                else -> {
                    item.id
                }
            }

        val description =
            MediaDescriptionCompat
                .Builder()
                .setMediaId(mediaId)
                .setTitle(item.title)
                .setSubtitle(item.subtitle)
                .setIconUri(item.iconUrl?.let { Uri.parse(it) })
                .setExtras(extras)
                .build()

        // Determine if browsable or playable
        val flag =
            if (item.isPlayable && item.mediaType == MediaType.AUDIO) {
                MediaBrowserCompat.MediaItem.FLAG_PLAYABLE
            } else {
                MediaBrowserCompat.MediaItem.FLAG_BROWSABLE
            }

        return MediaBrowserCompat.MediaItem(description, flag)
    }

    /**
     * Fallback: Load playlists when no media library is set
     */
    private suspend fun loadFallbackPlaylists(): MutableList<MediaBrowserCompat.MediaItem> {
        val playlists = trackPlayerCore?.getAllPlaylists() ?: emptyList()
        val mediaItems = mutableListOf<MediaBrowserCompat.MediaItem>()

        playlists.forEach { playlist ->
            val extras =
                Bundle().apply {
                    putInt(
                        MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_BROWSABLE,
                        MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM,
                    )
                }

            val description =
                MediaDescriptionCompat
                    .Builder()
                    .setMediaId("$PLAYLIST_PREFIX${playlist.id}")
                    .setTitle(playlist.name)
                    .setSubtitle(playlist.description ?: "${playlist.tracks.size} tracks")
                    .setIconUri(playlist.artwork?.let { Uri.parse(it) })
                    .setExtras(extras)
                    .build()

            mediaItems.add(
                MediaBrowserCompat.MediaItem(
                    description,
                    MediaBrowserCompat.MediaItem.FLAG_BROWSABLE,
                ),
            )
        }

        NitroPlayerLogger.log("MediaBrowserService", "✅ NitroPlayerMediaBrowserService: Loaded ${mediaItems.size} playlists as fallback")
        return mediaItems
    }
}
