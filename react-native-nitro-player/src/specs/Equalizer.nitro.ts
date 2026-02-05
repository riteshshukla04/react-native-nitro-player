import type { HybridObject } from 'react-native-nitro-modules'
import type {
  EqualizerBand,
  EqualizerPreset,
  EqualizerState,
  GainRange,
} from '../types/EqualizerTypes'

export interface Equalizer
  extends HybridObject<{ android: 'kotlin'; ios: 'swift' }> {
  // === Enable/Disable ===
  /** Enable or disable the equalizer */
  setEnabled(enabled: boolean): boolean

  /** Check if equalizer is currently enabled */
  isEnabled(): boolean

  // === Band Control ===
  /** Get all equalizer bands with current gain values */
  getBands(): EqualizerBand[]

  /** Set gain for a specific band index (-12 to +12 dB) */
  setBandGain(bandIndex: number, gainDb: number): boolean

  /** Set gains for all bands at once (array of 5 values) */
  setAllBandGains(gains: number[]): boolean

  /** Get the valid gain range for bands */
  getBandRange(): GainRange

  // === Presets ===
  /** Get all available presets (built-in + custom) */
  getPresets(): EqualizerPreset[]

  /** Get built-in presets only */
  getBuiltInPresets(): EqualizerPreset[]

  /** Get custom user presets only */
  getCustomPresets(): EqualizerPreset[]

  /** Apply a preset by name */
  applyPreset(presetName: string): boolean

  /** Get currently applied preset name (null if custom values) */
  getCurrentPresetName(): string | null

  /** Save current settings as a custom preset */
  saveCustomPreset(name: string): boolean

  /** Delete a custom preset by name */
  deleteCustomPreset(name: string): boolean

  // === State ===
  /** Get complete equalizer state */
  getState(): EqualizerState

  /** Reset to flat response (all bands at 0 dB) */
  reset(): void

  // === Events ===
  /** Called when equalizer enabled state changes */
  onEnabledChange(callback: (enabled: boolean) => void): void

  /** Called when any band gain changes */
  onBandChange(callback: (bands: EqualizerBand[]) => void): void

  /** Called when preset changes */
  onPresetChange(callback: (presetName: string | null) => void): void
}
