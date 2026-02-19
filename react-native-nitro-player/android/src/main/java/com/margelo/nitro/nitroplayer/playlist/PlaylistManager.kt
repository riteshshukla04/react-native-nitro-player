package com.margelo.nitro.nitroplayer.playlist

import android.content.Context
import android.content.SharedPreferences
import com.margelo.nitro.core.AnyMap
import com.margelo.nitro.core.NullType
import com.margelo.nitro.nitroplayer.QueueOperation
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.Variant_NullType_String
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Manages multiple playlists using ExoPlayer's native playlist functionality
 * Based on: https://developer.android.com/media/media3/exoplayer/playlists
 */
class PlaylistManager private constructor(
    private val context: Context,
) {
    private val playlists: MutableMap<String, Playlist> = mutableMapOf()
    private val listeners = CopyOnWriteArrayList<(List<Playlist>, QueueOperation?) -> Unit>()
    private val playlistListeners = mutableMapOf<String, CopyOnWriteArrayList<(Playlist, QueueOperation?) -> Unit>>()
    private var currentPlaylistId: String? = null

    private val sharedPreferences: SharedPreferences =
        context.getSharedPreferences("NitroPlayerPlaylists", Context.MODE_PRIVATE)

    private val saveHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val saveRunnable = Runnable { savePlaylistsToPreferences() }

    private fun scheduleSave() {
        saveHandler.removeCallbacks(saveRunnable)
        saveHandler.postDelayed(saveRunnable, 300)
    }

    companion object {
        @Volatile
        @Suppress("ktlint:standard:property-naming")
        private var INSTANCE: PlaylistManager? = null

        @JvmStatic
        fun getInstance(context: Context): PlaylistManager =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: PlaylistManager(context.applicationContext).also { INSTANCE = it }
            }
    }

    init {
        // Don't load from preferences on init - only load when Android Auto needs it
    }

    /**
     * Create a new playlist
     */
    fun createPlaylist(
        name: String,
        description: String? = null,
        artwork: String? = null,
    ): String {
        val id = UUID.randomUUID().toString()
        val playlist = Playlist(id, name, description, artwork)

        synchronized(playlists) {
            playlists[id] = playlist
        }

        // Only cache for Android Auto if connected
        if (NitroPlayerMediaBrowserService.isAndroidAutoConnected) {
            scheduleSave()
        }
        notifyPlaylistsChanged(QueueOperation.ADD)
        NitroPlayerMediaBrowserService.getInstance()?.onPlaylistsUpdated()

        return id
    }

    /**
     * Delete a playlist
     */
    fun deletePlaylist(playlistId: String): Boolean {
        val removed =
            synchronized(playlists) {
                playlists.remove(playlistId)
            }

        if (removed != null) {
            if (currentPlaylistId == playlistId) {
                currentPlaylistId = null
            }
            playlistListeners.remove(playlistId)
            // Only cache for Android Auto if connected
            if (NitroPlayerMediaBrowserService.isAndroidAutoConnected) {
                scheduleSave()
            }
            notifyPlaylistsChanged(QueueOperation.REMOVE)
            NitroPlayerMediaBrowserService.getInstance()?.onPlaylistsUpdated()
            return true
        }

        return false
    }

    /**
     * Update playlist metadata
     */
    fun updatePlaylist(
        playlistId: String,
        name: String? = null,
        description: String? = null,
        artwork: String? = null,
    ): Boolean {
        val playlist =
            synchronized(playlists) {
                playlists[playlistId]
            } ?: return false

        synchronized(playlists) {
            playlists[playlistId] =
                playlist.copy(
                    name = name ?: playlist.name,
                    description = description ?: playlist.description,
                    artwork = artwork ?: playlist.artwork,
                )
        }

        // Only cache for Android Auto if connected
        if (NitroPlayerMediaBrowserService.isAndroidAutoConnected) {
            scheduleSave()
        }
        notifyPlaylistChanged(playlistId, QueueOperation.UPDATE)
        notifyPlaylistsChanged(QueueOperation.UPDATE)
        NitroPlayerMediaBrowserService.getInstance()?.onPlaylistsUpdated()

        return true
    }

    /**
     * Get a playlist by ID
     */
    fun getPlaylist(playlistId: String): Playlist? =
        synchronized(playlists) {
            playlists[playlistId]
        }

    /**
     * Get all playlists
     */
    fun getAllPlaylists(): List<Playlist> =
        synchronized(playlists) {
            playlists.values.toList()
        }

    /**
     * Add a track to a playlist
     */
    fun addTrackToPlaylist(
        playlistId: String,
        track: TrackItem,
        index: Int? = null,
    ): Boolean {
        val playlist =
            synchronized(playlists) {
                playlists[playlistId]
            } ?: return false

        synchronized(playlists) {
            val tracks = playlist.tracks.toMutableList()
            if (index != null && index >= 0 && index <= tracks.size) {
                tracks.add(index, track)
            } else {
                tracks.add(track)
            }
            playlists[playlistId] = playlist.copy(tracks = tracks)
        }

        // Only cache for Android Auto if connected
        if (NitroPlayerMediaBrowserService.isAndroidAutoConnected) {
            scheduleSave()
        }
        notifyPlaylistChanged(playlistId, QueueOperation.ADD)
        NitroPlayerMediaBrowserService.getInstance()?.onPlaylistUpdated(playlistId)

        // Update ExoPlayer if this is the current playlist
        if (currentPlaylistId == playlistId) {
            TrackPlayerCore.getInstance(context)?.updatePlaylist(playlistId)
        }

        return true
    }

    /**
     * Add multiple tracks to a playlist at once
     */
    fun addTracksToPlaylist(
        playlistId: String,
        tracks: List<TrackItem>,
        index: Int? = null,
    ): Boolean {
        val playlist =
            synchronized(playlists) {
                playlists[playlistId]
            } ?: return false

        synchronized(playlists) {
            val currentTracks = playlist.tracks.toMutableList()
            if (index != null && index >= 0 && index <= currentTracks.size) {
                currentTracks.addAll(index, tracks)
            } else {
                currentTracks.addAll(tracks)
            }
            playlists[playlistId] = playlist.copy(tracks = currentTracks)
        }

        // Only cache for Android Auto if connected
        if (NitroPlayerMediaBrowserService.isAndroidAutoConnected) {
            scheduleSave()
        }
        notifyPlaylistChanged(playlistId, QueueOperation.ADD)
        NitroPlayerMediaBrowserService.getInstance()?.onPlaylistUpdated(playlistId)

        // Update ExoPlayer if this is the current playlist
        if (currentPlaylistId == playlistId) {
            TrackPlayerCore.getInstance(context)?.updatePlaylist(playlistId)
        }

        return true
    }

    /**
     * Remove a track from a playlist
     */
    fun removeTrackFromPlaylist(
        playlistId: String,
        trackId: String,
    ): Boolean {
        val playlist =
            synchronized(playlists) {
                playlists[playlistId]
            } ?: return false

        val removed =
            synchronized(playlists) {
                val tracks = playlist.tracks.toMutableList()
                val removed = tracks.removeAll { it.id == trackId }
                if (removed) {
                    playlists[playlistId] = playlist.copy(tracks = tracks)
                }
                removed
            }

        if (removed) {
            scheduleSave()
            notifyPlaylistChanged(playlistId, QueueOperation.REMOVE)
            NitroPlayerMediaBrowserService.getInstance()?.onPlaylistUpdated(playlistId)

            // Update ExoPlayer if this is the current playlist
            if (currentPlaylistId == playlistId) {
                TrackPlayerCore.getInstance(context)?.updatePlaylist(playlistId)
            }
        }

        return removed
    }

    /**
     * Reorder a track in a playlist
     */
    fun reorderTrackInPlaylist(
        playlistId: String,
        trackId: String,
        newIndex: Int,
    ): Boolean {
        val playlist =
            synchronized(playlists) {
                playlists[playlistId]
            } ?: return false

        val tracks = playlist.tracks.toMutableList()
        val oldIndex = tracks.indexOfFirst { it.id == trackId }
        if (oldIndex < 0 || newIndex < 0 || newIndex >= tracks.size) {
            return false
        }

        synchronized(playlists) {
            val track = tracks.removeAt(oldIndex)
            tracks.add(newIndex, track)
            playlists[playlistId] = playlist.copy(tracks = tracks)
        }

        scheduleSave()
        notifyPlaylistChanged(playlistId, QueueOperation.UPDATE)
        NitroPlayerMediaBrowserService.getInstance()?.onPlaylistUpdated(playlistId)

        // Update ExoPlayer if this is the current playlist
        if (currentPlaylistId == playlistId) {
            TrackPlayerCore.getInstance(context)?.updatePlaylist(playlistId)
        }

        return true
    }

    /**
     * Load a playlist for playback (sets it as current)
     */
    fun loadPlaylist(playlistId: String): Boolean {
        val playlist =
            synchronized(playlists) {
                playlists[playlistId]
            } ?: return false

        currentPlaylistId = playlistId
        TrackPlayerCore.getInstance(context)?.loadPlaylist(playlistId)

        return true
    }

    /**
     * Get the current playlist ID
     */
    fun getCurrentPlaylistId(): String? = currentPlaylistId

    /**
     * Get the current playlist
     */
    fun getCurrentPlaylist(): Playlist? = currentPlaylistId?.let { synchronized(playlists) { playlists[it] } }

    /**
     * Add a listener for playlist changes
     */
    fun addPlaylistsChangeListener(listener: (List<Playlist>, QueueOperation?) -> Unit): () -> Unit {
        listeners.add(listener)
        return { listeners.remove(listener) }
    }

    /**
     * Add a listener for a specific playlist changes
     */
    fun addPlaylistChangeListener(
        playlistId: String,
        listener: (Playlist, QueueOperation?) -> Unit,
    ): () -> Unit {
        val playlistListeners = playlistListeners.getOrPut(playlistId) { CopyOnWriteArrayList() }
        playlistListeners.add(listener)
        return { playlistListeners.remove(listener) }
    }

    private fun notifyPlaylistsChanged(operation: QueueOperation?) {
        val allPlaylists =
            synchronized(playlists) {
                playlists.values.toList()
            }
        listeners.forEach { it(allPlaylists, operation) }
    }

    private fun notifyPlaylistChanged(
        playlistId: String,
        operation: QueueOperation?,
    ) {
        val playlist =
            synchronized(playlists) {
                playlists[playlistId]
            } ?: return

        playlistListeners[playlistId]?.forEach { it(playlist, operation) }
    }

    private fun savePlaylistsToPreferences() {
        try {
            val jsonArray = JSONArray()
            synchronized(playlists) {
                playlists.values.forEach { playlist ->
                    val jsonObject =
                        JSONObject().apply {
                            put("id", playlist.id)
                            put("name", playlist.name)
                            put("description", playlist.description ?: "")
                            put("artwork", playlist.artwork ?: "")
                            val tracksArray = JSONArray()
                            playlist.tracks.forEach { track ->
                                tracksArray.put(
                                    JSONObject().apply {
                                        put("id", track.id)
                                        put("title", track.title)
                                        put("artist", track.artist)
                                        put("album", track.album)
                                        put("duration", track.duration)
                                        put("url", track.url)
                                        track.artwork?.let { put("artwork", it) }
                                        // Serialize extraPayload to JSON for persistence
                                        track.extraPayload?.let { payload ->
                                            val extraPayloadMap = payload.toHashMap()
                                            val extraPayloadJson = JSONObject(extraPayloadMap)
                                            put("extraPayload", extraPayloadJson)
                                        }
                                    },
                                )
                            }
                            put("tracks", tracksArray)
                        }
                    jsonArray.put(jsonObject)
                }
            }

            sharedPreferences
                .edit()
                .putString("playlists", jsonArray.toString())
                .putString("currentPlaylistId", currentPlaylistId)
                .apply()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun loadPlaylistsFromPreferences() {
        try {
            val jsonString = sharedPreferences.getString("playlists", null)
            if (jsonString != null) {
                val jsonArray = JSONArray(jsonString)
                synchronized(playlists) {
                    playlists.clear()
                    for (i in 0 until jsonArray.length()) {
                        val jsonObject = jsonArray.getJSONObject(i)
                        val tracks = mutableListOf<TrackItem>()
                        val tracksArray = jsonObject.getJSONArray("tracks")
                        for (j in 0 until tracksArray.length()) {
                            val trackObj = tracksArray.getJSONObject(j)
                            val artworkStr = trackObj.optString("artwork")
                            val artwork: Variant_NullType_String? =
                                if (!artworkStr.isNullOrEmpty()) {
                                    Variant_NullType_String.create(artworkStr)
                                } else {
                                    null
                                }
                            // Deserialize extraPayload from JSON
                            val extraPayload: AnyMap? =
                                if (trackObj.has("extraPayload")) {
                                    val extraPayloadJson = trackObj.getJSONObject("extraPayload")
                                    val map = AnyMap()
                                    val keyIterator = extraPayloadJson.keys()
                                    while (keyIterator.hasNext()) {
                                        val key = keyIterator.next()
                                        when (val value = extraPayloadJson.get(key)) {
                                            is String -> map.setString(key, value)
                                            is Number -> map.setDouble(key, value.toDouble())
                                            is Boolean -> map.setBoolean(key, value)
                                        }
                                    }
                                    map
                                } else {
                                    null
                                }
                            tracks.add(
                                TrackItem(
                                    id = trackObj.getString("id"),
                                    title = trackObj.getString("title"),
                                    artist = trackObj.getString("artist"),
                                    album = trackObj.getString("album"),
                                    duration = trackObj.getDouble("duration"),
                                    url = trackObj.getString("url"),
                                    artwork = artwork,
                                    extraPayload = extraPayload,
                                ),
                            )
                        }
                        val descriptionStr = jsonObject.optString("description")
                        val artworkStr = jsonObject.optString("artwork")
                        val playlist =
                            Playlist(
                                id = jsonObject.getString("id"),
                                name = jsonObject.getString("name"),
                                description = if (!descriptionStr.isNullOrEmpty()) descriptionStr else null,
                                artwork = if (!artworkStr.isNullOrEmpty()) artworkStr else null,
                                tracks = tracks,
                            )
                        playlists[playlist.id] = playlist
                    }
                }
                currentPlaylistId = sharedPreferences.getString("currentPlaylistId", null)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
