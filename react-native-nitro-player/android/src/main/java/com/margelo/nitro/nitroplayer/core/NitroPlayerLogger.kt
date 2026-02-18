package com.margelo.nitro.nitroplayer.core

import android.util.Log
import com.margelo.nitro.nitroplayer.BuildConfig

object NitroPlayerLogger {
    // Determine if logging is enabled based on build config
    val isEnabled: Boolean = BuildConfig.DEBUG

    fun log(
        header: String = "NitroPlayer",
        message: String,
    ) {
        if (isEnabled) {
            Log.d(header, message)
        }
    }
}
