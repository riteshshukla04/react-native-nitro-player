package com.margelo.nitro.nitroplayer.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.margelo.nitro.NitroModules
import com.margelo.nitro.nitroplayer.TAudioOutput
import com.margelo.nitro.nitroplayer.TAudioOutputChangeReason
import com.margelo.nitro.nitroplayer.core.ListenerRegistry
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger

/**
 * Reports which devices media plays through, and tells listeners when that changes.
 *
 * Android has no public listener for routing changes, so this re-reads the media route after devices connect or
 * disconnect, and notifies only when the outputs actually changed. A switch between two devices arrives as a
 * removal and an addition, so events are coalesced for a moment and the reason comes from what changed.
 * Observation runs on the main thread while at least one listener is registered.
 */
internal object AudioOutputMonitor {
    private const val SETTLE_MS = 300L
    private const val NOT_FOR_MEDIA = Int.MAX_VALUE

    private val listeners = ListenerRegistry<(Array<TAudioOutput>, TAudioOutputChangeReason) -> Unit>()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Main thread only
    private var lastOutputs: List<TAudioOutput> = emptyList()
    private var observing = false
    private val connectedIds = HashSet<String>()
    private val disconnectedIds = HashSet<String>()

    // Device ids (AudioDeviceInfo.id) in the order they connected, most recent last; learned while observing
    private val connectionOrder = LinkedHashSet<Int>()

    private val mediaAttributes: AudioAttributes by lazy {
        AudioAttributes
            .Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
    }

    private val readRunnable = Runnable { readOutputs() }

    private val deviceCallback =
        object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                addedDevices?.filter { it.isSink }?.forEach { device ->
                    // Registering reports the devices already connected; those aren't new
                    val isNew = synchronized(connectionOrder) { connectionOrder.add(device.id) }
                    if (isNew) connectedIds.add(device.toAudioOutput().id)
                }
                scheduleRead()
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                removedDevices?.filter { it.isSink }?.forEach { device ->
                    synchronized(connectionOrder) { connectionOrder.remove(device.id) }
                    disconnectedIds.add(device.toAudioOutput().id)
                }
                scheduleRead()
            }
        }

    /** The devices media plays through right now. */
    fun currentOutputs(): Array<TAudioOutput> =
        mediaOutputDevices(audioManager())
            .map { it.toAudioOutput() }
            .distinctBy { it.id }
            .toTypedArray()

    fun addListener(listener: (Array<TAudioOutput>, TAudioOutputChangeReason) -> Unit): Long {
        // The outputs the caller sees now: a change before observation starts on main is then still reported
        val current =
            try {
                currentOutputs().toList()
            } catch (_: Exception) {
                null
            }
        val id = listeners.add(listener)
        mainHandler.post { startObserving(current) }
        return id
    }

    fun removeListener(id: Long) {
        listeners.remove(id)
        mainHandler.post { if (listeners.isEmpty) stopObserving() }
    }

    private fun audioManager(): AudioManager {
        val context =
            NitroModules.applicationContext
                ?: throw IllegalStateException("AudioDevices: the application context isn't available yet")
        return context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    private fun mediaOutputDevices(audioManager: AudioManager): List<AudioDeviceInfo> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val routed = audioManager.getAudioDevicesForAttributes(mediaAttributes)
            if (routed.isNotEmpty()) return routed
        }
        // Android 12 and below can't be asked where media goes: infer it from the connected devices
        val candidates = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).filter { mediaRoutingRank(it.type) != NOT_FOR_MEDIA }
        if (candidates.isEmpty()) return emptyList()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11 and 12 send media to a hearing aid, else to the removable device (Bluetooth, wired, USB)
            // connected last; the order is only known for devices connected while observing
            candidates.firstOrNull { it.type == AudioDeviceInfo.TYPE_HEARING_AID }?.let { return listOf(it) }
            val order = synchronized(connectionOrder) { connectionOrder.toList() }
            val latest =
                candidates
                    .filter { mediaRoutingRank(it.type) in 1..3 && it.id in order }
                    .maxByOrNull { order.indexOf(it.id) }
            if (latest != null) return listOf(latest)
        }
        return listOf(candidates.minBy { mediaRoutingRank(it.type) })
    }

    /** Android's default media routing order (lower first), used where the order of connection isn't known. */
    private fun mediaRoutingRank(type: Int): Int =
        when (type) {
            AudioDeviceInfo.TYPE_BUS -> 0

            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_HEARING_AID,
            -> 1

            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_LINE_ANALOG,
            AudioDeviceInfo.TYPE_LINE_DIGITAL,
            -> 2

            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_ACCESSORY,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            -> 3

            AudioDeviceInfo.TYPE_DOCK,
            AudioDeviceInfo.TYPE_DOCK_ANALOG,
            AudioDeviceInfo.TYPE_AUX_LINE,
            AudioDeviceInfo.TYPE_HDMI,
            AudioDeviceInfo.TYPE_HDMI_ARC,
            AudioDeviceInfo.TYPE_HDMI_EARC,
            -> 4

            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> 5

            // Call-only paths (earpiece, Bluetooth SCO, telephony) and internal ones never carry media
            else -> NOT_FOR_MEDIA
        }

    private fun startObserving(callerOutputs: List<TAudioOutput>?) {
        if (observing || listeners.isEmpty) return
        try {
            val audioManager = audioManager()
            // What was connected before is ranked by the default order; later connections go after it
            val connected = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).sortedByDescending { mediaRoutingRank(it.type) }
            synchronized(connectionOrder) {
                connectionOrder.clear()
                connected.forEach { connectionOrder.add(it.id) }
            }
            lastOutputs = callerOutputs ?: currentOutputs().toList()
            audioManager.registerAudioDeviceCallback(deviceCallback, mainHandler)
            observing = true
            // Report a change that happened between the caller's read and now
            scheduleRead()
        } catch (e: Exception) {
            NitroPlayerLogger.log("AudioOutputMonitor") { "Can't observe audio outputs: ${e.message}" }
        }
    }

    private fun stopObserving() {
        if (!observing) return
        observing = false
        mainHandler.removeCallbacks(readRunnable)
        connectedIds.clear()
        disconnectedIds.clear()
        synchronized(connectionOrder) { connectionOrder.clear() }
        try {
            audioManager().unregisterAudioDeviceCallback(deviceCallback)
        } catch (_: Exception) {
        }
    }

    private fun scheduleRead() {
        mainHandler.removeCallbacks(readRunnable)
        mainHandler.postDelayed(readRunnable, SETTLE_MS)
    }

    private fun readOutputs() {
        val connected = connectedIds.toSet()
        val disconnected = disconnectedIds.toSet()
        connectedIds.clear()
        disconnectedIds.clear()
        val outputs =
            try {
                currentOutputs()
            } catch (e: Exception) {
                NitroPlayerLogger.log("AudioOutputMonitor") { "Can't read audio outputs: ${e.message}" }
                return
            }
        val list = outputs.toList()
        if (list == lastOutputs) return
        val previous = lastOutputs
        lastOutputs = list
        val reason =
            when {
                list.any { it.id in connected } -> TAudioOutputChangeReason.DEVICE_CONNECTED
                previous.any { it.id in disconnected } -> TAudioOutputChangeReason.DEVICE_DISCONNECTED
                else -> TAudioOutputChangeReason.ROUTE_CHANGED
            }
        NitroPlayerLogger.log("AudioOutputMonitor") { "Outputs changed (${reason.name}): ${list.joinToString { "${it.name} [${it.type.name}]" }}" }
        listeners.forEach { it(outputs, reason) }
    }
}
