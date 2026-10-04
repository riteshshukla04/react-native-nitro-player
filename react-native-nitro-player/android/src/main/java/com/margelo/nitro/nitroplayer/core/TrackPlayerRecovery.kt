@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import com.margelo.nitro.nitroplayer.Reason
import com.margelo.nitro.nitroplayer.TrackPlayerState

// Lost network waits for connectivity and retries the same item; bad sources skip, capped so an unplayable queue stops

internal const val MAX_CONSECUTIVE_SOURCE_ERRORS = 3

internal fun TrackPlayerCore.handlePlayerError(error: PlaybackException) {
    NitroPlayerLogger.log("TrackPlayer") { "Player error: ${error.errorCodeName} - ${error.message}" }
    // Still waiting for its URL: updateTracks re-prepares it, skipping would cascade through the window
    if (getCurrentTrack()?.url?.isEmpty() == true) {
        checkUpcomingTracksForUrls(lookaheadCount, force = true)
        return
    }
    notifyPlaybackStateChange(TrackPlayerState.STOPPED, Reason.ERROR)
    if (error.isConnectivityError() && !isNetworkValidated()) {
        awaitNetworkThenRetry()
        return
    }
    consecutiveSourceErrors++
    if (consecutiveSourceErrors >= MAX_CONSECUTIVE_SOURCE_ERRORS) return
    // A source error leaves ExoPlayer in IDLE; skip the dead item and re-prepare so the rest of the queue keeps playing
    if (!exo.hasNextMediaItem()) rebuildQueueFromCurrentPosition()
    if (exo.hasNextMediaItem()) {
        exo.seekToNext()
        exo.prepare()
    }
}

/** Called when playback actually starts, so earlier failures stop counting against the queue. */
internal fun TrackPlayerCore.onPlaybackHealthy() {
    consecutiveSourceErrors = 0
}

private fun PlaybackException.isConnectivityError(): Boolean =
    errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
        errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT

private fun TrackPlayerCore.connectivity(): ConnectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

internal fun TrackPlayerCore.isNetworkValidated(): Boolean {
    val manager = connectivity()
    val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
    return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
}

/** Retries once the network is back; [afterLoss] first waits for it to drop, for work started while it was up. */
internal fun TrackPlayerCore.awaitNetworkThenRetry(afterLoss: Boolean = false) {
    if (networkRetryCallback != null) return
    val callback =
        object : ConnectivityManager.NetworkCallback() {
            private var lost = !afterLoss
            private var seen: Network? = null

            override fun onLost(network: Network) {
                lost = true
            }

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) {
                // Switching networks (Wi-Fi to mobile) breaks requests in flight just like a drop
                if (seen != null && seen != network) lost = true
                seen = network
                if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
                    lost = true
                } else if (lost) {
                    enqueue { retryAfterNetwork(this) }
                }
            }
        }
    networkRetryCallback = callback
    connectivity().registerDefaultNetworkCallback(callback)
}

private fun TrackPlayerCore.retryAfterNetwork(callback: ConnectivityManager.NetworkCallback) {
    if (networkRetryCallback !== callback) return
    networkRetryCallback = null
    try {
        connectivity().unregisterNetworkCallback(callback)
    } catch (_: IllegalArgumentException) {
    }
    // URLs the app could not fetch offline are asked for again; a failed item is retried only if nothing replaced it
    checkUpcomingTracksForUrls(lookaheadCount, force = true)
    if (exo.playbackState == Player.STATE_IDLE && exo.player.playerError != null) exo.prepare()
}
