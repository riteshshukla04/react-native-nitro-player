@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import android.app.Activity
import androidx.media3.common.Player
import com.margelo.nitro.nitroplayer.CastState
import com.margelo.nitro.nitroplayer.TrackItem
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
// The queue is rebuilt for the target backend (not item-copied): cast needs remote URLs, local prefers download paths.

internal fun TrackPlayerCore.switchToCastPlayer() {
    val controller = castSessionController ?: return
    if (!isExoInitialized) return
    val local = exo.player
    if (local === controller.castPlayer) return

    // Capture context BEFORE swapping — the queue helpers read `exo`, and the cast timeline is still empty.
    val currentId = local.currentMediaItem?.mediaId?.let { extractTrackId(it) }
    val currentTrack = getCurrentTrack() ?: currentTracks.getOrNull(currentTrackIndex)
    val upcoming = buildUpcomingQueueTracks(currentId)
    val positionMs = local.currentPosition.coerceAtLeast(0L)
    val wasPlaying = local.playWhenReady
    val repeat = local.repeatMode

    playerListener?.let { local.removeListener(it) }
    local.playWhenReady = false // silence local output — audio now comes from the device

    isCastingField = true // before building items so makeMediaItem picks remote URLs
    exo = ExoPlayerCore(controller.castPlayer)
    playerListener?.let { controller.castPlayer.addListener(it) }
    setMediaSessionPlayer(controller.castPlayer)

    val castList = ArrayList<TrackItem>()
    currentTrack?.let { castList.add(it) }
    castList.addAll(upcoming)
    val playable = castableUpcoming(castList)

    if (playable.isNotEmpty()) {
        lastCastWaitTrackId = null
        val items = playable.map { makeMediaItem(it, mediaIdFor(it)) }
        // Resume mid-track only when the receiver starts on the locally playing track.
        val resumeFromCurrent = currentTrack != null && playable.first().id == currentTrack.id
        controller.castPlayer.setMediaItems(items, 0, if (resumeFromCurrent) positionMs else 0L)
        controller.castPlayer.repeatMode = repeat
        controller.castPlayer.playWhenReady = wasPlaying
        controller.castPlayer.prepare()
    } else {
        // Nothing castable yet (lazy queue) — request URLs; updateTracks will load.
        checkUpcomingTracksForUrls(lookaheadCount)
    }

    notifyCastStateChange(CastState.CONNECTED, controller.currentDeviceName())
}

internal fun TrackPlayerCore.switchToLocalPlayer() {
    val controller = castSessionController ?: return
    if (!isExoInitialized) return
    val cast = exo.player
    if (cast === controller.localPlayer) return

    // Capture context before swapping (the cast timeline empties once the session ends).
    val currentId = cast.currentMediaItem?.mediaId?.let { extractTrackId(it) }
    val currentTrack = getCurrentTrack() ?: currentTracks.getOrNull(currentTrackIndex)
    val upcoming = buildUpcomingQueueTracks(currentId)
    val positionMs = cast.currentPosition.coerceAtLeast(0L)
    val wasPlaying = cast.playWhenReady
    val repeat = cast.repeatMode

    playerListener?.let { cast.removeListener(it) }
    cast.playWhenReady = false

    isCastingField = false // before building items so makeMediaItem restores download paths
    lastCastWaitTrackId = null
    exo = ExoPlayerCore(controller.localPlayer)
    playerListener?.let { controller.localPlayer.addListener(it) }
    setMediaSessionPlayer(controller.localPlayer)

    val localList = ArrayList<TrackItem>()
    currentTrack?.let { localList.add(it) }
    localList.addAll(upcoming)

    if (localList.isNotEmpty()) {
        val items = localList.map { makeMediaItem(it, mediaIdFor(it)) }
        controller.localPlayer.setMediaItems(items, 0, positionMs)
        controller.localPlayer.repeatMode = repeat
        controller.localPlayer.playWhenReady = wasPlaying
        controller.localPlayer.prepare()
    }

    notifyCastStateChange(controller.getCastState(), controller.currentDeviceName())
}

private fun TrackPlayerCore.setMediaSessionPlayer(target: Player) {
    try {
        castSessionController?.let { it.mediaSession.player = target }
    } catch (e: Exception) {
        NitroPlayerLogger.log("TrackPlayerCast") { "setPlayer on MediaSession failed: ${e.message}" }
    }
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
