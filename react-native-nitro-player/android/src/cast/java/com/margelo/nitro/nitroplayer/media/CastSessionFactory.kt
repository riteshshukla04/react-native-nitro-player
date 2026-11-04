package com.margelo.nitro.nitroplayer.media

import android.content.Context
import android.os.Handler
import androidx.media3.cast.CastPlayer
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession
import com.google.android.gms.cast.framework.CastContext
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger

/**
 * Builds the [CastSessionController] for [NitroPlayerPlaybackService].
 *
 * Lives in the `cast` source set so the Google Cast SDK is only referenced when
 * `nitroPlayerCastEnabled` is true; the `nocast` source set provides a stub that
 * always returns null.
 */
@UnstableApi
internal object CastSessionFactory {
    /**
     * Best-effort: when Google Play services or the Cast framework are unavailable
     * (older devices, no Play services), returns null and all Cast features become
     * inert no-ops.
     */
    fun create(
        context: Context,
        localPlayer: Player,
        localSessionPlayer: Player,
        mediaSession: MediaSession,
        mainHandler: Handler,
    ): CastSessionController? =
        try {
            val castContext = CastContext.getSharedInstance(context)
            val castPlayer =
                CastPlayer(
                    castContext,
                    NitroMediaItemConverter(),
                    ExoPlayerBuilder.DEFAULT_REMOTE_SKIP_INTERVAL_MS,
                    ExoPlayerBuilder.DEFAULT_REMOTE_SKIP_INTERVAL_MS,
                )
            CastSessionController(
                castContext = castContext,
                castPlayer = castPlayer,
                localPlayer = localPlayer,
                localSessionPlayer = localSessionPlayer,
                mediaSession = mediaSession,
                mainHandler = mainHandler,
            )
        } catch (e: Exception) {
            NitroPlayerLogger.log("PlaybackService") { "Cast unavailable: ${e.message}" }
            null
        }
}
