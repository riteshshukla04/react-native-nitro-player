@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import android.app.Activity
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import com.margelo.nitro.nitroplayer.CastState
import com.margelo.nitro.nitroplayer.media.NitroCastConfig

/**
 * Google Cast backend integration for [TrackPlayerCore].
 *
 * Casting is modelled as a *backend swap*: the active Media3 [Player] wrapped by
 * [ExoPlayerCore] is switched from the local `ExoPlayer` to the `CastPlayer` (and
 * back) while keeping all queue state, listeners and the [androidx.media3.session.MediaSession]
 * pointed at whichever player is active. Because both implement [Player], the rest
 * of the core is unaware of which backend is playing.
 *
 * All functions here run on the player (main) looper.
 */

// ── Backend switching ──────────────────────────────────────────────────────

internal fun TrackPlayerCore.switchToCastPlayer() {
    val controller = castSessionController ?: return
    switchToPlayer(controller.castPlayer)
    isCastingField = true
    notifyCastStateChange(CastState.CONNECTED, controller.currentDeviceName())
}

internal fun TrackPlayerCore.switchToLocalPlayer() {
    val controller = castSessionController ?: return
    switchToPlayer(controller.localPlayer)
    isCastingField = false
    notifyCastStateChange(controller.getCastState(), controller.currentDeviceName())
}

private fun TrackPlayerCore.switchToPlayer(target: Player) {
    if (!isExoInitialized) return
    val current = exo.player
    if (current === target) return

    // Move listener, queue and position from the current player to the target,
    // then make the target authoritative for the MediaSession & notification.
    playerListener?.let { current.removeListener(it) }
    transferPlaybackState(current, target)
    current.playWhenReady = false // silence the player we're leaving

    exo = ExoPlayerCore(target)
    playerListener?.let { target.addListener(it) }

    try {
        castSessionController?.let { it.mediaSession.player = target }
    } catch (e: Exception) {
        NitroPlayerLogger.log("TrackPlayerCast") { "setPlayer on MediaSession failed: ${e.message}" }
    }
}

/** Copy the queue, index, position, repeat mode and play-when-ready from one player to another. */
private fun transferPlaybackState(
    from: Player,
    to: Player,
) {
    val count = from.mediaItemCount
    if (count == 0) return
    val items = ArrayList<MediaItem>(count)
    for (i in 0 until count) items.add(from.getMediaItemAt(i))
    val index = from.currentMediaItemIndex.coerceAtLeast(0)
    val position = if (from.currentPosition >= 0) from.currentPosition else 0L

    to.setMediaItems(items, index, position)
    to.repeatMode = from.repeatMode
    to.playWhenReady = from.playWhenReady
    to.prepare()
}

// ── Notifications ──────────────────────────────────────────────────────────

internal fun TrackPlayerCore.notifyCastStateChange(
    state: CastState,
    deviceName: String?,
) {
    onCastStateChangeListeners.forEach { it(state, deviceName) }
}

// ── Public accessors (used by HybridCast) ──────────────────────────────────

internal fun TrackPlayerCore.isCasting(): Boolean = isCastingField

internal fun TrackPlayerCore.getCastState(): CastState =
    if (isCastingField) {
        CastState.CONNECTED
    } else {
        castSessionController?.getCastState() ?: CastState.NO_DEVICES_AVAILABLE
    }

internal fun TrackPlayerCore.getCastDeviceName(): String? = castSessionController?.currentDeviceName()

internal fun TrackPlayerCore.endCastSession() {
    castSessionController?.endCurrentSession()
}

internal fun TrackPlayerCore.showCastPicker(activity: Activity) {
    val controller = castSessionController
    if (controller == null) {
        NitroPlayerLogger.log("TrackPlayerCast") { "showCastPicker ignored — Cast unavailable" }
        return
    }
    controller.showCastPicker(activity)
}

internal fun TrackPlayerCore.configureCast(receiverApplicationId: String?) {
    if (receiverApplicationId != null) {
        NitroCastConfig.receiverApplicationId = receiverApplicationId
        if (castSessionController != null) {
            NitroPlayerLogger.log("TrackPlayerCast") {
                "configureCast called after CastContext init — receiver ID takes effect on next app launch"
            }
        }
    }
}
