package com.margelo.nitro.nitroplayer.media

import androidx.media3.cast.DefaultMediaItemConverter
import androidx.media3.cast.MediaItemConverter
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import com.google.android.gms.cast.MediaQueueItem

/**
 * [MediaItemConverter] for [androidx.media3.cast.CastPlayer].
 *
 * The library builds [MediaItem]s with a URI + metadata but **no MIME type**
 * (local ExoPlayer infers it from the stream, and forcing one would risk picking
 * the wrong extractor). The Cast SDK's [DefaultMediaItemConverter] however throws
 * when the MIME type is missing, so this converter infers a sensible content type
 * from the URL before delegating. Local playback is untouched — this only runs
 * for items sent to a Cast device.
 */
@UnstableApi
class NitroMediaItemConverter : MediaItemConverter {
    private val delegate = DefaultMediaItemConverter()

    override fun toMediaItem(mediaQueueItem: MediaQueueItem): MediaItem =
        delegate.toMediaItem(mediaQueueItem)

    override fun toMediaQueueItem(mediaItem: MediaItem): MediaQueueItem =
        delegate.toMediaQueueItem(ensureMimeType(mediaItem))

    private fun ensureMimeType(mediaItem: MediaItem): MediaItem {
        val config = mediaItem.localConfiguration ?: return mediaItem
        if (config.mimeType != null) return mediaItem
        return mediaItem
            .buildUpon()
            .setMimeType(inferMimeType(config.uri.toString()))
            .build()
    }

    /** Best-effort content type the Cast receiver can load; defaults to MP3 audio. */
    private fun inferMimeType(url: String): String {
        val path = url.substringBefore('?').substringBefore('#').lowercase()
        return when {
            path.endsWith(".m3u8") -> "application/x-mpegurl"
            path.endsWith(".mpd") -> "application/dash+xml"
            path.endsWith(".flac") -> "audio/flac"
            path.endsWith(".wav") -> "audio/wav"
            path.endsWith(".opus") -> "audio/opus"
            path.endsWith(".ogg") -> "audio/ogg"
            path.endsWith(".aac") -> "audio/aac"
            path.endsWith(".m4a") || path.endsWith(".mp4") -> "audio/mp4"
            else -> "audio/mpeg"
        }
    }
}
