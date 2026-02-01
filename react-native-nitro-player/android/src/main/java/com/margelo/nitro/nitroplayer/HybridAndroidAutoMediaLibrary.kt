package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore

@DoNotStrip
@Keep
class HybridAndroidAutoMediaLibrary : HybridAndroidAutoMediaLibrarySpec() {
    private val core: TrackPlayerCore

    init {
        val context =
            NitroModules.applicationContext
                ?: throw IllegalStateException("React Context is not initialized")
        core = TrackPlayerCore.getInstance(context)
    }

    @DoNotStrip
    @Keep
    override fun setMediaLibrary(libraryJson: String) {
        core.setAndroidAutoMediaLibrary(libraryJson)
    }

    @DoNotStrip
    @Keep
    override fun clearMediaLibrary() {
        core.clearAndroidAutoMediaLibrary()
    }
}
