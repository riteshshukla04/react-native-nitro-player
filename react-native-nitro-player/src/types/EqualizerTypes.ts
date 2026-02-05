/**
 * Represents a single equalizer frequency band
 */
export interface EqualizerBand {
  /** Band index (0-4) */
  index: number
  /** Center frequency in Hz */
  centerFrequency: number
  /** Current gain in dB (-12 to +12) */
  gainDb: number
  /** Human-readable frequency label (e.g., "60 Hz", "3.6 kHz") */
  frequencyLabel: string
}

/**
 * Preset type identifier
 */
export type PresetType = 'built-in' | 'custom'

/**
 * Represents an equalizer preset (built-in or custom)
 */
export interface EqualizerPreset {
  /** Unique preset name */
  name: string
  /** Array of 5 gain values in dB for each band */
  gains: number[]
  /** Whether this is a built-in or custom preset */
  type: PresetType
}

/**
 * Complete equalizer state
 */
export interface EqualizerState {
  /** Whether equalizer is enabled */
  enabled: boolean
  /** Current band settings */
  bands: EqualizerBand[]
  /** Currently applied preset name (null if custom values) */
  currentPreset: string | null
}

/**
 * Gain range for equalizer bands
 */
export interface GainRange {
  /** Minimum gain in dB */
  min: number
  /** Maximum gain in dB */
  max: number
}

/**
 * Built-in preset names
 */
export type BuiltInPresetName =
  | 'Flat'
  | 'Bass Boost'
  | 'Bass Reducer'
  | 'Treble Boost'
  | 'Treble Reducer'
  | 'Vocal Boost'
  | 'Rock'
  | 'Pop'
  | 'Jazz'
  | 'Classical'
  | 'Hip Hop'
  | 'Electronic'
  | 'Acoustic'
  | 'R&B'
  | 'Loudness'
