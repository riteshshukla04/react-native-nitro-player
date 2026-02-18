package com.margelo.nitro.nitroplayer.core

import android.util.Log
import com.margelo.nitro.nitroplayer.BuildConfig

object NitroPlayerLogger {
    // Determine if logging is enabled based on build config
    val isEnabled: Boolean = BuildConfig.DEBUG

    /**
     * Preferred overload: message lambda is only evaluated when logging is enabled.
     * Use trailing lambda syntax: NitroPlayerLogger.log("Tag") { "msg $value" }
     * The lambda is inlined (no heap allocation) and skipped entirely when disabled.
     */
    inline fun log(header: String = "NitroPlayer", message: () -> String) {
        if (isEnabled) {
            Log.d(header, message())
        }
    }

    /**
     * Compatibility overload for existing call sites.
     * Note: the String is evaluated at the call site before this function runs.
     * Migrate to the lambda overload for hot paths.
     */
    fun log(header: String = "NitroPlayer", message: String) {
        if (isEnabled) {
            Log.d(header, message)
        }
    }
}
