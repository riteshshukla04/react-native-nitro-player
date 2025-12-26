package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.jni.HybridData
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.NullType
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager
import java.util.UUID
import com.margelo.nitro.nitroplayer.playlist.Playlist as InternalPlaylist

class HybridPlayerQueue : HybridPlayerQueueSpec() {
    private val core: TrackPlayerCore
    private val playlistManager: PlaylistManager

    init {
        val context = NitroModules.applicationContext ?: throw IllegalStateException("React Context is not initialized")
        core = TrackPlayerCore.getInstance(context)
        playlistManager = core.getPlaylistManager()
    }

    private var playlistsChangeListener: (() -> Unit)? = null
    private val playlistChangeListeners = mutableMapOf<String, () -> Unit>()

    @DoNotStrip
    @Keep
    override fun createPlaylist(
        name: String,
        description: String?,
        artwork: String?,
    ): String = playlistManager.createPlaylist(name, description, artwork)

    @DoNotStrip
    @Keep
    override fun deletePlaylist(playlistId: String) {
        playlistManager.deletePlaylist(playlistId)
    }

    @DoNotStrip
    @Keep
    override fun updatePlaylist(
        playlistId: String,
        name: String?,
        description: String?,
        artwork: String?,
    ) {
        playlistManager.updatePlaylist(playlistId, name, description, artwork)
    }

    @DoNotStrip
    @Keep
    override fun getPlaylist(playlistId: String): Variant_NullType_Playlist {
        val playlist = playlistManager.getPlaylist(playlistId)
        return if (playlist != null) {
            Variant_NullType_Playlist.create(playlist.toPlaylist())
        } else {
            Variant_NullType_Playlist.create(NullType.NULL)
        }
    }

    @DoNotStrip
    @Keep
    override fun getAllPlaylists(): Array<Playlist> =
        playlistManager
            .getAllPlaylists()
            .map {
                it.toPlaylist()
            }.toTypedArray()

    @DoNotStrip
    @Keep
    override fun addTrackToPlaylist(
        playlistId: String,
        track: TrackItem,
        index: Double?,
    ) {
        val insertIndex = index?.toInt()
        playlistManager.addTrackToPlaylist(playlistId, track, insertIndex)
    }

    @DoNotStrip
    @Keep
    override fun addTracksToPlaylist(
        playlistId: String,
        tracks: Array<TrackItem>,
        index: Double?,
    ) {
        val insertIndex = index?.toInt()
        playlistManager.addTracksToPlaylist(playlistId, tracks.toList(), insertIndex)
    }

    @DoNotStrip
    @Keep
    override fun removeTrackFromPlaylist(
        playlistId: String,
        trackId: String,
    ) {
        playlistManager.removeTrackFromPlaylist(playlistId, trackId)
    }

    @DoNotStrip
    @Keep
    override fun reorderTrackInPlaylist(
        playlistId: String,
        trackId: String,
        newIndex: Double,
    ) {
        playlistManager.reorderTrackInPlaylist(playlistId, trackId, newIndex.toInt())
    }

    @DoNotStrip
    @Keep
    override fun loadPlaylist(playlistId: String) {
        playlistManager.loadPlaylist(playlistId)
    }

    @DoNotStrip
    @Keep
    override fun getCurrentPlaylistId(): Variant_NullType_String {
        val playlistId = playlistManager.getCurrentPlaylistId()
        return if (playlistId != null) {
            Variant_NullType_String.create(playlistId)
        } else {
            Variant_NullType_String.create(NullType.NULL)
        }
    }

    @DoNotStrip
    @Keep
    override fun onPlaylistsChanged(callback: (playlists: Array<Playlist>, operation: QueueOperation?) -> Unit) {
        // Remove previous listener if exists
        playlistsChangeListener?.invoke()

        // Add new listener
        playlistsChangeListener =
            playlistManager.addPlaylistsChangeListener { playlists, operation ->
                callback(playlists.map { it.toPlaylist() }.toTypedArray(), operation)
            }
    }

    @DoNotStrip
    @Keep
    override fun onPlaylistChanged(callback: (playlistId: String, playlist: Playlist, operation: QueueOperation?) -> Unit) {
        // Listen to all playlists and filter by playlistId
        val listenerId = UUID.randomUUID().toString()

        // For each playlist, add a listener
        playlistManager.getAllPlaylists().forEach { internalPlaylist ->
            val removeListener =
                playlistManager.addPlaylistChangeListener(internalPlaylist.id) { playlist, operation ->
                    callback(playlist.id, playlist.toPlaylist(), operation)
                }
            playlistChangeListeners[listenerId] = removeListener
        }
    }

    // Helper to convert internal Playlist to generated Playlist type
    private fun InternalPlaylist.toPlaylist(): Playlist =
        Playlist(
            id = this.id,
            name = this.name,
            description = this.description?.let { Variant_NullType_String.create(it) },
            artwork = this.artwork?.let { Variant_NullType_String.create(it) },
            tracks = this.tracks.toTypedArray(),
        )
}
