package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.core.clearAndroidAutoMediaLibrary
import com.margelo.nitro.nitroplayer.core.setAndroidAutoMediaLibrary
import com.margelo.nitro.nitroplayer.media.MediaSessionManager
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService
import org.json.JSONArray

@DoNotStrip
@Keep
@UnstableApi
class HybridAndroidAutoMediaLibrary : HybridAndroidAutoMediaLibrarySpec() {
    private val core: TrackPlayerCore

    init {
        val context =
            NitroModules.applicationContext
                ?: throw IllegalStateException("React Context is not initialized")
        core = TrackPlayerCore.getInstance(context)
    }

    override fun setMediaLibrary(libraryJson: String): Promise<Unit> = Promise.async { core.setAndroidAutoMediaLibrary(libraryJson) }

    override fun clearMediaLibrary(): Promise<Unit> = Promise.async { core.clearAndroidAutoMediaLibrary() }

    override fun onLoadChildren(callback: (requestId: String, parentId: String) -> Unit) {
        core.mediaLibraryManager.childrenRequester = callback
    }

    override fun onSearch(callback: (requestId: String, query: String) -> Unit) {
        core.mediaLibraryManager.searchRequester = callback
        NitroPlayerMediaBrowserService.setSearchSupported(core.context, true)
    }

    override fun resolveRequest(
        requestId: String,
        itemsJson: String,
    ) = core.mediaLibraryManager.resolve(requestId, itemsJson)

    override fun setSessionButtons(buttonsJson: String) {
        val array = JSONArray(buttonsJson)
        val buttons =
            (0 until array.length()).mapNotNull { i ->
                val button = array.getJSONObject(i)
                val icon = ICONS[button.optString("icon")] ?: return@mapNotNull null
                MediaSessionManager.SessionButton(button.getString("action"), button.optString("title"), icon)
            }
        core.enqueue { core.mediaSessionManager?.setSessionButtons(buttons) }
    }

    override fun onSessionButtonPress(callback: (action: String) -> Unit) {
        core.enqueue { core.mediaSessionManager?.onSessionButtonPress = callback }
    }

    override fun onPlaybackResumption(callback: () -> Unit) = core.mediaLibraryManager.setResumptionRequester(callback)

    private companion object {
        val ICONS =
            mapOf(
                "heart" to CommandButton.ICON_HEART_UNFILLED,
                "heart_filled" to CommandButton.ICON_HEART_FILLED,
                "star" to CommandButton.ICON_STAR_UNFILLED,
                "star_filled" to CommandButton.ICON_STAR_FILLED,
                "thumb_up" to CommandButton.ICON_THUMB_UP_UNFILLED,
                "thumb_up_filled" to CommandButton.ICON_THUMB_UP_FILLED,
                "plus" to CommandButton.ICON_PLUS,
                "check" to CommandButton.ICON_CHECK_CIRCLE_FILLED,
            )
    }
}
