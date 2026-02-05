package com.margelo.nitro.nitroplayer.equalizer

import android.content.Context
import android.content.SharedPreferences
import android.media.audiofx.Equalizer
import com.margelo.nitro.core.NullType
import com.margelo.nitro.nitroplayer.EqualizerBand
import com.margelo.nitro.nitroplayer.EqualizerPreset
import com.margelo.nitro.nitroplayer.EqualizerState
import com.margelo.nitro.nitroplayer.GainRange
import com.margelo.nitro.nitroplayer.PresetType
import com.margelo.nitro.nitroplayer.Variant_NullType_String
import org.json.JSONArray
import org.json.JSONObject
import android.util.Log
import java.lang.ref.WeakReference
import java.util.Collections

class EqualizerCore private constructor(private val context: Context) {
    private var equalizer: Equalizer? = null
    private var audioSessionId: Int = 0
    private var isUsingFallbackSession: Boolean = false // Track if using fallback session 0
    private var isEqualizerEnabled: Boolean = false
    private var currentPresetName: String? = null

    // Standard 5-band frequencies: 60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz
    private val targetFrequencies = intArrayOf(60000, 230000, 910000, 3600000, 14000000) // milliHz
    private val frequencyLabels = arrayOf("60 Hz", "230 Hz", "910 Hz", "3.6 kHz", "14 kHz")
    private val frequencies = intArrayOf(60, 230, 910, 3600, 14000)
    private var bandMapping = IntArray(5) // Maps our 5 bands to actual EQ bands

    private val prefs: SharedPreferences =
        context.getSharedPreferences("equalizer_settings", Context.MODE_PRIVATE)

    // Weak callback wrapper for auto-cleanup
    private data class WeakCallbackBox<T>(
        private val ownerRef: WeakReference<Any>,
        val callback: T,
    ) {
        val isAlive: Boolean get() = ownerRef.get() != null
    }

    // Event listeners
    private val onEnabledChangeListeners =
        Collections.synchronizedList(mutableListOf<WeakCallbackBox<(Boolean) -> Unit>>())
    private val onBandChangeListeners =
        Collections.synchronizedList(mutableListOf<WeakCallbackBox<(Array<EqualizerBand>) -> Unit>>())
    private val onPresetChangeListeners =
        Collections.synchronizedList(mutableListOf<WeakCallbackBox<(Variant_NullType_String?) -> Unit>>())

    companion object {
        private const val TAG = "EqualizerCore"
        
        @Volatile
        private var INSTANCE: EqualizerCore? = null

        fun getInstance(context: Context): EqualizerCore =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: EqualizerCore(context).also { INSTANCE = it }
            }

        // Built-in presets: name -> [60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz] in dB
        private val BUILT_IN_PRESETS = mapOf(
            "Flat" to doubleArrayOf(0.0, 0.0, 0.0, 0.0, 0.0),
            "Bass Boost" to doubleArrayOf(6.0, 4.0, 0.0, 0.0, 0.0),
            "Bass Reducer" to doubleArrayOf(-6.0, -4.0, 0.0, 0.0, 0.0),
            "Treble Boost" to doubleArrayOf(0.0, 0.0, 0.0, 4.0, 6.0),
            "Treble Reducer" to doubleArrayOf(0.0, 0.0, 0.0, -4.0, -6.0),
            "Vocal Boost" to doubleArrayOf(-2.0, 0.0, 4.0, 2.0, 0.0),
            "Rock" to doubleArrayOf(5.0, 3.0, -1.0, 3.0, 5.0),
            "Pop" to doubleArrayOf(-1.0, 2.0, 4.0, 2.0, -1.0),
            "Jazz" to doubleArrayOf(3.0, 1.0, -2.0, 2.0, 4.0),
            "Classical" to doubleArrayOf(4.0, 2.0, -1.0, 2.0, 3.0),
            "Hip Hop" to doubleArrayOf(6.0, 4.0, 0.0, 1.0, 3.0),
            "Electronic" to doubleArrayOf(5.0, 3.0, 0.0, 2.0, 5.0),
            "Acoustic" to doubleArrayOf(4.0, 2.0, 1.0, 3.0, 3.0),
            "R&B" to doubleArrayOf(3.0, 6.0, 2.0, -1.0, 2.0),
            "Loudness" to doubleArrayOf(6.0, 3.0, -1.0, 3.0, 6.0),
        )
    }

    /**
     * Initialize equalizer with audio session from ExoPlayer
     * Must be called after TrackPlayerCore is initialized
     */
    fun initialize(audioSessionId: Int) {
        this.audioSessionId = audioSessionId
        this.isUsingFallbackSession = (audioSessionId == 0)

        try {
            equalizer?.release()
            equalizer = Equalizer(0, audioSessionId).apply {
                enabled = false
            }
            setupBandMapping()
            restoreSettings()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize equalizer: ${e.message}")
        }
    }

    /**
     * Ensure equalizer is initialized, using audio session 0 (global output mix) if needed
     * This allows the equalizer to work even before TrackPlayer is used
     */
    fun ensureInitialized() {
        if (equalizer == null) {
            initialize(0)
        }
    }

    
    private fun setupBandMapping() {
        val eq = equalizer ?: return
        val numBands = eq.numberOfBands.toInt()

        // Map each target frequency to the closest available band
        for (i in targetFrequencies.indices) {
            var closestBand = 0
            var closestDiff = Int.MAX_VALUE

            for (band in 0 until numBands) {
                val bandFreq = eq.getCenterFreq(band.toShort())
                val diff = kotlin.math.abs(bandFreq - targetFrequencies[i])
                if (diff < closestDiff) {
                    closestDiff = diff
                    closestBand = band
                }
            }
            bandMapping[i] = closestBand
        }
    }

    fun setEnabled(enabled: Boolean): Boolean {
        val eq = equalizer ?: return false

        return try {
            eq.enabled = enabled
            isEqualizerEnabled = enabled
            notifyEnabledChange(enabled)
            saveEnabled(enabled)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set enabled: ${e.message}")
            false
        }
    }

    fun isEnabled(): Boolean = isEqualizerEnabled

    fun getBands(): Array<EqualizerBand> {
        val eq = equalizer ?: return emptyArray()

        return (0 until 5).map { i ->
            val actualBand = bandMapping[i].toShort()
            val gainMb = try {
                eq.getBandLevel(actualBand)
            } catch (e: Exception) {
                0.toShort()
            }
            val gainDb = gainMb / 100.0 // convert millibels to dB

            EqualizerBand(
                index = i.toDouble(),
                centerFrequency = frequencies[i].toDouble(),
                gainDb = gainDb,
                frequencyLabel = frequencyLabels[i]
            )
        }.toTypedArray()
    }

    fun setBandGain(bandIndex: Int, gainDb: Double): Boolean {
        if (bandIndex !in 0..4) return false

        val eq = equalizer ?: return false
        val clampedGain = gainDb.coerceIn(-12.0, 12.0)
        val gainMb = (clampedGain * 100).toInt().toShort() // convert dB to millibels

        return try {
            eq.setBandLevel(bandMapping[bandIndex].toShort(), gainMb)
            currentPresetName = null // Custom settings
            notifyBandChange(getBands())
            notifyPresetChange(null)
            saveBandGains(getAllGains())
            saveCurrentPreset(null)
            true
        } catch (e: Exception) {
            false
        }
    }

    fun setAllBandGains(gains: DoubleArray): Boolean {
        if (gains.size != 5) return false

        val eq = equalizer ?: return false

        return try {
            gains.forEachIndexed { i, gain ->
                val clampedGain = gain.coerceIn(-12.0, 12.0)
                val gainMb = (clampedGain * 100).toInt().toShort()
                eq.setBandLevel(bandMapping[i].toShort(), gainMb)
            }
            notifyBandChange(getBands())
            saveBandGains(gains.toList())
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun getAllGains(): List<Double> {
        val eq = equalizer ?: return listOf(0.0, 0.0, 0.0, 0.0, 0.0)
        return (0 until 5).map { i ->
            try {
                eq.getBandLevel(bandMapping[i].toShort()) / 100.0
            } catch (e: Exception) {
                0.0
            }
        }
    }

    fun getBandRange(): GainRange {
        val eq = equalizer
        return if (eq != null) {
            val range = eq.bandLevelRange
            GainRange(
                min = (range[0] / 100.0).coerceAtLeast(-12.0),
                max = (range[1] / 100.0).coerceAtMost(12.0)
            )
        } else {
            GainRange(min = -12.0, max = 12.0)
        }
    }

    fun getPresets(): Array<EqualizerPreset> {
        val builtIn = getBuiltInPresets()
        val custom = getCustomPresets()
        return builtIn + custom
    }

    fun getBuiltInPresets(): Array<EqualizerPreset> {
        return BUILT_IN_PRESETS.map { (name, gains) ->
            EqualizerPreset(
                name = name,
                gains = gains,
                type = PresetType.BUILT_IN
            )
        }.toTypedArray()
    }

    fun getCustomPresets(): Array<EqualizerPreset> {
        val customPresetsJson = prefs.getString("custom_presets", null) ?: return emptyArray()
        return try {
            val json = JSONObject(customPresetsJson)
            json.keys().asSequence().map { name ->
                val gainsArray = json.getJSONArray(name)
                val gains = DoubleArray(5) { gainsArray.getDouble(it) }
                EqualizerPreset(
                    name = name,
                    gains = gains,
                    type = PresetType.CUSTOM
                )
            }.toList().toTypedArray()
        } catch (e: Exception) {
            emptyArray()
        }
    }

    fun applyPreset(presetName: String): Boolean {
        // Try built-in preset first
        val gains = BUILT_IN_PRESETS[presetName]
            ?: getCustomPresetGains(presetName)
            ?: return false

        if (setAllBandGains(gains)) {
            currentPresetName = presetName
            notifyPresetChange(presetName)
            saveCurrentPreset(presetName)
            return true
        }
        return false
    }

    private fun getCustomPresetGains(name: String): DoubleArray? {
        val customPresetsJson = prefs.getString("custom_presets", null) ?: return null
        return try {
            val json = JSONObject(customPresetsJson)
            if (json.has(name)) {
                val gainsArray = json.getJSONArray(name)
                DoubleArray(5) { gainsArray.getDouble(it) }
            } else null
        } catch (e: Exception) {
            null
        }
    }

    fun getCurrentPresetName(): String? = currentPresetName

    fun saveCustomPreset(name: String): Boolean {
        return try {
            val currentGains = getAllGains()
            val customPresetsJson = prefs.getString("custom_presets", null)
            val json = if (customPresetsJson != null) JSONObject(customPresetsJson) else JSONObject()

            val gainsArray = JSONArray()
            currentGains.forEach { gainsArray.put(it) }
            json.put(name, gainsArray)

            prefs.edit().putString("custom_presets", json.toString()).apply()
            currentPresetName = name
            notifyPresetChange(name)
            saveCurrentPreset(name)
            true
        } catch (e: Exception) {
            false
        }
    }

    fun deleteCustomPreset(name: String): Boolean {
        return try {
            val customPresetsJson = prefs.getString("custom_presets", null) ?: return false
            val json = JSONObject(customPresetsJson)

            if (json.has(name)) {
                json.remove(name)
                prefs.edit().putString("custom_presets", json.toString()).apply()

                if (currentPresetName == name) {
                    currentPresetName = null
                    notifyPresetChange(null)
                    saveCurrentPreset(null)
                }
                return true
            }
            false
        } catch (e: Exception) {
            false
        }
    }

    fun getState(): EqualizerState {
        return EqualizerState(
            enabled = isEqualizerEnabled,
            bands = getBands(),
            currentPreset = currentPresetName?.let { Variant_NullType_String.create(it) }
                ?: Variant_NullType_String.create(NullType.NULL)
        )
    }

    fun reset() {
        setAllBandGains(doubleArrayOf(0.0, 0.0, 0.0, 0.0, 0.0))
        currentPresetName = "Flat"
        notifyPresetChange("Flat")
        saveCurrentPreset("Flat")
    }

    // === Persistence ===

    private fun saveEnabled(enabled: Boolean) {
        prefs.edit().putBoolean("eq_enabled", enabled).apply()
    }

    private fun saveBandGains(gains: List<Double>) {
        val json = JSONArray()
        gains.forEach { json.put(it) }
        prefs.edit().putString("eq_band_gains", json.toString()).apply()
    }

    private fun saveCurrentPreset(name: String?) {
        if (name != null) {
            prefs.edit().putString("eq_current_preset", name).apply()
        } else {
            prefs.edit().remove("eq_current_preset").apply()
        }
    }

    private fun restoreSettings() {
        val enabled = prefs.getBoolean("eq_enabled", false)
        val gainsJson = prefs.getString("eq_band_gains", null)
        val presetName = prefs.getString("eq_current_preset", null)

        if (gainsJson != null) {
            try {
                val arr = JSONArray(gainsJson)
                val gains = DoubleArray(5) { arr.getDouble(it) }
                setAllBandGains(gains)
            } catch (e: Exception) {
                // Ignore
            }
        }

        currentPresetName = presetName
        isEqualizerEnabled = enabled

        try {
            equalizer?.enabled = enabled
        } catch (e: Exception) {
            // Ignore
        }
    }

    // === Callback management ===

    fun addOnEnabledChangeListener(callback: (Boolean) -> Unit) {
        val box = WeakCallbackBox(WeakReference(callback as Any), callback)
        onEnabledChangeListeners.add(box)
    }

    fun addOnBandChangeListener(callback: (Array<EqualizerBand>) -> Unit) {
        val box = WeakCallbackBox(WeakReference(callback as Any), callback)
        synchronized(onBandChangeListeners) {
            @Suppress("UNCHECKED_CAST")
            (onBandChangeListeners as MutableList<WeakCallbackBox<(Array<EqualizerBand>) -> Unit>>).add(box)
        }
    }

    fun addOnPresetChangeListener(callback: (Variant_NullType_String?) -> Unit) {
        val box = WeakCallbackBox(WeakReference(callback as Any), callback)
        onPresetChangeListeners.add(box)
    }

    private fun notifyEnabledChange(enabled: Boolean) {
        synchronized(onEnabledChangeListeners) {
            onEnabledChangeListeners.removeAll { !it.isAlive }
            onEnabledChangeListeners.forEach { box ->
                try {
                    box.callback(enabled)
                } catch (e: Exception) {
                    // Ignore callback errors
                }
            }
        }
    }

    private fun notifyBandChange(bands: Array<EqualizerBand>) {
        synchronized(onBandChangeListeners) {
            @Suppress("UNCHECKED_CAST")
            val listeners = onBandChangeListeners as MutableList<WeakCallbackBox<(Array<EqualizerBand>) -> Unit>>
            listeners.removeAll { !it.isAlive }
            listeners.forEach { box ->
                try {
                    box.callback(bands)
                } catch (e: Exception) {
                    // Ignore callback errors
                }
            }
        }
    }

    private fun notifyPresetChange(presetName: String?) {
        synchronized(onPresetChangeListeners) {
            onPresetChangeListeners.removeAll { !it.isAlive }
            onPresetChangeListeners.forEach { box ->
                try {
                    val variant = presetName?.let { Variant_NullType_String.create(it) }
                    box.callback(variant)
                } catch (e: Exception) {
                    // Ignore callback errors
                }
            }
        }
    }

    fun release() {
        try {
            equalizer?.release()
            equalizer = null
        } catch (e: Exception) {
            // Ignore
        }
    }
}
