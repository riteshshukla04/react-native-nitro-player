package com.margelo.nitro.nitroplayer.media

import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultHttpDataSource

@UnstableApi
class AuthAwareHttpDataSourceFactory : DataSource.Factory {
    private val baseFactory = DefaultHttpDataSource.Factory()
        .setAllowCrossProtocolRedirects(true)
        .setConnectTimeoutMs(15_000)
        .setReadTimeoutMs(15_000)

    override fun createDataSource(): DataSource {
        return AuthAwareHttpDataSource(baseFactory.createDataSource() as DefaultHttpDataSource)
    }

    companion object {
        private val headersMap = HashMap<String, Map<String, String>>()

        fun setHeadersForUrl(url: String, headers: Map<String, String>) {
            headersMap[url] = headers
        }

        fun getHeadersForUrl(url: String): Map<String, String>? {
            return headersMap[url]
        }

        fun clearHeaders() {
            headersMap.clear()
        }
    }
}

@UnstableApi
private class AuthAwareHttpDataSource(
    private val delegate: DefaultHttpDataSource
) : DataSource by delegate {

    override fun open(dataSpec: DataSpec): Long {
        val url = dataSpec.uri.toString()
        val extraHeaders = AuthAwareHttpDataSourceFactory.getHeadersForUrl(url)

        if (extraHeaders != null) {
            val headers = HashMap(dataSpec.httpRequestHeaders)
            headers.putAll(extraHeaders)
            val newSpec = dataSpec.buildUpon()
                .setHttpRequestHeaders(headers)
                .build()
            return delegate.open(newSpec)
        }

        return delegate.open(dataSpec)
    }
}
