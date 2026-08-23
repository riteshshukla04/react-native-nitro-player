package com.margelo.nitro.nitroplayer.media

import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource

/**
 * HTTP [DataSource.Factory] that injects per-URL request headers (e.g. `Authorization`)
 * into ExoPlayer's HTTP requests, enabling playback from authenticated endpoints.
 *
 * Headers are registered per effective URL via [setHeadersForUrl] during MediaItem
 * construction and applied through a [ResolvingDataSource] just before each request opens.
 *
 * The registry is a [ConcurrentHashMap] because it is written on the player thread but
 * read on ExoPlayer's loader threads.
 */
@UnstableApi
class AuthAwareHttpDataSourceFactory : DataSource.Factory {
    private val factory =
        ResolvingDataSource.Factory(
            DefaultHttpDataSource
                .Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15_000)
                .setReadTimeoutMs(15_000),
            ResolvingDataSource.Resolver { dataSpec ->
                val headers = headersMap[dataSpec.uri.toString()]
                if (headers.isNullOrEmpty()) dataSpec else dataSpec.withAdditionalHeaders(headers)
            },
        )

    override fun createDataSource(): DataSource = factory.createDataSource()

    companion object {
        // LRU-bounded: rotating signed URLs would otherwise add an entry per
        // playback for the process lifetime (destroy() has no callers today)
        private const val MAX_HEADER_ENTRIES = 500

        private val headersMap: MutableMap<String, Map<String, String>> =
            java.util.Collections.synchronizedMap(
                object : LinkedHashMap<String, Map<String, String>>(16, 0.75f, true) {
                    override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Map<String, String>>) =
                        size > MAX_HEADER_ENTRIES
                },
            )

        fun setHeadersForUrl(url: String, headers: Map<String, String>) {
            headersMap[url] = headers
        }

        /** Releases all registered headers. Call when the player is torn down. */
        fun clear() {
            headersMap.clear()
        }
    }
}
