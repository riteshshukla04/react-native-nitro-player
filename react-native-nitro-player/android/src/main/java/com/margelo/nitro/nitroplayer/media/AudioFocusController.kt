package com.margelo.nitro.nitroplayer.media

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build

/**
 * Owns audio focus for the 'duck' mode. ExoPlayer's own handling pauses on every transient
 * loss, duckable or not, which is why a notification can stop playback outright.
 */
class AudioFocusController(
    context: Context,
    private val onDuck: (Boolean) -> Unit,
    private val onPause: () -> Unit,
) {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var request: AudioFocusRequest? = null
    private var ducked = false
    private var held = false

    private val listener =
        AudioManager.OnAudioFocusChangeListener { change ->
            when (change) {
                // Another app took focus for good — stop and let it go.
                AudioManager.AUDIOFOCUS_LOSS -> {
                    setDucked(false)
                    onPause()
                    abandon()
                }

                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK,
                -> setDucked(true)

                AudioManager.AUDIOFOCUS_GAIN -> setDucked(false)
            }
        }

    private fun setDucked(next: Boolean) {
        if (ducked == next) return
        ducked = next
        onDuck(next)
    }

    /** Returns false when the system refused focus, so the caller can leave playback alone. */
    fun acquire(): Boolean {
        if (held) return true
        val attributes =
            AudioAttributes
                .Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
        val result =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val built =
                    AudioFocusRequest
                        .Builder(AudioManager.AUDIOFOCUS_GAIN)
                        .setAudioAttributes(attributes)
                        .setWillPauseWhenDucked(false)
                        .setOnAudioFocusChangeListener(listener)
                        .build()
                request = built
                audioManager.requestAudioFocus(built)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(listener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
            }
        held = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return held
    }

    fun abandon() {
        if (!held) return
        held = false
        setDucked(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            request?.let { audioManager.abandonAudioFocusRequest(it) }
            request = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(listener)
        }
    }
}
