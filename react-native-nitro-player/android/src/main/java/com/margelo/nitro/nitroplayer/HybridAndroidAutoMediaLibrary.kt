package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.core.clearAndroidAutoMediaLibrary
import com.margelo.nitro.nitroplayer.core.setAndroidAutoMediaLibrary

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

    override fun setMediaLibrary(libraryJson: String): Promise<Unit> = Promise.async { core.setAndroidAutoMediaLibrary(libraryJson) }

    override fun clearMediaLibrary(): Promise<Unit> = Promise.async { core.clearAndroidAutoMediaLibrary() }
}
