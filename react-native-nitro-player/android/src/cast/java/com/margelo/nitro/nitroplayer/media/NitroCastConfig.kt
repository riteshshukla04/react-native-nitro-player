package com.margelo.nitro.nitroplayer.media

import com.google.android.gms.cast.CastMediaControlIntent

/**
 * Process-wide Google Cast configuration.
 *
 * The Cast receiver application ID must be known *before* `CastContext` is
 * initialized (it is a singleton, fixed for the process lifetime). Callers set
 * [receiverApplicationId] via `Cast.configure(...)` as early as possible; the
 * [NitroCastOptionsProvider] reads it at init time. When unset, the platform
 * Default Media Receiver is used, which supports audio playback, metadata and
 * queues out of the box.
 */
object NitroCastConfig {
    @Volatile
    var receiverApplicationId: String? = null

    /** The effective receiver ID, falling back to the Default Media Receiver. */
    val effectiveReceiverId: String
        get() = receiverApplicationId
            ?: CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID
}
