package com.margelo.nitro.nitroplayer.media

import android.content.Context
import android.os.Handler
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession

/**
 * Cast-free build (`nitroPlayerCastEnabled=false`): Google Cast is not compiled
 * in, so there is never a [CastSessionController] and all Cast features are inert.
 */
@UnstableApi
internal object CastSessionFactory {
    @Suppress("UNUSED_PARAMETER")
    fun create(
        context: Context,
        localPlayer: Player,
        localSessionPlayer: Player,
        mediaSession: MediaSession,
        mainHandler: Handler,
    ): CastSessionController? = null
}
