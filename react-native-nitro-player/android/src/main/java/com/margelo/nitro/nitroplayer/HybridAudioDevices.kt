package com.margelo.nitro.nitroplayer

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import com.margelo.nitro.NitroModules

class HybridAudioDevices : HybridAudioDevicesSpec() {

    val applicationContext = NitroModules.applicationContext;
    private val audioManager = applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    override fun getAudioDevices(): TAudioDevice {
        val devices = audioManager.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
        var activeDevice: AudioDeviceInfo? = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            activeDevice = audioManager.communicationDevice
        }
        devices.map { device -> TAudioDevice(
            id = device.id.toDouble(),
            name = device.productName?.toString() ?: device.type.toString(),
            type = device.type.toDouble(),
            isActive = device == activeDevice
        ) }
    }

    override fun setAudioDevice(deviceId: Double): Boolean {
        val device =
            audioManager.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
                .firstOrNull { it.id == deviceId.toInt() }
                ?: return false

        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            audioManager.setCommunicationDevice(device)
        } else {
            // Pre-Android 12 fallback (best-effort)
            when (device.type) {
                android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> {
                    audioManager.startBluetoothSco()
                    audioManager.isBluetoothScoOn = true
                    true
                }
                android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> {
                    audioManager.isSpeakerphoneOn = true
                    true
                }
                else -> false
            }
        }
    }
}
