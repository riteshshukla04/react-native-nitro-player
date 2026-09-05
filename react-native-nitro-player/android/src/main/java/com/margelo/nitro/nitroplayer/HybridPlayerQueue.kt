@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.NullType
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.core.loadPlaylistOnQueue
import com.margelo.nitro.nitroplayer.core.updatePlaylist
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager
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

    // ── Playlist CRUD ─────────────────────────────────────────────────────────

    override fun createPlaylist(
        name: String,
        description: String?,
        artwork: String?,
    ): Promise<String> = Promise.async { playlistManager.createPlaylist(name, description, artwork) }

    override fun deletePlaylist(playlistId: String): Promise<Unit> =
        Promise.async {
            if (!playlistManager.deletePlaylist(playlistId)) {
                throw IllegalArgumentException("Playlist not found: $playlistId")
            }
        }

    override fun updatePlaylist(
        playlistId: String,
        name: String?,
        description: String?,
        artwork: String?,
    ): Promise<Unit> =
        Promise.async {
            if (!playlistManager.updatePlaylist(playlistId, name, description, artwork)) {
                throw IllegalArgumentException("Playlist not found: $playlistId")
            }
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
            if (!playlistManager.addTrackToPlaylist(playlistId, track, index?.toInt())) {
                throw IllegalArgumentException("Playlist not found: $playlistId")
            }
            core.updatePlaylist(playlistId)
        }

    override fun addTracksToPlaylist(
        playlistId: String,
        tracks: Array<TrackItem>,
        index: Double?,
    ): Promise<Unit> =
        Promise.async {
            if (!playlistManager.addTracksToPlaylist(playlistId, tracks.toList(), index?.toInt())) {
                throw IllegalArgumentException("Playlist not found: $playlistId")
            }
            core.updatePlaylist(playlistId)
        }

    /** Same semantics as the batch form: unknown ids are skipped, only a missing playlist rejects. */
    override fun removeTrackFromPlaylist(
        playlistId: String,
        trackId: String,
    ): Promise<Unit> = removeTracksFromPlaylist(playlistId, arrayOf(trackId))

    override fun reorderTrackInPlaylist(
        playlistId: String,
        trackId: String,
        newIndex: Double,
    ): Promise<Unit> =
        Promise.async {
            if (!playlistManager.reorderTrackInPlaylist(playlistId, trackId, newIndex.toInt())) {
                throw IllegalArgumentException("Invalid reorder for track $trackId in playlist $playlistId")
            }
            core.updatePlaylist(playlistId)
        }

    /** On the player looper: the live queue must reflect the removal before the promise resolves. */
    override fun removeTracksFromPlaylist(
        playlistId: String,
        trackIds: Array<String>,
    ): Promise<Unit> {
        val promise = Promise<Unit>()
        core.enqueue {
            val removed = playlistManager.removeTracksFromPlaylist(playlistId, trackIds.toList())
            if (removed == null) {
                promise.reject(IllegalArgumentException("Playlist not found: $playlistId"))
                return@enqueue
            }
            if (removed > 0 && core.getCurrentPlaylistId() == playlistId) core.syncCurrentPlaylistOnQueue()
            promise.resolve(Unit)
        }
        return promise
    }

    /** On the player looper: the anchor id is player-thread state. */
    override fun shufflePlaylist(
        playlistId: String,
        options: ShufflePlaylistOptions?,
    ): Promise<Unit> {
        val promise = Promise<Unit>()
        core.enqueue {
            val isCurrent = core.getCurrentPlaylistId() == playlistId
            val pin =
                if (isCurrent && options?.keepCurrentTrackFirst != false) {
                    core.currentTracks.getOrNull(core.currentTrackIndex)?.id
                } else {
                    null
                }
            val changed = playlistManager.shufflePlaylist(playlistId, pin)
            if (changed == null) {
                promise.reject(IllegalArgumentException("Playlist not found: $playlistId"))
                return@enqueue
            }
            if (changed && isCurrent) core.syncCurrentPlaylistOnQueue()
            promise.resolve(Unit)
        }
        return promise
    }

    // ── Playback control ──────────────────────────────────────────────────────

    /**
     * Enqueued synchronously on the player looper so a `loadPlaylist()` followed by
     * `play()` from JS cannot be reordered — see HybridTrackPlayer.enqueue.
     */
    override fun loadPlaylist(
        playlistId: String,
        index: Double?,
    ): Promise<Unit> {
        val startIndex = index?.toInt()
        val promise = Promise<Unit>()
        core.enqueue {
            if (playlistManager.loadPlaylist(playlistId, startIndex)) {
                core.loadPlaylistOnQueue(playlistId, startIndex)
                promise.resolve(Unit)
            } else {
                promise.reject(IllegalArgumentException("Invalid playlist or index: $playlistId"))
            }
        }
        return promise
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
        // Manager-level listener: covers playlists created after registration,
        // and one remover per callback instead of one per playlist
        val removeListener =
            playlistManager.addAnyPlaylistChangeListener { playlist, operation ->
                callback(playlist.id, playlist.toPlaylist(), operation)
            }
        playlistsChangeListeners.add(removeListener)
    }

    override fun dispose() {
        super.dispose()
        playlistsChangeListeners.forEach { it() }
        playlistsChangeListeners.clear()
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
