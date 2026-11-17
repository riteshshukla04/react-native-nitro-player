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
    // Each session asks for fresh Cast URLs; resume where local playback was once the current one arrives.
    castUrls.clear()
    castUrlRequestedAt.clear()
    castResume = null
    castPendingList = null
    exo = ExoPlayerCore(controller.castPlayer)
    playerListener?.let { controller.castPlayer.addListener(it) }
    setMediaSessionPlayer(controller.castPlayer)

    val castList = ArrayList<TrackItem>()
    currentTrack?.let { castList.add(it) }
    castList.addAll(upcoming)
    val playable = castableUpcoming(castList)
    controller.castPlayer.repeatMode = repeat
    controller.castPlayer.playWhenReady = wasPlaying

    if (playable.isNotEmpty()) {
        lastCastWaitTrackId = null
        val items = playable.map { makeMediaItem(it, mediaIdFor(it)) }
        // Resume mid-track only when the receiver starts on the locally playing track.
        val resumeFromCurrent = currentTrack != null && playable.first().id == currentTrack.id
        controller.castPlayer.setMediaItems(items, 0, if (resumeFromCurrent) positionMs else 0L)
        controller.castPlayer.prepare()
    } else {
        // Nothing castable yet (lazy queue or Cast URLs pending) — request URLs; updateTracks / setCastUrls will load.
        // Remember what was playing so it resumes there once its Cast URL arrives.
        if (suppliesCastUrls && castList.isNotEmpty()) {
            castPendingList = castList
            castResume = currentTrack?.let { it.id to positionMs }
        }
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
    castUrls.clear()
    castUrlRequestedAt.clear()
    castResume = null
    castPendingList = null
    playerHandler.removeCallbacks(castUrlRetryRunnable)
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

// ── App-supplied Cast URLs ────────────────────────────────────────────────

/** Apply app-supplied Cast URLs: load the receiver if it was waiting, else resync the items after the current one. */
internal fun TrackPlayerCore.setCastUrlsOnQueue(urls: Map<String, String>) {
    // URLs belong to a session; a late answer after disconnecting must not leak into the next one
    if (!isCastingField || !isExoInitialized) return
    val supplied = urls.filterValues { it.isNotEmpty() }
    if (supplied.isEmpty()) return
    castUrls.putAll(supplied)
    supplied.keys.forEach { castUrlRequestedAt.remove(it) }

    if (exo.mediaItemCount > 0) {
        // Upcoming items whose URL changed are replaced; the playing one keeps its URL.
        rebuildQueueFromCurrentPosition()
        return
    }

    // The receiver started empty: load what was playing at connect, temporary tracks included
    val pending = castPendingList
    if (pending != null) {
        val playable = castableUpcoming(pending)
        if (playable.isEmpty()) return
        castPendingList = null
        lastCastWaitTrackId = null
        playerHandler.removeCallbacks(castUrlRetryRunnable)
        val resume = castResume?.takeIf { it.first == playable.first().id }?.second ?: 0L
        castResume = null
        val controller = castSessionController ?: return
        // The receiver hasn't reported the queue yet; the first item transition re-checks the URLs it needs
        controller.castPlayer.setMediaItems(playable.map { makeMediaItem(it, mediaIdFor(it)) }, 0, resume)
        controller.castPlayer.prepare()
        return
    }

    if (currentTracks.getOrNull(currentTrackIndex) == null) return
    rebuildQueueAndPlayFromIndex(currentTrackIndex)
}

/** Keeps the connect-time Cast queue in step with a playlist edit made while its URLs are still pending. */
internal fun TrackPlayerCore.refreshCastPendingList() {
    val head = castPendingList?.firstOrNull() ?: return
    val removed = currentTemporaryType == TrackPlayerCore.TemporaryType.NONE && currentTracks.none { it.id == head.id }
    if (removed) {
        castPendingList = null
        castResume = null
        // Like a removed playing track: move on to the one that took its place
        if (currentTracks.isNotEmpty()) playFromIndexInternal(minOf(currentTrackIndex + 1, currentTracks.size - 1))
        return
    }
    castPendingList = listOf(head) + buildUpcomingQueueTracks(head.id)
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
