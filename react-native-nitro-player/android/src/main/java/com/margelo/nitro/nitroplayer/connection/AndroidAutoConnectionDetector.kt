package com.margelo.nitro.nitroplayer.connection

import android.content.AsyncQueryHandler
import android.content.BroadcastReceiver
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.util.Log
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger

/**
 * Detects Android Auto connection status using the official Android for Cars API
 * Based on: https://developer.android.com/training/cars/apps#car-connection
 * Source: https://stackoverflow.com/a (CC BY-SA 4.0)
 */
class AndroidAutoConnectionDetector(
    private val context: Context,
) {
    companion object {
        private const val TAG = "AndroidAutoConnection"

        // Column name for provider to query on connection status
        private const val CAR_CONNECTION_STATE = "CarConnectionState"

        // Android Auto app will send broadcast with this action when connection state changes
        private const val ACTION_CAR_CONNECTION_UPDATED = "androidx.car.app.connection.action.CAR_CONNECTION_UPDATED"

        // Connection types
        const val CONNECTION_TYPE_NOT_CONNECTED = 0
        const val CONNECTION_TYPE_NATIVE = 1 // Connected to Automotive OS
        const val CONNECTION_TYPE_PROJECTION = 2 // Connected to Android Auto

        private const val QUERY_TOKEN = 42
        private const val CAR_CONNECTION_AUTHORITY = "androidx.car.app.connection"
        private val PROJECTION_HOST_URI =
            Uri
                .Builder()
                .scheme("content")
                .authority(CAR_CONNECTION_AUTHORITY)
                .build()
    }

    private val carConnectionReceiver = CarConnectionBroadcastReceiver()
    private val carConnectionQueryHandler = CarConnectionQueryHandler(context.contentResolver)

    var onConnectionChanged: ((Boolean, Int) -> Unit)? = null
    private var isRegistered = false

    fun registerCarConnectionReceiver() {
        if (isRegistered) {
            NitroPlayerLogger.log("AndroidAutoConnection", "Receiver already registered")
            return
        }

        try {
            val filter = IntentFilter(ACTION_CAR_CONNECTION_UPDATED)

            // For Android 14+ (API 34+), we need to specify the receiver flags
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                context.registerReceiver(carConnectionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(carConnectionReceiver, filter)
            }

            isRegistered = true
            NitroPlayerLogger.log("AndroidAutoConnection", "✅ Car connection receiver registered")

            // Query initial state
            queryForState()
        } catch (e: Exception) {
            NitroPlayerLogger.log("AndroidAutoConnection", "❌ Error registering car connection receiver: ${e.message}")
            e.printStackTrace()
        }
    }

    fun unregisterCarConnectionReceiver() {
        if (!isRegistered) {
            return
        }

        try {
            context.unregisterReceiver(carConnectionReceiver)
            isRegistered = false
            NitroPlayerLogger.log("AndroidAutoConnection", "🛑 Car connection receiver unregistered")
        } catch (e: Exception) {
            NitroPlayerLogger.log("AndroidAutoConnection", "❌ Error unregistering car connection receiver: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun queryForState() {
        try {
            carConnectionQueryHandler.startQuery(
                QUERY_TOKEN,
                null,
                PROJECTION_HOST_URI,
                arrayOf(CAR_CONNECTION_STATE),
                null,
                null,
                null,
            )
        } catch (e: Exception) {
            NitroPlayerLogger.log("AndroidAutoConnection", "❌ Error querying car connection state: ${e.message}")
            e.printStackTrace()
            notifyCarDisconnected()
        }
    }

    private fun notifyCarConnected(connectionType: Int) {
        NitroPlayerLogger.log("AndroidAutoConnection", "🚗 Android Auto CONNECTED (type: $connectionType)")
        onConnectionChanged?.invoke(true, connectionType)
    }

    private fun notifyCarDisconnected() {
        NitroPlayerLogger.log("AndroidAutoConnection", "📱 Android Auto DISCONNECTED")
        onConnectionChanged?.invoke(false, CONNECTION_TYPE_NOT_CONNECTED)
    }

    inner class CarConnectionBroadcastReceiver : BroadcastReceiver() {
        override fun onReceive(
            context: Context?,
            intent: Intent?,
        ) {
            NitroPlayerLogger.log("AndroidAutoConnection", "🔔 Car connection broadcast received")
            queryForState()
        }
    }

    inner class CarConnectionQueryHandler(
        resolver: ContentResolver?,
    ) : AsyncQueryHandler(resolver) {
        override fun onQueryComplete(
            token: Int,
            cookie: Any?,
            response: Cursor?,
        ) {
            if (response == null) {
                NitroPlayerLogger.log("AndroidAutoConnection", "⚠️ Null response from content provider, treating as disconnected")
                notifyCarDisconnected()
                return
            }

            val carConnectionTypeColumn = response.getColumnIndex(CAR_CONNECTION_STATE)
            if (carConnectionTypeColumn < 0) {
                NitroPlayerLogger.log("AndroidAutoConnection", "⚠️ Connection type column missing, treating as disconnected")
                notifyCarDisconnected()
                return
            }

            if (!response.moveToNext()) {
                NitroPlayerLogger.log("AndroidAutoConnection", "⚠️ Empty response, treating as disconnected")
                notifyCarDisconnected()
                return
            }

            val connectionState = response.getInt(carConnectionTypeColumn)
            NitroPlayerLogger.log("AndroidAutoConnection", "📊 Connection state queried: $connectionState")

            if (connectionState == CONNECTION_TYPE_NOT_CONNECTED) {
                notifyCarDisconnected()
            } else {
                notifyCarConnected(connectionState)
            }

            response.close()
        }
    }
}
