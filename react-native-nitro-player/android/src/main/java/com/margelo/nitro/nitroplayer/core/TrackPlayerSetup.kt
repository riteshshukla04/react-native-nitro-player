package com.margelo.nitro.nitroplayer.core

import com.margelo.nitro.nitroplayer.equalizer.EqualizerCore
import com.margelo.nitro.nitroplayer.media.MediaSessionManager
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService
import com.margelo.nitro.nitroplayer.media.NitroPlayerPlaybackService

/**
 * Initialises ExoPlayerCore wrapper and MediaSessionManager from the service binder.
 * Called once from TrackPlayerCore's ServiceConnection.onServiceConnected via playerHandler.post.
 */
internal fun TrackPlayerCore.initFromService(binder: NitroPlayerPlaybackService.LocalBinder) {
    // Wrap the service-owned ExoPlayer
    exo = ExoPlayerCore(binder.exoPlayer)

    // Wrap the service-owned MediaSession (no longer creates its own)
    mediaSessionManager =
        MediaSessionManager(context, binder.session, playlistManager).apply {
            setTrackPlayerCore(this@initFromService)
        }

    // Give MediaBrowserService access to this core and media session
    NitroPlayerMediaBrowserService.trackPlayerCore = this
    NitroPlayerMediaBrowserService.mediaSessionManager = mediaSessionManager

    // Attach player listener
    val listener = TrackPlayerEventListener(this)
    playerListener = listener
    exo.addListener(listener)

    // Wire Google Cast (if available on this device) so sessions can swap the
    // active player to/from the CastPlayer.
    binder.castController?.let { controller ->
        castSessionController = controller
        controller.attachCore(this)
    }

    // The audio session ID is assigned during ExoPlayer construction (in
    // PlaybackService.onCreate), before our listener is attached.
    // onAudioSessionIdChanged only fires on *changes*, so we'd miss the
    // initial value. Manually feed it to the equalizer now.
    val sessionId = binder.exoPlayer.audioSessionId
    if (sessionId != 0) {
        try {
            EqualizerCore.getInstance(context).initialize(sessionId)
        } catch (_: Exception) {
        }
    }

    // Start progress ticks on the main looper
    playerHandler.postDelayed(progressUpdateRunnable, TrackPlayerCore.PROGRESS_INTERVAL_MS)

    // Signal that the player is ready — unblocks all withPlayerContext callers
    completeServiceReady()

    // Flush any commands JS issued before the service bound, in their original order
    startCommandDraining()
}
