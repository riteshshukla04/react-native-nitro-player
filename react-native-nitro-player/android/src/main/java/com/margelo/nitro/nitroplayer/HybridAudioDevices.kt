@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger

@DoNotStrip
@Keep
class HybridAudioDevices : HybridAudioDevicesSpec() {
    val applicationContext = NitroModules.applicationContext
    private val audioManager = applicationContext?.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val validCommunicationDeviceTypes: Set<Int> by lazy {
        val types =
            mutableSetOf(
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_USB_HEADSET,
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            types.add(AudioDeviceInfo.TYPE_BLE_HEADSET)
            types.add(AudioDeviceInfo.TYPE_BLE_SPEAKER)
        }
        types
    }

    override fun getAudioDevices(): Array<TAudioDevice> {
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val activeDevice: AudioDeviceInfo? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) audioManager.communicationDevice else null
        return devices
            .filter { validCommunicationDeviceTypes.contains(it.type) }
            .map { device ->
                TAudioDevice(
                    id = device.id.toDouble(),
                    name = device.productName?.toString() ?: getDeviceTypeName(device.type),
                    type = device.type.toDouble(),
                    isActive = device == activeDevice,
                )
            }.toTypedArray()
    }

    /** v2: setAudioDevice now returns Promise<Unit> instead of Boolean */
    override fun setAudioDevice(deviceId: Double): Promise<Unit> =
        Promise.async {
            val device =
                audioManager
                    .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    .firstOrNull { it.id == deviceId.toInt() }
                    ?: throw IllegalArgumentException("Audio device $deviceId not found")
            if (!validCommunicationDeviceTypes.contains(device.type)) {
                throw IllegalArgumentException("Device type ${device.type} is not a valid communication device")
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    audioManager.setCommunicationDevice(device)
                } else {
                    when (device.type) {
                        AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> {
                            audioManager.startBluetoothSco()
                            audioManager.isBluetoothScoOn = true
                        }

                        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> {
                            audioManager.isSpeakerphoneOn = true
                        }

                        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> {
                            audioManager.isSpeakerphoneOn = false
                            audioManager.isBluetoothScoOn = false
                        }

                        else -> {
                            throw IllegalArgumentException("Unsupported device type for pre-Android 12: ${device.type}")
                        }
                    }
                }
            } catch (e: Exception) {
                NitroPlayerLogger.log("HybridAudioDevices", "Error setting audio device: ${e.message}")
                throw e
            }
        }

    private fun getDeviceTypeName(type: Int): String =
        when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Built-in Earpiece"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Built-in Speaker"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired Headphones"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth SCO"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "USB Headset"
            26 -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) "BLE Headset" else "Type 26"
            27 -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) "BLE Speaker" else "Type 27"
            else -> "Type $type"
        }
}
