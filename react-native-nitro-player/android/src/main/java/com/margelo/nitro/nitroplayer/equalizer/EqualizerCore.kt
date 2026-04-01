package com.margelo.nitro.nitroplayer.equalizer

import android.content.Context
import android.content.SharedPreferences
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.os.Build
import androidx.annotation.RequiresApi
import com.margelo.nitro.core.NullType
import com.margelo.nitro.nitroplayer.EqualizerBand
import com.margelo.nitro.nitroplayer.EqualizerPreset
import com.margelo.nitro.nitroplayer.EqualizerState
import com.margelo.nitro.nitroplayer.GainRange
import com.margelo.nitro.nitroplayer.PresetType
import com.margelo.nitro.nitroplayer.Variant_NullType_String
import com.margelo.nitro.nitroplayer.core.ListenerRegistry
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger
import org.json.JSONArray
import org.json.JSONObject

class EqualizerCore private constructor(
    private val context: Context,
) {
    private var equalizer: Equalizer? = null
    private var dynamicsProcessing: DynamicsProcessing? = null
    private var usingDynamicsProcessing: Boolean = false
    private var audioSessionId: Int = 0
    private var isUsingFallbackSession: Boolean = false // Track if using fallback session 0
    private var isEqualizerEnabled: Boolean = false
    private var currentPresetName: String? = null

    // Standard 10-band frequencies: 31Hz, 63Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz
    private val targetFrequencies = intArrayOf(31000, 63000, 125000, 250000, 500000, 1000000, 2000000, 4000000, 8000000, 16000000) // milliHz
    private val frequencyLabels = arrayOf("31 Hz", "63 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz")
    private val frequencies = intArrayOf(31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)
    private var bandMapping = IntArray(10) // Maps our 10 bands to actual EQ bands (fallback only)
    private val currentGainsArray = DoubleArray(10) { 0.0 } // Local gain cache (both DP and fallback paths)

    private val prefs: SharedPreferences =
        context.getSharedPreferences("equalizer_settings", Context.MODE_PRIVATE)

    // Event listeners
    private val onEnabledChangeListeners = ListenerRegistry<(Boolean) -> Unit>()
    private val onBandChangeListeners = ListenerRegistry<(Array<EqualizerBand>) -> Unit>()
    private val onPresetChangeListeners = ListenerRegistry<(Variant_NullType_String?) -> Unit>()

    companion object {
        private const val TAG = "EqualizerCore"

        @Volatile
        private var INSTANCE: EqualizerCore? = null

        fun getInstance(context: Context): EqualizerCore =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: EqualizerCore(context).also { INSTANCE = it }
            }

        // Built-in presets: name -> [31Hz, 63Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz] in dB
        private val BUILT_IN_PRESETS =
            mapOf(
                "Flat" to doubleArrayOf(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
                "Rock" to doubleArrayOf(4.8, 2.88, -3.36, -4.8, -1.92, 2.4, 5.28, 6.72, 6.72, 6.72),
                "Pop" to doubleArrayOf(0.96, 2.88, 4.32, 4.8, 3.36, 0.0, -1.44, -1.44, 0.96, 0.96),
                "Classical" to doubleArrayOf(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -4.32, -4.32, -4.32, -5.76),
                "Dance" to doubleArrayOf(5.76, 4.32, 1.44, 0.0, 0.0, -3.36, -4.32, -4.32, 0.0, 0.0),
                "Techno" to doubleArrayOf(4.8, 3.36, 0.0, -3.36, -2.88, 0.0, 4.8, 5.76, 5.76, 5.28),
                "Club" to doubleArrayOf(0.0, 0.0, 4.8, 3.36, 3.36, 3.36, 1.92, 0.0, 0.0, 0.0),
                "Live" to doubleArrayOf(-2.88, 0.0, 2.4, 3.36, 3.36, 3.36, 2.4, 1.44, 1.44, 1.44),
                "Reggae" to doubleArrayOf(0.0, 0.0, 0.0, -3.36, 0.0, 3.84, 3.84, 0.0, 0.0, 0.0),
                "Full Bass" to doubleArrayOf(4.8, 5.76, 5.76, 3.36, 0.96, -2.4, -4.8, -6.24, -6.72, -6.72),
                "Full Treble" to doubleArrayOf(-5.76, -5.76, -5.76, -2.4, 1.44, 6.72, 9.6, 9.6, 9.6, 10.08),
                "Full Bass & Treble" to doubleArrayOf(4.32, 3.36, 0.0, -4.32, -2.88, 0.96, 4.8, 6.72, 7.2, 7.2),
                "Large Hall" to doubleArrayOf(6.24, 6.24, 3.36, 3.36, 0.0, -2.88, -2.88, -2.88, 0.0, 0.0),
                "Party" to doubleArrayOf(4.32, 4.32, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 4.32, 4.32),
                "Ska" to doubleArrayOf(-1.44, -2.88, -2.4, 0.0, 2.4, 3.36, 5.28, 5.76, 6.72, 5.76),
                "Soft" to doubleArrayOf(2.88, 0.96, 0.0, -1.44, 0.0, 2.4, 4.8, 5.76, 6.72, 7.2),
                "Soft Rock" to doubleArrayOf(2.4, 2.4, 1.44, 0.0, -2.4, -3.36, -1.92, 0.0, 1.44, 5.28),
                "Headphones" to doubleArrayOf(2.88, 6.72, 3.36, -1.92, -1.44, 0.96, 2.88, 5.76, 7.68, 8.64),
                "Laptop Speakers" to doubleArrayOf(2.88, 6.72, 3.36, -1.92, -1.44, 0.96, 2.88, 5.76, 7.68, 8.64),
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
            releaseAudioEffects()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                initDynamicsProcessing(audioSessionId)
                usingDynamicsProcessing = true
            } else {
                equalizer =
                    Equalizer(0, audioSessionId).apply {
                        enabled = false
                    }
                usingDynamicsProcessing = false
                setupBandMapping()
            }
            restoreSettings()
        } catch (e: Exception) {
            NitroPlayerLogger.log("EqualizerCore", "Failed to initialize equalizer: ${e.message}")
        }
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun initDynamicsProcessing(sessionId: Int) {
        val config =
            DynamicsProcessing.Config
                .Builder(
                    DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                    1, // channelCount (stereo handled internally)
                    true,
                    10, // Pre-EQ enabled, 10 bands
                    false,
                    0, // MBC disabled
                    false,
                    0, // Post-EQ disabled
                    false, // Limiter disabled
                ).build()
        dynamicsProcessing = DynamicsProcessing(0, sessionId, config).apply { enabled = false }
        for (i in 0 until 10) {
            val band = DynamicsProcessing.EqBand(true, frequencies[i].toFloat(), 0f)
            dynamicsProcessing!!.setPreEqBandAllChannelsTo(i, band)
        }
    }

    /**
     * Ensure equalizer is initialized, using audio session 0 (global output mix) if needed
     * This allows the equalizer to work even before TrackPlayer is used
     */
    fun ensureInitialized() {
        if (equalizer == null && dynamicsProcessing == null) {
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

    fun setEnabled(enabled: Boolean): Boolean =
        try {
            if (usingDynamicsProcessing && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dynamicsProcessing?.enabled = enabled
            } else {
                equalizer?.enabled = enabled
            }
            isEqualizerEnabled = enabled
            notifyEnabledChange(enabled)
            saveEnabled(enabled)
            true
        } catch (e: Exception) {
            NitroPlayerLogger.log("EqualizerCore", "Failed to set enabled: ${e.message}")
            false
        }

    fun isEnabled(): Boolean = isEqualizerEnabled

    fun getBands(): Array<EqualizerBand> =
        (0 until 10)
            .map { i ->
                val gainDb = getCurrentBandGain(i)
                EqualizerBand(
                    index = i.toDouble(),
                    centerFrequency = frequencies[i].toDouble(),
                    gainDb = gainDb,
                    frequencyLabel = frequencyLabels[i],
                )
            }.toTypedArray()

    private fun getCurrentBandGain(bandIndex: Int): Double = currentGainsArray[bandIndex]

    fun setBandGain(
        bandIndex: Int,
        gainDb: Double,
    ): Boolean {
        if (bandIndex !in 0..9) return false

        val clampedGain = gainDb.coerceIn(-12.0, 12.0)

        return try {
            currentGainsArray[bandIndex] = clampedGain
            if (usingDynamicsProcessing && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                setDPBandGain(bandIndex, clampedGain.toFloat())
            } else {
                val eq = equalizer ?: return false
                val gainMb = (clampedGain * 100).toInt().toShort()
                eq.setBandLevel(bandMapping[bandIndex].toShort(), gainMb)
            }
            currentPresetName = null
            notifyBandChange(getBands())
            notifyPresetChange(null)
            saveBandGainsAndPreset(getAllGains(), null)
            true
        } catch (e: Exception) {
            false
        }
    }

    @RequiresApi(Build.VERSION_CODES.P)
    private fun setDPBandGain(
        bandIndex: Int,
        gainDb: Float,
    ) {
        val band = DynamicsProcessing.EqBand(true, frequencies[bandIndex].toFloat(), gainDb)
        dynamicsProcessing?.setPreEqBandAllChannelsTo(bandIndex, band)
    }

    fun setAllBandGains(gains: DoubleArray): Boolean {
        if (gains.size != 10) return false

        return try {
            if (usingDynamicsProcessing && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                gains.forEachIndexed { i, gain ->
                    val clampedGain = gain.coerceIn(-12.0, 12.0)
                    currentGainsArray[i] = clampedGain
                    setDPBandGain(i, clampedGain.toFloat())
                }
            } else {
                val eq = equalizer ?: return false
                gains.forEachIndexed { i, gain ->
                    val clampedGain = gain.coerceIn(-12.0, 12.0)
                    currentGainsArray[i] = clampedGain
                    val gainMb = (clampedGain * 100).toInt().toShort()
                    eq.setBandLevel(bandMapping[i].toShort(), gainMb)
                }
            }
            notifyBandChange(getBands())
            saveBandGains(gains.toList())
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun getAllGains(): List<Double> = (0 until 10).map { i -> getCurrentBandGain(i) }

    fun getBandRange(): GainRange =
        if (usingDynamicsProcessing) {
            GainRange(min = -12.0, max = 12.0)
        } else {
            val eq = equalizer
            if (eq != null) {
                val range = eq.bandLevelRange
                GainRange(
                    min = (range[0] / 100.0).coerceAtLeast(-12.0),
                    max = (range[1] / 100.0).coerceAtMost(12.0),
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

    fun getBuiltInPresets(): Array<EqualizerPreset> =
        BUILT_IN_PRESETS
            .map { (name, gains) ->
                EqualizerPreset(
                    name = name,
                    gains = gains,
                    type = PresetType.BUILT_IN,
                )
            }.toTypedArray()

    fun getCustomPresets(): Array<EqualizerPreset> {
        val customPresetsJson = prefs.getString("custom_presets", null) ?: return emptyArray()
        return try {
            val json = JSONObject(customPresetsJson)
            json
                .keys()
                .asSequence()
                .map { name ->
                    val gainsArray = json.getJSONArray(name)
                    val gains = DoubleArray(gainsArray.length()) { gainsArray.getDouble(it) }
                    EqualizerPreset(
                        name = name,
                        gains = gains,
                        type = PresetType.CUSTOM,
                    )
                }.toList()
                .toTypedArray()
        } catch (e: Exception) {
            emptyArray()
        }
    }

    fun applyPreset(presetName: String): Boolean {
        // Try built-in preset first
        val gains =
            BUILT_IN_PRESETS[presetName]
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
                DoubleArray(gainsArray.length()) { gainsArray.getDouble(it) }
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    fun getCurrentPresetName(): String? = currentPresetName

    fun saveCustomPreset(name: String): Boolean =
        try {
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

    fun getState(): EqualizerState =
        EqualizerState(
            enabled = isEqualizerEnabled,
            bands = getBands(),
            currentPreset =
                currentPresetName?.let { Variant_NullType_String.create(it) }
                    ?: Variant_NullType_String.create(NullType.NULL),
        )

    fun reset() {
        setAllBandGains(DoubleArray(10) { 0.0 })
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

    private fun saveBandGainsAndPreset(
        gains: List<Double>,
        presetName: String?,
    ) {
        val json = JSONArray()
        gains.forEach { json.put(it) }
        prefs
            .edit()
            .apply {
                putString("eq_band_gains", json.toString())
                if (presetName != null) {
                    putString("eq_current_preset", presetName)
                } else {
                    remove("eq_current_preset")
                }
            }.apply()
    }

    private fun restoreSettings() {
        val enabled = prefs.getBoolean("eq_enabled", false)
        val gainsJson = prefs.getString("eq_band_gains", null)
        val presetName = prefs.getString("eq_current_preset", null)

        if (gainsJson != null) {
            try {
                val arr = JSONArray(gainsJson)
                // Migration: if saved array length != 10, skip (5-band data incompatible)
                if (arr.length() == 10) {
                    val gains = DoubleArray(10) { arr.getDouble(it) }
                    setAllBandGains(gains)
                }
                // else: start at flat (migration from 5-band)
            } catch (e: Exception) {
                // Ignore
            }
        }

        currentPresetName = presetName
        isEqualizerEnabled = enabled

        try {
            if (usingDynamicsProcessing && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dynamicsProcessing?.enabled = enabled
            } else {
                equalizer?.enabled = enabled
            }
        } catch (e: Exception) {
            // Ignore
        }
    }

    // === Callback management ===

    fun addOnEnabledChangeListener(callback: (Boolean) -> Unit) {
        onEnabledChangeListeners.add(callback)
    }

    fun addOnBandChangeListener(callback: (Array<EqualizerBand>) -> Unit) {
        onBandChangeListeners.add(callback)
    }

    fun addOnPresetChangeListener(callback: (Variant_NullType_String?) -> Unit) {
        onPresetChangeListeners.add(callback)
    }

    private fun notifyEnabledChange(enabled: Boolean) {
        onEnabledChangeListeners.forEach { it(enabled) }
    }

    private fun notifyBandChange(bands: Array<EqualizerBand>) {
        onBandChangeListeners.forEach { it(bands) }
    }

    private fun notifyPresetChange(presetName: String?) {
        val variant = presetName?.let { Variant_NullType_String.create(it) }
        onPresetChangeListeners.forEach { it(variant) }
    }

    private fun releaseAudioEffects() {
        try {
            equalizer?.release()
            equalizer = null
        } catch (e: Exception) {
            // Ignore
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                dynamicsProcessing?.release()
                dynamicsProcessing = null
            } catch (e: Exception) {
                // Ignore
            }
        }
    }

    fun release() {
        releaseAudioEffects()
    }
}
