@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import android.app.Activity
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.Timeline
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
    // A live stream's position is just time listened, so there is nothing at that offset to resume.
    // An item that hasn't loaded yet (placeholder window) keeps its position.
    val canResumePosition = !isLiveStream(local)
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
        val resumeFromCurrent = canResumePosition && currentTrack != null && playable.first().id == currentTrack.id
        // Set right before the load: the cast load reads both, and a play sent while the receiver has no
        // media yet is dropped. Not earlier, so reattaching to a playing receiver with nothing to load leaves it alone.
        controller.castPlayer.repeatMode = repeat
        controller.castPlayer.playWhenReady = wasPlaying
        controller.castPlayer.setMediaItems(items, 0, if (resumeFromCurrent) positionMs else 0L)
        controller.castPlayer.prepare()
    } else {
        // Nothing castable yet (lazy queue) — request URLs; updateTracks will load, playing if the handed-off track was.
        pendingCastAutoplay = currentTrack?.let { it.id to wasPlaying }
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
    // A live stream's receiver position is just time listened; start it fresh on the phone. The receiver
    // reports live streams as buffered with no duration, so an unknown duration counts as live here.
    val positionMs = if (isLiveStream(cast) || hasUnknownDuration(cast)) 0L else cast.currentPosition.coerceAtLeast(0L)
    val wasPlaying = cast.playWhenReady
    val repeat = cast.repeatMode

    playerListener?.let { cast.removeListener(it) }
    cast.playWhenReady = false

    isCastingField = false // before building items so makeMediaItem restores download paths
    lastCastWaitTrackId = null
    pendingCastAutoplay = null
    exo = ExoPlayerCore(controller.localPlayer)
    playerListener?.let { controller.localPlayer.addListener(it) }
    setMediaSessionPlayer(controller.localSessionPlayer)

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

/** The current item's loaded window, or null while there is none or it is still a placeholder. */
private fun loadedWindow(player: Player): Timeline.Window? {
    val timeline = player.currentTimeline
    if (timeline.isEmpty) return null
    return timeline.getWindow(player.currentMediaItemIndex, Timeline.Window()).takeUnless { it.isPlaceholder }
}

/** A live stream: its position is time listened, which can't be carried to another player. */
private fun isLiveStream(player: Player): Boolean = loadedWindow(player)?.isLive == true

private fun hasUnknownDuration(player: Player): Boolean = loadedWindow(player)?.durationMs == C.TIME_UNSET

/**
 * Applies the play state of a connect that had nothing castable yet, just before a deferred cast load.
 * Only a load that starts on the handed-off track carries it; any other load is the user's own.
 */
internal fun TrackPlayerCore.applyPendingCastAutoplay(firstTrackId: String) {
    val (trackId, autoplay) = pendingCastAutoplay ?: return
    pendingCastAutoplay = null
    if (trackId == firstTrackId) exo.playWhenReady = autoplay
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
