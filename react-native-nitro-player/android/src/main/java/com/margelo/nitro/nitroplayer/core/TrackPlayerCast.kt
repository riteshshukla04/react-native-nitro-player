@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import android.app.Activity
import androidx.media3.common.C
import androidx.media3.common.MediaItem
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
    // Each session asks for fresh Cast URLs; resume where local playback was once the current one arrives.
    castUrls.clear()
    castUrlRequestedAt.clear()
    castResume = null
    castPendingList = null
    clearCastLoadInFlight()
    castLoadRetried = false
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
        markCastLoadInFlight(CastQueueChange.LOAD)
        controller.castPlayer.setMediaItems(items, 0, if (resumeFromCurrent) positionMs else 0L)
        controller.castPlayer.prepare()
    } else {
        // Nothing castable yet (lazy queue or Cast URLs pending) — request URLs; updateTracks / setCastUrls will load,
        // playing if the handed-off track was. A receiver that already has media (a reattach) keeps it and loads
        // nothing, so nothing waits then.
        pendingCastAutoplay = currentTrack?.takeIf { controller.castPlayer.mediaItemCount == 0 }?.let { it.id to wasPlaying }
        // Remember what was playing so it resumes there once its Cast URL arrives.
        if (suppliesCastUrls && castList.isNotEmpty()) {
            castPendingList = castList
            castResume = currentTrack?.takeIf { canResumePosition }?.let { it.id to positionMs }
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
    // A live stream's receiver position is just time listened; start it at its default position (the live edge)
    // on the phone. The receiver reports live streams as buffered with no duration, so that counts as live here.
    val positionMs = if (isLiveStream(cast) || hasUnknownDuration(cast)) C.TIME_UNSET else cast.currentPosition.coerceAtLeast(0L)
    val wasPlaying = cast.playWhenReady
    val repeat = cast.repeatMode

    playerListener?.let { cast.removeListener(it) }
    cast.playWhenReady = false

    isCastingField = false // before building items so makeMediaItem restores download paths
    lastCastWaitTrackId = null
    pendingCastAutoplay = null
    castUrls.clear()
    castUrlRequestedAt.clear()
    castResume = null
    castPendingList = null
    clearCastLoadInFlight()
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

/** The current item's loaded window, or null while there is none or it is still a placeholder. */
private fun loadedWindow(player: Player): Timeline.Window? {
    val timeline = player.currentTimeline
    if (timeline.isEmpty) return null
    return timeline.getWindow(player.currentMediaItemIndex, Timeline.Window()).takeUnless { it.isPlaceholder }
}

// A transcode without a length header reads as live (or, on the receiver, reports no duration); the app-supplied duration says it's finite
private fun hasAppDuration(player: Player): Boolean = (player.currentMediaItem?.mediaMetadata?.durationMs ?: 0L) > 0

/** A live stream: its position is time listened, which can't be carried to another player. */
private fun isLiveStream(player: Player): Boolean = loadedWindow(player)?.isLive == true && !hasAppDuration(player)

private fun hasUnknownDuration(player: Player): Boolean = loadedWindow(player)?.durationMs == C.TIME_UNSET && !hasAppDuration(player)

/**
 * Applies the play state of a connect that had nothing castable yet, just before a deferred cast load.
 * Only a load that starts on the handed-off track carries it; any other load is the user's own.
 */
internal fun TrackPlayerCore.applyPendingCastAutoplay(firstTrackId: String) {
    val (trackId, autoplay) = pendingCastAutoplay ?: return
    pendingCastAutoplay = null
    if (trackId == firstTrackId) exo.playWhenReady = autoplay
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
    // A queue change is on its way to the receiver; its report applies these URLs
    if (castLoadInFlight) {
        castRebuildDeferred = true
        return
    }

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
        val items = playable.map { makeMediaItem(it, mediaIdFor(it)) }
        // The deferred hand-off load: it carries the play state the phone had at connect
        applyPendingCastAutoplay(playable.first().id)
        markCastLoadInFlight(CastQueueChange.LOAD)
        controller.castPlayer.setMediaItems(items, 0, resume)
        controller.castPlayer.prepare()
        return
    }

    if (currentTracks.getOrNull(currentTrackIndex) == null) return
    rebuildQueueAndPlayFromIndex(currentTrackIndex)
}

private const val CAST_LOAD_TIMEOUT_MS = 15_000L

/** A queue change sent to the receiver: a whole new queue, an emptied one, or items inserted or removed after the current one. */
internal enum class CastQueueChange { LOAD, CLEAR, EDIT }

private fun Timeline.periodUids(): Set<Any> = (0 until periodCount).mapTo(HashSet()) { getUidOfPeriod(it) }

/**
 * Marks a load or clear about to be sent to the receiver. media3's cast player only sends it: the local timeline
 * stays as it was until the receiver reports, so until then URL answers, edits and new targets only accumulate.
 * The receiver gives every item it loads a new id, so a load's report is the first transition onto an unknown id.
 */
internal fun TrackPlayerCore.markCastLoadInFlight(change: CastQueueChange) {
    if (!suppliesCastUrls) return
    armCastChange(change)
}

/** Marks an edit about to be sent: reported once [removedUids] are gone and [insertCount] new ids are there. */
internal fun TrackPlayerCore.markCastEditInFlight(
    removedUids: Set<Any>,
    insertCount: Int,
) {
    if (!suppliesCastUrls) return
    castEditRemovedUids = removedUids
    castEditInsertCount = insertCount
    armCastChange(CastQueueChange.EDIT)
}

private fun TrackPlayerCore.armCastChange(change: CastQueueChange) {
    castLoadInFlight = true
    castLoadChange = change
    castLoadStaleUids = exo.player.currentTimeline.periodUids()
    playerHandler.removeCallbacks(castLoadTimeoutRunnable)
    playerHandler.postDelayed(castLoadTimeoutRunnable, CAST_LOAD_TIMEOUT_MS)
}

internal fun TrackPlayerCore.clearCastLoadInFlight() {
    castLoadInFlight = false
    castLoadStaleUids = emptySet()
    castRebuildDeferred = false
    castReloadDeferred = false
    castEditRemovedUids = emptySet()
    castEditInsertCount = 0
    playerHandler.removeCallbacks(castLoadTimeoutRunnable)
}

/** While a queue change is in flight, a new target waits for its report instead of going out on a stale timeline. */
internal fun TrackPlayerCore.deferCastReload(): Boolean {
    if (!castLoadInFlight) return false
    castReloadDeferred = true
    return true
}

/** The receiver is empty, waiting on a picked track's app-supplied Cast URL. */
internal fun TrackPlayerCore.isCastWaitingOnUrl(): Boolean =
    isCastingField && suppliesCastUrls && lastCastWaitTrackId != null && isExoInitialized && exo.mediaItemCount == 0 && currentTracks.isNotEmpty()

/** A load or clear in flight, which replaces the whole receiver queue. */
internal fun TrackPlayerCore.castQueueReplaceInFlight(): Boolean = isCastingField && castLoadInFlight && castLoadChange != CastQueueChange.EDIT

/** Whether a transition to [mediaItem] is the receiver reporting the load or clear in flight (not a move on the queue it replaces). */
internal fun TrackPlayerCore.isCastLoadReport(mediaItem: MediaItem?): Boolean {
    if (castLoadChange == CastQueueChange.CLEAR) return mediaItem == null
    val timeline = exo.player.currentTimeline
    if (mediaItem == null || timeline.isEmpty) return false
    return timeline.getUidOfPeriod(exo.player.currentPeriodIndex) !in castLoadStaleUids
}

/** The receiver reported an in-flight change: send a target picked meanwhile, else apply what arrived, once. */
private fun TrackPlayerCore.finishCastChange(receiverEmpty: Boolean) {
    val change = castLoadChange
    val reload = castReloadDeferred
    val rebuild = castRebuildDeferred
    clearCastLoadInFlight()
    if (!receiverEmpty) castLoadRetried = false
    when {
        reload && currentTracks.isNotEmpty() -> rebuildQueueAndPlayFromIndex(currentTrackIndex.coerceIn(0, currentTracks.size - 1))
        // A load's report also tops the queue up (the listener skips its own top-up for it)
        change == CastQueueChange.LOAD -> rebuildQueueFromCurrentPosition()
        change == CastQueueChange.EDIT -> if (rebuild) rebuildQueueFromCurrentPosition()
        // Cleared while waiting on a track's URL: load it if the URL arrived meanwhile
        lastCastWaitTrackId != null && currentTracks.isNotEmpty() ->
            rebuildQueueAndPlayFromIndex(currentTrackIndex.coerceIn(0, currentTracks.size - 1))
    }
}

/** The receiver reported the load or clear in flight (see [isCastLoadReport]). */
internal fun TrackPlayerCore.finishCastLoad(receiverEmpty: Boolean) = finishCastChange(receiverEmpty)

/** After a batch of player events: an in-flight edit is reported once its removals are gone and its inserts are there. */
internal fun TrackPlayerCore.onCastTimelineEvents() {
    if (!isCastingField || !castLoadInFlight || castLoadChange != CastQueueChange.EDIT) return
    val uids = exo.player.currentTimeline.periodUids()
    if (uids.any { it in castEditRemovedUids }) return
    if (uids.count { it !in castLoadStaleUids } < castEditInsertCount) return
    finishCastChange(receiverEmpty = uids.isEmpty())
}

/** No report after the timeout (e.g. a rejected LOAD sends none): send the current target once more. */
internal fun TrackPlayerCore.onCastLoadTimeout() {
    if (!castLoadInFlight) return
    val change = castLoadChange
    val reload = castReloadDeferred
    val rebuild = castRebuildDeferred
    clearCastLoadInFlight()
    if (!isCastingField || !isExoInitialized || currentTracks.isEmpty()) return
    val target = currentTrackIndex.coerceIn(0, currentTracks.size - 1)
    when {
        reload -> rebuildQueueAndPlayFromIndex(target)
        // Insert or remove only: the next rebuild compares against whatever the receiver holds by then
        change == CastQueueChange.EDIT -> if (rebuild) rebuildQueueFromCurrentPosition()
        !castLoadRetried -> {
            castLoadRetried = true
            rebuildQueueAndPlayFromIndex(target)
        }
    }
}

/** Keeps the connect-time Cast queue in step with a playlist edit made while its URLs are still pending. */
internal fun TrackPlayerCore.refreshCastPendingList() {
    val head = castPendingList?.firstOrNull() ?: return
    val isTemp = currentTemporaryType != TrackPlayerCore.TemporaryType.NONE
    val removed =
        if (isTemp) (playNextStack + upNextQueue).none { it.id == head.id } else currentTracks.none { it.id == head.id }
    if (removed && !isTemp) {
        castPendingList = null
        castResume = null
        // Like a removed playing track: move on to the one that took its place
        if (currentTracks.isNotEmpty()) playFromIndexInternal(minOf(currentTrackIndex + 1, currentTracks.size - 1))
        return
    }
    if (removed) {
        // A removed temporary track: wait on what follows it instead
        castResume = null
        castPendingList = buildUpcomingQueueTracks(head.id).takeIf { it.isNotEmpty() }
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
