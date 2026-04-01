package com.margelo.nitro.nitroplayer.core

import com.margelo.nitro.nitroplayer.media.MediaSessionManager
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService

/**
 * Initialises ExoPlayer (via ExoPlayerCore) and MediaSessionManager on the player thread.
 * Called once from TrackPlayerCore.init via playerHandler.post.
 */
internal fun TrackPlayerCore.initExoAndMedia() {
    exo = ExoPlayerCore(context, playerThread)

    mediaSessionManager =
        MediaSessionManager(context, exo.player, playlistManager).apply {
            setTrackPlayerCore(this@initExoAndMedia)
        }

    // Give MediaBrowserService access to this core and media session
    NitroPlayerMediaBrowserService.trackPlayerCore = this
    NitroPlayerMediaBrowserService.mediaSessionManager = mediaSessionManager

    // Attach player listener
    val listener = TrackPlayerEventListener(this)
    playerListener = listener
    exo.addListener(listener)

    // Start progress ticks on the player thread
    playerHandler.postDelayed(progressUpdateRunnable, 250)
}
