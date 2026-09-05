import { describe, it, expect, beforeAll, beforeEach, afterEach } from 'react-native-harness';
import { Equalizer } from 'react-native-nitro-player';

describe('Equalizer', () => {
  const wait = (ms = 300) => new Promise<void>(resolve => setTimeout(resolve, ms));
  const CUSTOM_PRESET = 'Harness Custom Preset';

  const deleteCustomPresetIfPresent = async (name: string) => {
    if (Equalizer.getCustomPresets().some(p => p.name === name)) {
      await Equalizer.deleteCustomPreset(name);
    }
  };

  // The first bridge call after app launch can be dropped while the runtime is still settling,
  // so make that throwaway call here rather than inside a test.
  beforeAll(async () => {
    try {
      await Equalizer.getBands();
    } catch {
      await Equalizer.getBands();
    }
  });

  beforeEach(async () => {
    await Equalizer.reset();
    await Equalizer.setEnabled(false);
    await deleteCustomPresetIfPresent(CUSTOM_PRESET);
  });

  afterEach(async () => {
    await deleteCustomPresetIfPresent(CUSTOM_PRESET);
    await Equalizer.reset();
    await Equalizer.setEnabled(false);
  });

  describe('Enabling', () => {
    it('should report the enabled state it was set to', async () => {
      await Equalizer.setEnabled(true);
      expect(Equalizer.isEnabled()).toBe(true);

      await Equalizer.setEnabled(false);
      expect(Equalizer.isEnabled()).toBe(false);
    });

    it('should notify listeners when the enabled state changes', async () => {
      const seen: boolean[] = [];
      Equalizer.onEnabledChange(enabled => {
        seen.push(enabled);
      });
      await wait();

      await Equalizer.setEnabled(true);
      await wait();

      expect(seen).toContain(true);
    });
  });

  describe('Bands', () => {
    it('should expose one band per gain slot with ascending frequencies', async () => {
      const bands = await Equalizer.getBands();

      expect(bands.length > 0).toBe(true);
      expect(bands.map(b => b.index)).toStrictEqual(bands.map((_, i) => i));
      for (let i = 1; i < bands.length; i++) {
        expect(bands[i].centerFrequency > bands[i - 1].centerFrequency).toBe(true);
      }
    });

    it('should apply a gain to a single band and leave the others alone', async () => {
      const before = await Equalizer.getBands();
      const target = Math.min(3, before.length - 1);

      await Equalizer.setBandGain(target, 6);
      const after = await Equalizer.getBands();

      expect(Math.abs(after[target].gainDb - 6) < 0.5).toBe(true);
      for (let i = 0; i < after.length; i++) {
        if (i !== target) {
          expect(Math.abs(after[i].gainDb - before[i].gainDb) < 0.5).toBe(true);
        }
      }
    });

    it('should apply every gain at once', async () => {
      const bands = await Equalizer.getBands();
      const gains = bands.map((_, i) => (i % 2 === 0 ? 3 : -3));

      await Equalizer.setAllBandGains(gains);
      const after = await Equalizer.getBands();

      after.forEach((band, i) => {
        expect(Math.abs(band.gainDb - gains[i]) < 0.5).toBe(true);
      });
    });

    it('should keep every band gain inside the reported range', async () => {
      const range = Equalizer.getBandRange();
      expect(range.max > range.min).toBe(true);

      // Ask for more than the device allows; it must clamp rather than drift out of range.
      await Equalizer.setBandGain(0, range.max + 20);
      const clamped = (await Equalizer.getBands())[0].gainDb;

      expect(clamped <= range.max).toBe(true);
      expect(clamped >= range.min).toBe(true);
    });

    it('should notify listeners when a band changes', async () => {
      const seen: number[] = [];
      Equalizer.onBandChange(bands => {
        seen.push(bands[0].gainDb);
      });
      await wait();

      await Equalizer.setBandGain(0, 5);
      await wait();

      expect(seen.length > 0).toBe(true);
    });

    it('should return every band to zero on reset', async () => {
      await Equalizer.setAllBandGains((await Equalizer.getBands()).map(() => 8));

      await Equalizer.reset();

      const bands = await Equalizer.getBands();
      bands.forEach(band => {
        expect(Math.abs(band.gainDb) < 0.5).toBe(true);
      });
    });
  });

  describe('Presets', () => {
    it('should list built-in presets as part of all presets', () => {
      const builtIn = Equalizer.getBuiltInPresets();
      const all = Equalizer.getPresets().map(p => p.name);

      expect(builtIn.length > 0).toBe(true);
      builtIn.forEach(preset => {
        expect(all).toContain(preset.name);
      });
    });

    it('should apply a built-in preset and report it as current', async () => {
      const preset = Equalizer.getBuiltInPresets().find(p => p.gains.some(g => g !== 0));
      if (!preset) return;

      await Equalizer.applyPreset(preset.name);

      expect(Equalizer.getCurrentPresetName()).toBe(preset.name);
      const bands = await Equalizer.getBands();
      bands.forEach((band, i) => {
        expect(Math.abs(band.gainDb - preset.gains[i]) < 0.5).toBe(true);
      });
    });

    it('should save the current gains as a custom preset and restore them', async () => {
      const bands = await Equalizer.getBands();
      const gains = bands.map((_, i) => (i === 0 ? 7 : 0));
      await Equalizer.setAllBandGains(gains);

      await Equalizer.saveCustomPreset(CUSTOM_PRESET);

      const saved = Equalizer.getCustomPresets().find(p => p.name === CUSTOM_PRESET);
      expect(saved?.gains[0]).toBe(7);

      await Equalizer.reset();
      await Equalizer.applyPreset(CUSTOM_PRESET);

      expect(Math.abs((await Equalizer.getBands())[0].gainDb - 7) < 0.5).toBe(true);
    });

    it('should drop a deleted custom preset from the list', async () => {
      await Equalizer.saveCustomPreset(CUSTOM_PRESET);
      expect(Equalizer.getCustomPresets().map(p => p.name)).toContain(CUSTOM_PRESET);

      await Equalizer.deleteCustomPreset(CUSTOM_PRESET);

      expect(Equalizer.getCustomPresets().map(p => p.name)).not.toContain(CUSTOM_PRESET);
    });

    it('should notify listeners when a preset is applied', async () => {
      const preset = Equalizer.getBuiltInPresets()[0];
      const seen: (string | null)[] = [];
      Equalizer.onPresetChange(name => {
        seen.push(name);
      });
      await wait();

      await Equalizer.applyPreset(preset.name);
      await wait();

      expect(seen).toContain(preset.name);
    });
  });

  describe('State', () => {
    it('should report enabled state, bands and preset together', async () => {
      const preset = Equalizer.getBuiltInPresets()[0];
      await Equalizer.setEnabled(true);
      await Equalizer.applyPreset(preset.name);

      const state = await Equalizer.getState();

      expect(state.enabled).toBe(true);
      expect(state.currentPreset).toBe(preset.name);
      expect(state.bands.map(b => b.gainDb)).toStrictEqual(
        (await Equalizer.getBands()).map(b => b.gainDb)
      );
    });
  });
});
