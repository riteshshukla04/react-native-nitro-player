---
sidebar_position: 6
sidebar_label: '📱 Platform Specific'
tags: [android, ios]
---

# Platform Specific

Certain features are available only on specific platforms.

## Android

<span className="badge badge--success">Android</span>

### `useAudioDevices()`

Hook to get the list of available audio devices.
- **Returns**: [`AudioDevice[]`](#audiodevice)

```typescript
const devices = useAudioDevices()
```

### `AudioDevices`

Object to control audio output routing on Android.

#### `getAudioDevices()`

Returns list of available devices.
- **Returns**: [`AudioDevice[]`](#audiodevice)

```typescript
const devices = AudioDevices.getAudioDevices()
```

#### `setAudioDevice(device)`

Sets the active audio output device.
- **device**: `number` (id)

```typescript
AudioDevices.setAudioDevice(deviceId)
```

### `AndroidAutoMediaLibrary`

Object to control Android Auto integration.

#### `setMediaLibrary(json)`

Sets the structure of the media library displayed in Android Auto.
- **json**: `string` (serialized [`MediaLibrary`](#medialibrary))

```typescript
AndroidAutoMediaLibrary.setMediaLibrary(JSON.stringify(myStructure))
```

#### `clearMediaLibrary()`

Clears the media library in Android Auto.

```typescript
AndroidAutoMediaLibrary.clearMediaLibrary()
```

## iOS

<span className="badge badge--secondary">iOS</span>

### `AudioRoutePicker`

Object to control audio output routing on iOS (AirPlay, Bluetooth).

#### `showRoutePicker()`

Displays the native iOS AirPlay route picker view.

```typescript
AudioRoutePicker.showRoutePicker()
```

## Types

### `AudioDevice`

Represents an audio output device (Android).

```typescript
interface AudioDevice {
  id: number
  name: string
  type: number
  isActive: boolean
}
```

### `MediaItem`

Represents a playable item or folder in the Android Auto interface.

```typescript
interface MediaItem {
  id: string
  title: string
  subtitle?: string
  iconUrl?: string
  isPlayable: boolean
  mediaType: 'folder' | 'audio' | 'playlist'
  playlistId?: string
  children?: MediaItem[]
  layoutType?: 'grid' | 'list'
}
```

### `MediaLibrary`

Structure of the Android Auto media browser.

```typescript
interface MediaLibrary {
  layoutType: 'grid' | 'list'
  rootItems: MediaItem[]
  appName?: string
  appIconUrl?: string
}
```
