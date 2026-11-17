package com.margelo.nitro.nitroplayer.audio

import android.media.AudioDeviceInfo
import android.os.Build
import com.margelo.nitro.nitroplayer.TAudioOutput
import com.margelo.nitro.nitroplayer.TAudioOutputType

/** The kind of output this device is. */
internal val AudioDeviceInfo.audioOutputType: TAudioOutputType
    get() =
        when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE,
            -> TAudioOutputType.BUILT_IN_SPEAKER

            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> TAudioOutputType.BUILT_IN_EARPIECE

            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            -> TAudioOutputType.WIRED_HEADPHONES

            AudioDeviceInfo.TYPE_LINE_ANALOG,
            AudioDeviceInfo.TYPE_LINE_DIGITAL,
            AudioDeviceInfo.TYPE_AUX_LINE,
            AudioDeviceInfo.TYPE_DOCK,
            AudioDeviceInfo.TYPE_DOCK_ANALOG,
            -> TAudioOutputType.LINE_OUT

            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
            AudioDeviceInfo.TYPE_BLE_BROADCAST,
            AudioDeviceInfo.TYPE_HEARING_AID,
            -> TAudioOutputType.BLUETOOTH

            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_ACCESSORY,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            -> TAudioOutputType.USB

            AudioDeviceInfo.TYPE_HDMI,
            AudioDeviceInfo.TYPE_HDMI_ARC,
            AudioDeviceInfo.TYPE_HDMI_EARC,
            -> TAudioOutputType.HDMI

            // Android Automotive routes all audio through the car's buses
            AudioDeviceInfo.TYPE_BUS -> TAudioOutputType.CAR_AUDIO

            else -> TAudioOutputType.UNKNOWN
        }

/**
 * This device as a [TAudioOutput]. Built-in and wired devices report the phone model as their product name,
 * so they get a generic name instead.
 */
internal fun AudioDeviceInfo.toAudioOutput(): TAudioOutput {
    val outputType = audioOutputType
    val product = productName?.toString()?.trim().orEmpty()
    val name = if (product.isEmpty() || product == Build.MODEL) outputType.genericName else product
    return TAudioOutput(id = "${outputType.name.lowercase()}:${stableKey(outputType, name)}", name = name, type = outputType)
}

/**
 * What identifies this device across reconnects. For Bluetooth, the last two octets of its address: Android 13+
 * shows apps without the Nearby devices permission only those, so the id is the same whether or not the app has
 * it. Everything else, USB included (its address is just the sound card slot), is identified by its name.
 */
private fun AudioDeviceInfo.stableKey(
    outputType: TAudioOutputType,
    name: String,
): String {
    if (outputType != TAudioOutputType.BLUETOOTH || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return name
    val octets = address?.trim()?.split(':')?.takeIf { it.size == 6 && it.all { octet -> octet.length == 2 } } ?: return name
    return "${octets[4]}:${octets[5]}".uppercase()
}

private val TAudioOutputType.genericName: String
    get() =
        when (this) {
            TAudioOutputType.BUILT_IN_SPEAKER -> "Speaker"
            TAudioOutputType.BUILT_IN_EARPIECE -> "Earpiece"
            TAudioOutputType.WIRED_HEADPHONES -> "Headphones"
            TAudioOutputType.LINE_OUT -> "Line Out"
            TAudioOutputType.BLUETOOTH -> "Bluetooth"
            TAudioOutputType.USB -> "USB Audio"
            TAudioOutputType.AIRPLAY -> "AirPlay"
            TAudioOutputType.CAR_AUDIO -> "Car Audio"
            TAudioOutputType.HDMI -> "HDMI"
            TAudioOutputType.UNKNOWN -> "Audio Output"
        }
