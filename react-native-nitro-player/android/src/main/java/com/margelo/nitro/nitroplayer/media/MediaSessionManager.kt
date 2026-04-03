package com.margelo.nitro.nitroplayer.media

import android.content.Context
import androidx.media3.session.MediaSession
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager

/**
 * Thin wrapper around a [MediaSession] owned by the playback service.
 *
 * No longer creates the session, notification channel, or manages service
 * start/stop — the service handles all of that automatically per Media3 docs.
 */
class MediaSessionManager(
    private val context: Context,
    session: MediaSession,
    private val playlistManager: PlaylistManager,
) {
    private var trackPlayerCore: TrackPlayerCore? = null

    fun setTrackPlayerCore(core: TrackPlayerCore) {
        trackPlayerCore = core
    }

    var mediaSession: MediaSession? = session
        private set

    @Volatile private var currentTrack: TrackItem? = null
    @Volatile private var isPlaying: Boolean = false

    private var androidAutoEnabled: Boolean = false
    private var carPlayEnabled: Boolean = false
    private var showInNotification: Boolean = true

    fun configure(
        androidAutoEnabled: Boolean?,
        carPlayEnabled: Boolean?,
        showInNotification: Boolean?,
    ) {
        androidAutoEnabled?.let { this.androidAutoEnabled = it }
        carPlayEnabled?.let { this.carPlayEnabled = it }
        showInNotification?.let { this.showInNotification = it }
    }

    fun onTrackChanged(track: TrackItem?) {
        currentTrack = track
    }

    fun onPlaybackStateChanged(playing: Boolean) {
        isPlaying = playing
    }

    fun release() {
        // Service owns the session — just null out our reference
        mediaSession = null
    }
}
