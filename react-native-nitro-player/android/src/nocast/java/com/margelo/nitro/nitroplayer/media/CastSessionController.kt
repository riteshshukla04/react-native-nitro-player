package com.margelo.nitro.nitroplayer.media

import android.app.Activity
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession
import com.margelo.nitro.nitroplayer.CastState
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore

/**
 * Cast-free stand-in for the Google Cast controller, keeping the core's Cast
 * plumbing compiling without the Cast SDK. Never instantiated —
 * [CastSessionFactory.create] always returns null in this build.
 */
@UnstableApi
class CastSessionController private constructor(
    val castPlayer: Player,
    val localPlayer: Player,
    val localSessionPlayer: Player,
    val mediaSession: MediaSession,
) {
    fun attachCore(core: TrackPlayerCore) = Unit

    fun getCastState(): CastState = CastState.NO_DEVICES_AVAILABLE

    fun currentDeviceName(): String? = null

    fun endCurrentSession() = Unit

    fun showCastPicker(activity: Activity) = Unit

    fun release() = Unit
}
