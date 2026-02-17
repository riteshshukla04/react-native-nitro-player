---
sidebar_position: 5
sidebar_label: '🎛️ Equalizer'
tags: [android, ios]
---

# Equalizer

<span className="badge badge--success">Android</span> <span className="badge badge--secondary">iOS</span>

The `Equalizer` object provides access to the 5-band internal equalizer.

## Methods

### `setEnabled(enabled)`
Enables or disables the equalizer.
- **enabled**: `boolean`

```typescript
Equalizer.setEnabled(true)
```

### `isEnabled()`
Returns the current enabled state.
- **Returns**: `boolean`

```typescript
const isEnabled = Equalizer.isEnabled()
```

### `getBands()`
Returns the current gain settings for all 5 bands.
- **Returns**: [`EqualizerBand[]`](#equalizerband)

```typescript
const bands = Equalizer.getBands()
```

### `setBandGain(index, gainDb)`
Sets the gain for a specific band (range: -12dB to +12dB).
- **index**: `number`
- **gainDb**: `number`

```typescript
Equalizer.setBandGain(0, 5.0) // Boost bass by 5dB
```

### `setAllBandGains(gains)`
Sets all band gains at once.
- **gains**: `number[]`

```typescript
Equalizer.setAllBandGains([0, 2, 4, 2, 0])
```

### `getBandRange()`
Gets the valid gain range for bands (min/max dB).
- **Returns**: `{ min: number, max: number }`

```typescript
const range = Equalizer.getBandRange()
// { min: -12, max: 12 }
```

### `getPresets()`
Returns all available presets (built-in + custom).
- **Returns**: [`EqualizerPreset[]`](#equalizerpreset)

```typescript
const presets = Equalizer.getPresets()
```

### `getBuiltInPresets()`
Returns only the built-in presets.
- **Returns**: [`EqualizerPreset[]`](#equalizerpreset)

```typescript
const builtIn = Equalizer.getBuiltInPresets()
```

### `getCustomPresets()`
Returns only the custom user presets.
- **Returns**: [`EqualizerPreset[]`](#equalizerpreset)

```typescript
const custom = Equalizer.getCustomPresets()
```

### `applyPreset(presetName)`
Applies a preset by name.
- **presetName**: `string`

```typescript
Equalizer.applyPreset('Bass Boost')
```

### `getCurrentPresetName()`
Gets the name of the currently applied preset, or `null` if custom settings are used.
- **Returns**: `string` | `null`

```typescript
const preset = Equalizer.getCurrentPresetName()
```

### `saveCustomPreset(name)`
Saves current settings as a custom preset.
- **name**: `string`

```typescript
Equalizer.saveCustomPreset('My Custom EQ')
```

### `deleteCustomPreset(name)`
Deletes a custom preset.
- **name**: `string`

```typescript
Equalizer.deleteCustomPreset('My Custom EQ')
```

### `getState()`
Gets the complete equalizer state (enabled, bands, current preset).
- **Returns**: [`EqualizerState`](#equalizerstate)

```typescript
const state = Equalizer.getState()
```

### `reset()`
Resets the equalizer to flat response (all bands 0dB).

```typescript
Equalizer.reset()
```

## Types

### `EqualizerBand`

Represents a single frequency band.

```typescript
interface EqualizerBand {
  index: number
  centerFrequency: number
  gainDb: number
  frequencyLabel: string
}
```

### `EqualizerPreset`

Represents a predefined or custom equalizer setting.

```typescript
interface EqualizerPreset {
  name: string
  gains: number[]
  type: 'built-in' | 'custom'
}
```

### `EqualizerState`

```typescript
interface EqualizerState {
  enabled: boolean
  bands: EqualizerBand[]
  currentPreset: string | null
}
```
