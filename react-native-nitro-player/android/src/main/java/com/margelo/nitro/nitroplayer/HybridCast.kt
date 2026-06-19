@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.NullType
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.core.configureCast
import com.margelo.nitro.nitroplayer.core.endCastSession
import com.margelo.nitro.nitroplayer.core.getCastDeviceName
import com.margelo.nitro.nitroplayer.core.getCastState
import com.margelo.nitro.nitroplayer.core.isCasting
import com.margelo.nitro.nitroplayer.core.showCastPicker

/**
 * Nitro module exposing the Google Cast control surface to JS. Routing of actual
 * playback to/from the Cast device is handled internally by [TrackPlayerCore]
 * (see `TrackPlayerCast`); this object only forwards Cast-specific calls.
 */
@DoNotStrip
@Keep
class HybridCast : HybridCastSpec() {
    private val applicationContext = NitroModules.applicationContext
    private val core: TrackPlayerCore

    private val listenerIds = mutableListOf<Long>()

    init {
        val context =
            applicationContext
                ?: throw IllegalStateException("React Context is not initialized")
        core = TrackPlayerCore.getInstance(context)
    }

    override fun configure(receiverApplicationId: String?): Promise<Unit> =
        Promise.async { core.configureCast(receiverApplicationId) }

    override fun isCasting(): Boolean = core.isCasting()

    override fun getCastState(): CastState = core.getCastState()

    override fun getCastDeviceName(): Variant_NullType_String {
        val name = core.getCastDeviceName()
        return if (name != null) {
            Variant_NullType_String.create(name)
        } else {
            Variant_NullType_String.create(NullType.NULL)
        }
    }

    override fun showCastPicker() {
        val activity = applicationContext?.currentActivity ?: return
        activity.runOnUiThread { core.showCastPicker(activity) }
    }

    override fun endCastSession(): Promise<Unit> = Promise.async { core.endCastSession() }

    override fun onCastStateChange(callback: (state: CastState, deviceName: Variant_NullType_String?) -> Unit) {
        // Replace any prior listener registered through this HybridObject so JS
        // reloads (Fast Refresh) don't accumulate handlers.
        listenerIds.forEach { core.removeOnCastStateChangeListener(it) }
        listenerIds.clear()

        val id =
            core.addOnCastStateChangeListener { state, deviceName ->
                callback(state, deviceName?.let { Variant_NullType_String.create(it) })
            }
        listenerIds += id
    }

    override fun dispose() {
        super.dispose()
        listenerIds.forEach { core.removeOnCastStateChangeListener(it) }
        listenerIds.clear()
    }
}
