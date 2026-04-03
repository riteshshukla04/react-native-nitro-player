package com.margelo.nitro.nitroplayer.media

import android.content.Intent
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger

/**
 * Foreground service that keeps playback alive when the app is backgrounded or the screen is locked.
 *
 * Media3's [MediaSessionService] automatically:
 * - Promotes to a foreground service (with notification) when playback starts
 * - Demotes / stops when playback stops
 * - Posts a media-style notification with transport controls
 * - Handles media-button intents
 */
class NitroPlayerPlaybackService : MediaSessionService() {

    companion object {
        @Volatile
        var mediaSession: MediaSession? = null
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val session = mediaSession
        if (session == null || !session.player.playWhenReady) {
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        NitroPlayerLogger.log("PlaybackService") { "Service destroyed" }
        super.onDestroy()
    }
}
