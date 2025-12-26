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
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.playlist.Playlist
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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

    override fun onCreate() {
        super.onCreate()

        instance = this

        // Use the existing MediaSession from MediaSessionManager
        // This ensures the session is already connected to the ExoPlayer
        try {
            val session = mediaSessionManager?.mediaSession
            if (session != null) {
                // Convert Media3 MediaSession to MediaSessionCompat for MediaBrowserService
                sessionToken = session.sessionCompatToken
                println("🎵 NitroPlayerMediaBrowserService: MediaSession token set successfully")
            } else {
                println("⚠️ NitroPlayerMediaBrowserService: MediaSession not available yet")
            }
        } catch (e: Exception) {
            println("❌ NitroPlayerMediaBrowserService: Error setting session token - ${e.message}")
            e.printStackTrace()
        }

        println("🚀 NitroPlayerMediaBrowserService: Service created")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        serviceScope.cancel()
        println("🛑 NitroPlayerMediaBrowserService: Service destroyed")
    }

    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: Bundle?,
    ): BrowserRoot? {
        println("📂 NitroPlayerMediaBrowserService: onGetRoot called from $clientPackageName")

        // Check if Android Auto is enabled
        if (!isAndroidAutoEnabled) {
            println("⚠️ NitroPlayerMediaBrowserService: Android Auto not enabled")
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
        println("✅ NitroPlayerMediaBrowserService: Allowing connection from $clientPackageName with grid layout")
        return BrowserRoot(ROOT_ID, extras)
    }

    override fun onLoadChildren(
        parentId: String,
        result: Result<MutableList<MediaBrowserCompat.MediaItem>>,
    ) {
        println("📂 NitroPlayerMediaBrowserService: onLoadChildren called for parentId: $parentId")

        if (!isAndroidAutoEnabled) {
            println("⚠️ NitroPlayerMediaBrowserService: Android Auto not enabled, returning empty")
            result.sendResult(mutableListOf())
            return
        }

        when {
            parentId == ROOT_ID -> {
                // Return playlists as a grid
                result.detach()

                serviceScope.launch {
                    try {
                        val playlists = trackPlayerCore?.getAllPlaylists() ?: emptyList()
                        val mediaItems = mutableListOf<MediaBrowserCompat.MediaItem>()

                        playlists.forEach { playlist ->
                            val extras =
                                Bundle().apply {
                                    // Enable grid layout for playlists
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

                        println("✅ NitroPlayerMediaBrowserService: Returning ${mediaItems.size} playlists as grid")
                        result.sendResult(mediaItems)
                    } catch (e: Exception) {
                        println("❌ NitroPlayerMediaBrowserService: Error loading playlists - ${e.message}")
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
                        val core = trackPlayerCore
                        if (core != null) {
                            val playlist = core.getPlaylistManager().getPlaylist(playlistId)

                            if (playlist == null) {
                                println("⚠️ NitroPlayerMediaBrowserService: Playlist '$playlistId' not found")
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

                                // Use format: "playlistId:trackId" for mediaId
                                // This allows us to identify both playlist and track
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

                            println(
                                "✅ NitroPlayerMediaBrowserService: Returning ${mediaItems.size} tracks from playlist '$playlistId'",
                            )
                            result.sendResult(mediaItems)
                        } else {
                            result.sendResult(mutableListOf())
                        }
                    } catch (e: Exception) {
                        println("❌ NitroPlayerMediaBrowserService: Error loading playlist tracks - ${e.message}")
                        e.printStackTrace()
                        result.sendResult(mutableListOf())
                    }
                }
            }

            parentId == EMPTY_ROOT_ID -> {
                result.sendResult(mutableListOf())
            }

            else -> {
                println("⚠️ NitroPlayerMediaBrowserService: Unknown parentId: $parentId")
                result.sendResult(mutableListOf())
            }
        }
    }

    fun onPlaylistsUpdated() {
        try {
            notifyChildrenChanged(ROOT_ID)
            println("📢 NitroPlayerMediaBrowserService: Notified Android Auto of playlist update")
        } catch (e: Exception) {
            println("⚠️ NitroPlayerMediaBrowserService: Error notifying children changed: ${e.message}")
        }
    }

    fun onPlaylistUpdated(playlistId: String) {
        try {
            notifyChildrenChanged("$PLAYLIST_PREFIX$playlistId")
            println("📢 NitroPlayerMediaBrowserService: Notified Android Auto of playlist '$playlistId' update")
        } catch (e: Exception) {
            println("⚠️ NitroPlayerMediaBrowserService: Error notifying playlist changed: ${e.message}")
        }
    }
}
