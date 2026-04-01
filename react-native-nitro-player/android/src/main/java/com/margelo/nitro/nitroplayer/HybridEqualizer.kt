package com.margelo.nitro.nitroplayer

import androidx.annotation.Keep
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.NullType
import com.margelo.nitro.core.Promise
import com.margelo.nitro.nitroplayer.equalizer.EqualizerCore

@DoNotStrip
@Keep
class HybridEqualizer : HybridEqualizerSpec() {
    private val core: EqualizerCore

    init {
        val context =
            NitroModules.applicationContext
                ?: throw IllegalStateException("React Context is not initialized")
        core = EqualizerCore.getInstance(context)
        core.ensureInitialized()
    }

    // ── Sync reads ────────────────────────────────────────────────────────────
    override fun isEnabled(): Boolean = core.isEnabled()

    override fun getBandRange(): GainRange = core.getBandRange()

    override fun getPresets(): Array<EqualizerPreset> = core.getPresets()

    override fun getBuiltInPresets(): Array<EqualizerPreset> = core.getBuiltInPresets()

    override fun getCustomPresets(): Array<EqualizerPreset> = core.getCustomPresets()

    override fun getCurrentPresetName(): Variant_NullType_String {
        val name = core.getCurrentPresetName()
        return if (name != null) {
            Variant_NullType_String.create(name)
        } else {
            Variant_NullType_String.create(NullType.NULL)
        }
    }

    // ── Async mutations (per v2 spec) ─────────────────────────────────────────
    override fun setEnabled(enabled: Boolean): Promise<Unit> = Promise.async { core.setEnabled(enabled) }

    override fun getBands(): Promise<Array<EqualizerBand>> = Promise.async { core.getBands() }

    override fun setBandGain(
        bandIndex: Double,
        gainDb: Double,
    ): Promise<Unit> = Promise.async { core.setBandGain(bandIndex.toInt(), gainDb) }

    override fun setAllBandGains(gains: DoubleArray): Promise<Unit> = Promise.async { core.setAllBandGains(gains) }

    override fun applyPreset(presetName: String): Promise<Unit> = Promise.async { core.applyPreset(presetName) }

    override fun saveCustomPreset(name: String): Promise<Unit> = Promise.async { core.saveCustomPreset(name) }

    override fun deleteCustomPreset(name: String): Promise<Unit> = Promise.async { core.deleteCustomPreset(name) }

    override fun getState(): Promise<EqualizerState> = Promise.async { core.getState() }

    override fun reset(): Promise<Unit> = Promise.async { core.reset() }

    // ── Events ────────────────────────────────────────────────────────────────
    override fun onEnabledChange(callback: (enabled: Boolean) -> Unit) = core.addOnEnabledChangeListener(callback)

    override fun onBandChange(callback: (bands: Array<EqualizerBand>) -> Unit) = core.addOnBandChangeListener(callback)

    override fun onPresetChange(callback: (presetName: Variant_NullType_String?) -> Unit) = core.addOnPresetChangeListener(callback)
}
