package com.margelo.nitro.nitroplayer.media

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer

/**
 * Builds an [ExoPlayer] with the standard NitroPlayer configuration.
 * The player uses the main application looper so that Media3's
 * [MediaSessionService] notification system works without thread conflicts.
 */
object ExoPlayerBuilder {
    fun build(context: Context): ExoPlayer {
        val loadControl =
            DefaultLoadControl
                .Builder()
                .setBufferDurationsMs(
                    // minBufferMs
                    30_000,
                    // maxBufferMs
                    120_000,
                    // bufferForPlayback
                    2_500,
                    // bufferForRebuffer
                    5_000,
                ).setBackBuffer(30_000, /* retainBackBufferFromKeyframe */ true)
                .setTargetBufferBytes(C.LENGTH_UNSET)
                .setPrioritizeTimeOverSizeThresholds(true)
                .build()

        val audioAttrs =
            AudioAttributes
                .Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .build()

        return ExoPlayer
            .Builder(context)
            .setLoadControl(loadControl)
            .setAudioAttributes(audioAttrs, /* handleAudioFocus */ true)
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setPauseAtEndOfMediaItems(false)
            .build()
    }
}
