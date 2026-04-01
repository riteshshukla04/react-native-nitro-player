@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.NullType
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.core.loadPlaylist
import com.margelo.nitro.nitroplayer.core.updatePlaylist
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager
import java.util.UUID
import com.margelo.nitro.nitroplayer.playlist.Playlist as InternalPlaylist

@DoNotStrip
@Keep
class HybridPlayerQueue : HybridPlayerQueueSpec() {
    private val core: TrackPlayerCore
    private val playlistManager: PlaylistManager

    init {
        val context =
            NitroModules.applicationContext
                ?: throw IllegalStateException("React Context is not initialized")
        core = TrackPlayerCore.getInstance(context)
        playlistManager = core.getPlaylistManager()
    }

    private val playlistsChangeListeners = java.util.concurrent.CopyOnWriteArrayList<() -> Unit>()
    private val playlistChangeListeners = java.util.concurrent.ConcurrentHashMap<String, () -> Unit>()

    // ── Playlist CRUD ─────────────────────────────────────────────────────────

    override fun createPlaylist(
        name: String,
        description: String?,
        artwork: String?,
    ): Promise<String> = Promise.async { playlistManager.createPlaylist(name, description, artwork) }

    override fun deletePlaylist(playlistId: String): Promise<Unit> =
        Promise.async {
            playlistManager.deletePlaylist(playlistId)
        }

    override fun updatePlaylist(
        playlistId: String,
        name: String?,
        description: String?,
        artwork: String?,
    ): Promise<Unit> =
        Promise.async {
            playlistManager.updatePlaylist(playlistId, name, description, artwork)
            core.updatePlaylist(playlistId)
        }

    override fun getPlaylist(playlistId: String): Variant_NullType_Playlist {
        val playlist = playlistManager.getPlaylist(playlistId)
        return if (playlist != null) {
            Variant_NullType_Playlist.create(playlist.toPlaylist())
        } else {
            Variant_NullType_Playlist.create(NullType.NULL)
        }
    }

    override fun getAllPlaylists(): Array<Playlist> = playlistManager.getAllPlaylists().map { it.toPlaylist() }.toTypedArray()

    // ── Track mutations ───────────────────────────────────────────────────────

    override fun addTrackToPlaylist(
        playlistId: String,
        track: TrackItem,
        index: Double?,
    ): Promise<Unit> =
        Promise.async {
            playlistManager.addTrackToPlaylist(playlistId, track, index?.toInt())
            core.updatePlaylist(playlistId)
        }

    override fun addTracksToPlaylist(
        playlistId: String,
        tracks: Array<TrackItem>,
        index: Double?,
    ): Promise<Unit> =
        Promise.async {
            playlistManager.addTracksToPlaylist(playlistId, tracks.toList(), index?.toInt())
            core.updatePlaylist(playlistId)
        }

    override fun removeTrackFromPlaylist(
        playlistId: String,
        trackId: String,
    ): Promise<Unit> =
        Promise.async {
            playlistManager.removeTrackFromPlaylist(playlistId, trackId)
            core.updatePlaylist(playlistId)
        }

    override fun reorderTrackInPlaylist(
        playlistId: String,
        trackId: String,
        newIndex: Double,
    ): Promise<Unit> =
        Promise.async {
            playlistManager.reorderTrackInPlaylist(playlistId, trackId, newIndex.toInt())
            core.updatePlaylist(playlistId)
        }

    // ── Playback control ──────────────────────────────────────────────────────

    override fun loadPlaylist(playlistId: String): Promise<Unit> =
        Promise.async {
            core.loadPlaylist(playlistId)
        }

    override fun getCurrentPlaylistId(): Variant_NullType_String {
        val id = core.getCurrentPlaylistId()
        return if (id != null) {
            Variant_NullType_String.create(id)
        } else {
            Variant_NullType_String.create(NullType.NULL)
        }
    }

    // ── Events ────────────────────────────────────────────────────────────────

    override fun onPlaylistsChanged(callback: (playlists: Array<Playlist>, operation: QueueOperation?) -> Unit) {
        val removeListener =
            playlistManager.addPlaylistsChangeListener { playlists, operation ->
                callback(playlists.map { it.toPlaylist() }.toTypedArray(), operation)
            }
        playlistsChangeListeners.add(removeListener)
    }

    override fun onPlaylistChanged(callback: (playlistId: String, playlist: Playlist, operation: QueueOperation?) -> Unit) {
        val listenerId = UUID.randomUUID().toString()
        playlistManager.getAllPlaylists().forEach { internalPlaylist ->
            val removeListener =
                playlistManager.addPlaylistChangeListener(internalPlaylist.id) { playlist, operation ->
                    callback(playlist.id, playlist.toPlaylist(), operation)
                }
            playlistChangeListeners[listenerId] = removeListener
        }
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    private fun InternalPlaylist.toPlaylist(): Playlist =
        Playlist(
            id = this.id,
            name = this.name,
            description = this.description?.let { Variant_NullType_String.create(it) },
            artwork = this.artwork?.let { Variant_NullType_String.create(it) },
            tracks = this.tracks.toTypedArray(),
        )
}
