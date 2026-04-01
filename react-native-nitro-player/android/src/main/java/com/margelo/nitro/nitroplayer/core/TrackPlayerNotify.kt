package com.margelo.nitro.nitroplayer.core

import com.margelo.nitro.nitroplayer.Reason
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.TrackPlayerState

/**
 * Notification helpers — call the registered ListenerRegistry callbacks.
 * All methods must be called from the player thread (already serialised).
 */

internal fun TrackPlayerCore.notifyTrackChange(
    track: TrackItem,
    reason: Reason?,
) {
    onChangeTrackListeners.forEach { it(track, reason) }
}

internal fun TrackPlayerCore.notifyPlaybackStateChange(
    state: TrackPlayerState,
    reason: Reason?,
) {
    onPlaybackStateChangeListeners.forEach { it(state, reason) }
}

internal fun TrackPlayerCore.notifySeek(
    position: Double,
    duration: Double,
) {
    onSeekListeners.forEach { it(position, duration) }
}

internal fun TrackPlayerCore.notifyPlaybackProgress(
    position: Double,
    duration: Double,
    isManuallySeeked: Boolean?,
) {
    onProgressListeners.forEach { it(position, duration, isManuallySeeked) }
}

internal fun TrackPlayerCore.notifyTracksNeedUpdate(
    tracks: List<TrackItem>,
    lookahead: Int,
) {
    onTracksNeedUpdateListeners.forEach { it(tracks, lookahead) }
}

internal fun TrackPlayerCore.notifyTemporaryQueueChange() {
    val pn = playNextStack.toList()
    val un = upNextQueue.toList()
    onTemporaryQueueChangeListeners.forEach { it(pn, un) }
}

internal fun TrackPlayerCore.notifyAndroidAutoConnection(connected: Boolean) {
    onAndroidAutoConnectionListeners.forEach { it(connected) }
}
