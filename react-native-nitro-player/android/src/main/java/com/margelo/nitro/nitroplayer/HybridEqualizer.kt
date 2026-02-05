package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.NullType
import com.margelo.nitro.nitroplayer.equalizer.EqualizerCore

@DoNotStrip
@Keep
class HybridEqualizer : HybridEqualizerSpec() {
    private val core: EqualizerCore

    init {
        val context =
            NitroModules.applicationContext ?: throw IllegalStateException("React Context is not initialized")

        // Get the equalizer core - it will initialize lazily with audio session 0
        // and be re-initialized with the proper session when onAudioSessionIdChanged fires
        core = EqualizerCore.getInstance(context)
        core.ensureInitialized()
    }

    @DoNotStrip
    @Keep
    override fun setEnabled(enabled: Boolean): Boolean = core.setEnabled(enabled)

    @DoNotStrip
    @Keep
    override fun isEnabled(): Boolean = core.isEnabled()

    @DoNotStrip
    @Keep
    override fun getBands(): Array<EqualizerBand> = core.getBands()

    @DoNotStrip
    @Keep
    override fun setBandGain(bandIndex: Double, gainDb: Double): Boolean =
        core.setBandGain(bandIndex.toInt(), gainDb)

    @DoNotStrip
    @Keep
    override fun setAllBandGains(gains: DoubleArray): Boolean = core.setAllBandGains(gains)

    @DoNotStrip
    @Keep
    override fun getBandRange(): GainRange = core.getBandRange()

    @DoNotStrip
    @Keep
    override fun getPresets(): Array<EqualizerPreset> = core.getPresets()

    @DoNotStrip
    @Keep
    override fun getBuiltInPresets(): Array<EqualizerPreset> = core.getBuiltInPresets()

    @DoNotStrip
    @Keep
    override fun getCustomPresets(): Array<EqualizerPreset> = core.getCustomPresets()

    @DoNotStrip
    @Keep
    override fun applyPreset(presetName: String): Boolean = core.applyPreset(presetName)

    @DoNotStrip
    @Keep
    override fun getCurrentPresetName(): Variant_NullType_String {
        val name = core.getCurrentPresetName()
        return if (name != null) {
            Variant_NullType_String.create(name)
        } else {
            Variant_NullType_String.create(NullType.NULL)
        }
    }

    @DoNotStrip
    @Keep
    override fun saveCustomPreset(name: String): Boolean = core.saveCustomPreset(name)

    @DoNotStrip
    @Keep
    override fun deleteCustomPreset(name: String): Boolean = core.deleteCustomPreset(name)

    @DoNotStrip
    @Keep
    override fun getState(): EqualizerState = core.getState()

    @DoNotStrip
    @Keep
    override fun reset() = core.reset()

    override fun onEnabledChange(callback: (enabled: Boolean) -> Unit) {
        core.addOnEnabledChangeListener(callback)
    }

    override fun onBandChange(callback: (bands: Array<EqualizerBand>) -> Unit) {
        core.addOnBandChangeListener(callback)
    }

    override fun onPresetChange(callback: (presetName: Variant_NullType_String?) -> Unit) {
        core.addOnPresetChangeListener(callback)
    }
}
