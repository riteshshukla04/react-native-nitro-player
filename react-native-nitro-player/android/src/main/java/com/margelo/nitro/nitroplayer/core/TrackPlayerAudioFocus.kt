@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.margelo.nitro.nitroplayer.AndroidAudioFocusMode
import com.margelo.nitro.nitroplayer.media.AudioFocusController

/**
 * Audio focus policy. ExoPlayer's built-in handling pauses on every transient loss — even the
 * duckable kind a notification asks for — so 'duck' and 'ignore' take focus into our own hands.
 */

internal const val DUCK_VOLUME_FACTOR = 0.2f

@OptIn(UnstableApi::class)
internal fun TrackPlayerCore.applyAudioFocusMode(mode: AndroidAudioFocusMode) {
    if (mode == audioFocusMode && (mode == AndroidAudioFocusMode.PAUSE) == (audioFocusController == null)) return
    audioFocusMode = mode

    audioFocusController?.abandon()
    audioFocusController = null
    isDucked = false

    val local = exoOrNull() ?: return
    // media3 only knows how to pause; it owns focus for the default mode and nothing else.
    local.setAudioAttributes(mediaAudioAttributes(), mode == AndroidAudioFocusMode.PAUSE)
    local.volume = userVolume

    if (mode == AndroidAudioFocusMode.DUCK) {
        audioFocusController =
            AudioFocusController(
                context,
                onDuck = { ducked -> applyDuck(ducked) },
                onPause = { playerHandler.post { pauseOnQueue() } },
            )
        if (isExoInitialized && exo.player.isPlaying) audioFocusController?.acquire()
    }
}

@OptIn(UnstableApi::class)
internal fun TrackPlayerCore.applyDuck(ducked: Boolean) {
    playerHandler.post {
        isDucked = ducked
        exoOrNull()?.volume = userVolume * if (ducked) DUCK_VOLUME_FACTOR else 1f
    }
}

private fun mediaAudioAttributes(): AudioAttributes =
    AudioAttributes
        .Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
        .build()

/** The local ExoPlayer, or null while casting (the CastPlayer has no audio focus of its own). */
@OptIn(UnstableApi::class)
internal fun TrackPlayerCore.exoOrNull(): ExoPlayer? {
    if (!isExoInitialized) return null
    return exo.player as? ExoPlayer
}
