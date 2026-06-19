@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.media

import android.app.Activity
import android.os.Handler
import androidx.media3.cast.CastPlayer
import androidx.media3.cast.SessionAvailabilityListener
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.mediarouter.app.MediaRouteControllerDialog
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastStateListener
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.core.notifyCastStateChange
import com.margelo.nitro.nitroplayer.core.switchToCastPlayer
import com.margelo.nitro.nitroplayer.core.switchToLocalPlayer
import androidx.media3.session.MediaSession
import com.google.android.gms.cast.framework.CastState as GmsCastState
import com.margelo.nitro.nitroplayer.CastState

/**
 * Owns the Google Cast [CastPlayer] and bridges Cast session lifecycle into the
 * player core.
 *
 * Created by [NitroPlayerPlaybackService] once a `CastContext` is available, then
 * wired to [TrackPlayerCore] via [attachCore]. When a Cast session starts, the
 * core swaps its active player to [castPlayer] (see `TrackPlayerCast`), so audio
 * plays only on the remote device; on disconnect it swaps back to [localPlayer].
 */
@UnstableApi
class CastSessionController(
    private val castContext: CastContext,
    val castPlayer: CastPlayer,
    val localPlayer: Player,
    val mediaSession: MediaSession,
    private val mainHandler: Handler,
) {
    private var core: TrackPlayerCore? = null

    // Cast SDK reads (castState, current session) MUST happen on the main thread —
    // it throws IllegalStateException otherwise. Nitro sync getters run on the JS
    // thread, so we keep a main-thread-updated cache and serve the getters from it.
    @Volatile private var cachedState: CastState = CastState.NO_DEVICES_AVAILABLE
    @Volatile private var cachedDeviceName: String? = null

    private val castStateListener =
        CastStateListener {
            val c = core ?: return@CastStateListener
            mainHandler.post {
                refreshCacheOnMain()
                c.notifyCastStateChange(cachedState, cachedDeviceName)
            }
        }

    private val sessionAvailabilityListener =
        object : SessionAvailabilityListener {
            override fun onCastSessionAvailable() {
                mainHandler.post {
                    refreshCacheOnMain()
                    core?.switchToCastPlayer()
                }
            }

            override fun onCastSessionUnavailable() {
                mainHandler.post {
                    refreshCacheOnMain()
                    core?.switchToLocalPlayer()
                }
            }
        }

    /** Wire this controller to the core and start listening for Cast events. */
    fun attachCore(core: TrackPlayerCore) {
        this.core = core
        castPlayer.setSessionAvailabilityListener(sessionAvailabilityListener)
        castContext.addCastStateListener(castStateListener)

        // If a session is already live (e.g. resumed on app launch), adopt it.
        if (castPlayer.isCastSessionAvailable) {
            mainHandler.post { core.switchToCastPlayer() }
        }
        // Emit the current state so JS reflects reality immediately.
        mainHandler.post {
            refreshCacheOnMain()
            core.notifyCastStateChange(cachedState, cachedDeviceName)
        }
    }

    /** Cached value — safe to call from the JS thread. */
    fun getCastState(): CastState = cachedState

    /** Cached value — safe to call from the JS thread. */
    fun currentDeviceName(): String? = cachedDeviceName

    /** Re-read the live Cast state into the cache. MUST run on the main thread. */
    private fun refreshCacheOnMain() {
        cachedState =
            try {
                mapCastState(castContext.castState)
            } catch (_: Exception) {
                cachedState
            }
        cachedDeviceName =
            try {
                castContext.sessionManager.currentCastSession?.castDevice?.friendlyName
            } catch (_: Exception) {
                null
            }
    }

    fun endCurrentSession() {
        mainHandler.post {
            try {
                castContext.sessionManager.endCurrentSession(true)
            } catch (e: Exception) {
                NitroPlayerLogger.log("CastSessionController") { "endCurrentSession failed: ${e.message}" }
            }
        }
    }

    /**
     * Present the native Cast dialog: the device chooser when not connected, or
     * the route controller (with disconnect) when already casting. Requires a
     * foreground [Activity].
     */
    fun showCastPicker(activity: Activity) {
        try {
            if (castContext.castState == GmsCastState.CONNECTED) {
                MediaRouteControllerDialog(activity).show()
            } else {
                val selector = castContext.mergedSelector ?: return
                MediaRouteChooserDialog(activity).apply {
                    routeSelector = selector
                }.show()
            }
        } catch (e: Exception) {
            NitroPlayerLogger.log("CastSessionController") { "showCastPicker failed: ${e.message}" }
        }
    }

    fun release() {
        try {
            castPlayer.setSessionAvailabilityListener(null)
            castContext.removeCastStateListener(castStateListener)
            castPlayer.release()
        } catch (_: Exception) {
        }
    }

    private fun mapCastState(state: Int): CastState =
        when (state) {
            GmsCastState.NO_DEVICES_AVAILABLE -> CastState.NO_DEVICES_AVAILABLE
            GmsCastState.CONNECTING -> CastState.CONNECTING
            GmsCastState.CONNECTED -> CastState.CONNECTED
            else -> CastState.NOT_CONNECTED
        }
}
