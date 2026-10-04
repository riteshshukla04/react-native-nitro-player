@file:Suppress("ktlint:standard:filename")

package com.margelo.nitro.nitroplayer.media

import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat
import android.support.v4.media.session.MediaSessionCompat
import androidx.media.MediaBrowserServiceCompat
import androidx.media.utils.MediaConstants
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.core.onAndroidAutoBrowserConnected
import com.margelo.nitro.nitroplayer.playlist.Playlist
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class NitroPlayerMediaBrowserService : MediaBrowserServiceCompat() {
    companion object {
        private const val ROOT_ID = "root"
        private const val PLAYLIST_PREFIX = "playlist_"
        private const val ANDROID_AUTO_PACKAGE = "com.google.android.projection.gearhead"
        private const val PREFS_NAME = "NitroPlayerAndroidAuto"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_SEARCH = "search"

        var isAndroidAutoConnected: Boolean = false

        @Volatile
        private var instance: NitroPlayerMediaBrowserService? = null

        fun getInstance(): NitroPlayerMediaBrowserService? = instance

        // Persisted so a cold start from the car, before JS runs configure, still serves the library
        fun setAndroidAutoEnabled(
            context: Context,
            enabled: Boolean,
        ) {
            prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
            instance?.onPlaylistsUpdated()
        }

        // Persisted too: the car reads the root (and hides search for the whole connection) before JS registers a handler
        fun setSearchSupported(
            context: Context,
            supported: Boolean,
        ) {
            prefs(context).edit().putBoolean(KEY_SEARCH, supported).apply()
        }

        private fun prefs(context: Context) = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var mediaLibraryManager: MediaLibraryManager
    private lateinit var core: TrackPlayerCore

    private val isAndroidAutoEnabled: Boolean
        get() = prefs(this).getBoolean(KEY_ENABLED, false)

    override fun onCreate() {
        super.onCreate()

        instance = this
        mediaLibraryManager = MediaLibraryManager.getInstance(applicationContext)
        mediaLibraryManager.onLateChildren = { parentId -> notifyChildrenChanged(parentId) }

        // A cold start has no session yet; the connection stays pending until the token is set
        core = TrackPlayerCore.getInstance(applicationContext)
        serviceScope.launch {
            val token = core.withPlayerContext { core.mediaSessionManager?.mediaSession?.platformToken } ?: return@launch
            if (sessionToken == null) sessionToken = MediaSessionCompat.Token.fromToken(token)
            NitroPlayerLogger.log("MediaBrowserService", "🎵 NitroPlayerMediaBrowserService: MediaSession token set")
        }

        NitroPlayerLogger.log("MediaBrowserService", "🚀 NitroPlayerMediaBrowserService: Service created")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        mediaLibraryManager.onLateChildren = null
        serviceScope.cancel()
        NitroPlayerLogger.log("MediaBrowserService", "🛑 NitroPlayerMediaBrowserService: Service destroyed")
    }

    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: Bundle?,
    ): BrowserRoot {
        NitroPlayerLogger.log("MediaBrowserService", "📂 NitroPlayerMediaBrowserService: onGetRoot called from $clientPackageName")

        if (clientPackageName == ANDROID_AUTO_PACKAGE) core.onAndroidAutoBrowserConnected()

        // Always the real root: enabling later only has to refresh it, not reconnect the car
        val extras =
            Bundle().apply {
                putInt(
                    MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_BROWSABLE,
                    MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM,
                )
                putInt(
                    MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_PLAYABLE,
                    MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_LIST_ITEM,
                )
                putBoolean(
                    MediaConstants.BROWSER_SERVICE_EXTRAS_KEY_SEARCH_SUPPORTED,
                    prefs(this@NitroPlayerMediaBrowserService).getBoolean(KEY_SEARCH, false),
                )
            }
        return BrowserRoot(ROOT_ID, extras)
    }

    override fun onLoadChildren(
        parentId: String,
        result: Result<MutableList<MediaBrowserCompat.MediaItem>>,
    ) {
        NitroPlayerLogger.log("MediaBrowserService", "📂 NitroPlayerMediaBrowserService: onLoadChildren called for parentId: $parentId")
        startJsOnDemand()

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
                        if (mediaLibraryManager.getMediaLibrary() == null) mediaLibraryManager.awaitFirstPublish(MediaLibraryManager.FIRST_PUBLISH_WAIT_MS)
                        val library = mediaLibraryManager.getMediaLibrary()
                        val rootItems = library?.rootItems?.filter { it.hasContent() }.orEmpty()

                        if (library == null || rootItems.isEmpty()) {
                            // Fallback: show playlists if no media library is set
                            NitroPlayerLogger.log("MediaBrowserService", "⚠️ NitroPlayerMediaBrowserService: No media library set, using fallback playlists")
                            val mediaItems = loadFallbackPlaylists()
                            result.sendResult(mediaItems)
                            return@launch
                        }

                        val mediaItems = rootItems.map { convertToMediaBrowserItem(it, library.layoutType) }.toMutableList()

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
                        val playlist = core.playlistManager.getPlaylist(playlistId)

                        if (playlist == null) {
                            NitroPlayerLogger.log("MediaBrowserService", "⚠️ NitroPlayerMediaBrowserService: Playlist '$playlistId' not found")
                            result.sendResult(mutableListOf())
                            return@launch
                        }

                        val mediaItems = mutableListOf<MediaBrowserCompat.MediaItem>()

                        val seen = mutableSetOf<String>()
                        playlist.tracks.forEachIndexed { index, track ->
                            // A repeated track gets its own id so picking that row plays that occurrence
                            val trackRef = if (seen.add(track.id)) track.id else "${track.id}#$index"
                            val extras =
                                Bundle().apply {
                                    putString("playlistId", playlistId)
                                    putInt("trackIndex", index)
                                    putString("trackId", track.id)
                                }

                            val description =
                                MediaDescriptionCompat
                                    .Builder()
                                    .setMediaId("$playlistId:$trackRef")
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

            else -> {
                // Handle custom folder IDs from media library
                result.detach()

                serviceScope.launch {
                    try {
                        if (mediaLibraryManager.getMediaLibrary() == null) mediaLibraryManager.awaitFirstPublish(MediaLibraryManager.FIRST_PUBLISH_WAIT_MS)
                        val children = mediaLibraryManager.getChildrenById(parentId) ?: mediaLibraryManager.loadChildren(parentId)

                        if (children == null) {
                            NitroPlayerLogger.log("MediaBrowserService", "⚠️ NitroPlayerMediaBrowserService: No children found for parentId: $parentId")
                            result.sendResult(mutableListOf())
                            return@launch
                        }

                        val library = mediaLibraryManager.getMediaLibrary()
                        val defaultLayout = library?.layoutType ?: LayoutType.LIST
                        val mediaItems =
                            children
                                .filter { it.hasContent() }
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

    override fun onSearch(
        query: String,
        extras: Bundle?,
        result: Result<MutableList<MediaBrowserCompat.MediaItem>>,
    ) {
        startJsOnDemand()
        result.detach()
        serviceScope.launch {
            val items = mediaLibraryManager.search(query).orEmpty().filter { it.hasContent() }
            val layout = mediaLibraryManager.getMediaLibrary()?.layoutType ?: LayoutType.LIST
            result.sendResult(items.map { convertToMediaBrowserItem(it, layout) }.toMutableList())
        }
    }

    // The car binds every media app on connect; JS starts only once content is asked for, never for SystemUI's recent-media probe
    private fun startJsOnDemand() {
        if (browserRootHints?.getBoolean(BrowserRoot.EXTRA_RECENT) != true) core.startJsRuntimeIfNeeded()
    }

    // Folders a client has open keep their stale children unless refreshed too
    fun onLibraryUpdated(folderIds: List<String>) {
        onPlaylistsUpdated()
        folderIds.distinct().forEach { notifyChildrenChanged(it) }
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

    // Apps may delete the playlists a published library points at; hide those, but keep empty ones so the user still finds them
    private fun MediaItem.hasContent(): Boolean {
        if (mediaType != MediaType.PLAYLIST || playlistId == null) return true
        return core.playlistManager.getPlaylist(playlistId) != null
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
                item.groupTitle?.let { putString(MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_GROUP_TITLE, it) }
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
        // Apps frequently create internal queue playlists named with raw UUIDs
        // (e.g. `PlayerQueue.createPlaylist(uuid.v4())`). Showing those in
        // Android Auto surfaces ugly UUID strings as titles. Filter:
        //   - empty playlists (no tracks)
        //   - playlists whose name is a bare UUID
        //   - duplicate names (keep latest)
        // and prefer surfacing the currently-loaded playlist first so the user
        // always has access to "what's playing now" while the JS side hasn't
        // published a media library yet.
        val rawPlaylists = core.getAllPlaylists()
        val currentId = core.getCurrentPlaylistId()
        val uuidRegex = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

        val dedupedByName = linkedMapOf<String, com.margelo.nitro.nitroplayer.playlist.Playlist>()
        rawPlaylists.forEach { p ->
            if (p.tracks.isEmpty()) return@forEach
            // Always keep the currently-playing playlist regardless of name shape.
            val isCurrent = p.id == currentId
            if (!isCurrent && uuidRegex.matches(p.name)) return@forEach
            dedupedByName[p.name] = p
        }
        val playlists =
            dedupedByName.values.sortedByDescending { it.id == currentId }
        val mediaItems = mutableListOf<MediaBrowserCompat.MediaItem>()

        playlists.forEach { playlist ->
            val extras =
                Bundle().apply {
                    putInt(
                        MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_BROWSABLE,
                        MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM,
                    )
                }

            val displayTitle =
                if (uuidRegex.matches(playlist.name)) "Now Playing" else playlist.name
            val description =
                MediaDescriptionCompat
                    .Builder()
                    .setMediaId("$PLAYLIST_PREFIX${playlist.id}")
                    .setTitle(displayTitle)
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
