package com.margelo.nitro.nitroplayer

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import com.margelo.nitro.NitroModules

class HybridAudioDevices : HybridAudioDevicesSpec() {

    val applicationContext = NitroModules.applicationContext;
    private val audioManager = applicationContext?.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    
    // Device types that can be set as communication devices
    private val validCommunicationDeviceTypes: Set<Int> by lazy {
        val types = mutableSetOf(
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_USB_HEADSET
        )
        // BLE types are only available on Android S (API 31) and above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            types.add(AudioDeviceInfo.TYPE_BLE_HEADSET)
            types.add(AudioDeviceInfo.TYPE_BLE_SPEAKER)
        }
        types
    }
    
    override fun getAudioDevices(): Array<TAudioDevice> {
        val devices = audioManager.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
        var activeDevice: AudioDeviceInfo? = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            activeDevice = audioManager.communicationDevice
        }
        
        // Filter to only include valid communication devices
        return devices.filter { device ->
            validCommunicationDeviceTypes.contains(device.type)
        }.map { device -> TAudioDevice(
            id = device.id.toDouble(),
            name = device.productName?.toString() ?: getDeviceTypeName(device.type),
            type = device.type.toDouble(),
            isActive = device == activeDevice
        ) }.toTypedArray()
    }
    
    private fun getDeviceTypeName(type: Int): String {
        return when (type) {
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

    override fun setAudioDevice(deviceId: Double): Boolean {
        val device =
            audioManager.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
                .firstOrNull { it.id == deviceId.toInt() }
                ?: return false

        // Check if device type is valid for communication
        if (!validCommunicationDeviceTypes.contains(device.type)) {
            android.util.Log.w(TAG, "Device type ${device.type} is not a valid communication device")
            return false
        }

        return try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                audioManager.setCommunicationDevice(device)
            } else {
                // Pre-Android 12 fallback (best-effort)
                when (device.type) {
                    android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                    android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> {
                        audioManager.startBluetoothSco()
                        audioManager.isBluetoothScoOn = true
                        true
                    }
                    android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> {
                        audioManager.isSpeakerphoneOn = true
                        true
                    }
                    android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET,
                    android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> {
                        audioManager.isSpeakerphoneOn = false
                        audioManager.isBluetoothScoOn = false
                        true
                    }
                    else -> {
                        android.util.Log.w(TAG, "Unsupported device type for pre-Android 12: ${device.type}")
                        false
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error setting audio device: ${e.message}", e)
            false
        }
    }

    companion object {
        private const val TAG = "HybridAudioDevices"
    }
}
