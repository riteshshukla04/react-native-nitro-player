package com.margelo.nitro.nitroplayer.media

import android.content.Context
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider

/**
 * Supplies [CastOptions] used to initialize the Cast `CastContext` singleton.
 *
 * Registered via the `com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME`
 * manifest meta-data (declared in this library's AndroidManifest, merged into the
 * host app). Apps that ship their own OptionsProvider (e.g. when also using
 * react-native-google-cast) must override the meta-data with `tools:replace`.
 *
 * The receiver ID is read from [NitroCastConfig], so `Cast.configure(id)` can
 * change it before Cast is first used.
 */
class NitroCastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions =
        CastOptions.Builder()
            .setReceiverApplicationId(NitroCastConfig.effectiveReceiverId)
            // Keep the local session alive when the app is backgrounded so
            // playback control survives notification/lock-screen interaction.
            .setResumeSavedSession(true)
            .setEnableReconnectionService(true)
            .build()

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null
}
