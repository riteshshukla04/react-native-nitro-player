# React Native Nitro Player

A powerful audio player library for React Native with playlist management, playback controls, and support for Android Auto and CarPlay.

## Installation

```bash
npm install react-native-nitro-player
# or
yarn add react-native-nitro-player
```

### Peer Dependencies

Make sure you have these installed:

```bash
npm install react-native-nitro-modules
```

## Quick Start

### 1. Configure the Player

Configure the player before using it in your app:

```typescript
import { TrackPlayer } from 'react-native-nitro-player'

TrackPlayer.configure({
  androidAutoEnabled: true,
  carPlayEnabled: false,
  showInNotification: true,
})
```

### 2. Create Playlists

```typescript
import { PlayerQueue } from 'react-native-nitro-player'
import type { TrackItem } from 'react-native-nitro-player'

const tracks: TrackItem[] = [
  {
    id: '1',
    title: 'Song Title',
    artist: 'Artist Name',
    album: 'Album Name',
    duration: 180.0, // in seconds
    url: 'https://example.com/song.mp3',
    artwork: 'https://example.com/artwork.jpg',
  },
]

// Create a playlist
const playlistId = PlayerQueue.createPlaylist(
  'My Playlist',
  'Playlist description',
  'https://example.com/playlist-artwork.jpg'
)

// Add tracks to the playlist
PlayerQueue.addTracksToPlaylist(playlistId, tracks)
```

### 3. Play Music

```typescript
import { TrackPlayer, PlayerQueue } from 'react-native-nitro-player'

// Load and play a playlist
PlayerQueue.loadPlaylist(playlistId)

// Or play a specific song
TrackPlayer.playSong('song-id', playlistId)

// Basic controls
TrackPlayer.play()
TrackPlayer.pause()
TrackPlayer.skipToNext()
TrackPlayer.skipToPrevious()
TrackPlayer.seek(30) // Seek to 30 seconds

// Set repeat mode
TrackPlayer.setRepeatMode('off') // No repeat
TrackPlayer.setRepeatMode('Playlist') // Repeat entire playlist
TrackPlayer.setRepeatMode('track') // Repeat current track
```

## Core Concepts

### PlayerQueue

Manages playlists and tracks. Use it to:

- Create, update, and delete playlists
- Add or remove tracks from playlists
- Load playlists for playback
- Listen to playlist changes

### TrackPlayer

Controls playback. Use it to:

- Play, pause, and seek
- Skip tracks
- Control repeat mode
- Get current player state
- Listen to playback events

## React Hooks

The library provides React hooks for reactive state management. These hooks automatically update your components when player state changes.

### `useOnChangeTrack()`

Returns the current track and the reason why it changed.

**Returns:**

- `track: TrackItem | undefined` - The current track, or `undefined` if no track is playing
- `reason: Reason | undefined` - The reason for the track change (`'user_action'`, `'skip'`, `'end'`, or `'error'`)

### `useOnPlaybackStateChange()`

Returns the current playback state and the reason for the state change.

**Returns:**

- `state: TrackPlayerState | undefined` - Current playback state (`'playing'`, `'paused'`, or `'stopped'`)
- `reason: Reason | undefined` - The reason for the state change

### `useOnPlaybackProgressChange()`

Returns real-time playback progress updates.

**Returns:**

- `position: number` - Current playback position in seconds
- `totalDuration: number` - Total duration of the current track in seconds
- `isManuallySeeked: boolean | undefined` - `true` if the user manually seeked, `undefined` otherwise

### `useOnSeek()`

Returns information about the last seek event.

**Returns:**

- `position: number | undefined` - The position where the user seeked to, or `undefined` if no seek has occurred
- `totalDuration: number | undefined` - The total duration at the time of seek, or `undefined` if no seek has occurred

### `useAndroidAutoConnection()`

Monitors Android Auto connection status.

**Returns:**

- `isConnected: boolean` - `true` if connected to Android Auto, `false` otherwise

### `useAudioDevices()` (Android only)

Automatically polls for audio device changes every 2 seconds.

**Returns:**

- `devices: TAudioDevice[]` - Array of available audio devices

## Audio Device APIs

### `AudioDevices` (Android only)

Android-specific API for managing audio output devices.

#### `getAudioDevices(): TAudioDevice[]`

Returns the list of available audio output devices.

**Returns:** Array of `TAudioDevice` objects with:

- `id: number` - Unique device ID
- `name: string` - Device name (e.g., "Built-in Speaker", "Bluetooth")
- `type: number` - Device type constant
- `isActive: boolean` - Whether this device is currently active

**Example:**

```typescript
import { AudioDevices } from 'react-native-nitro-player'

if (AudioDevices) {
  const devices = AudioDevices.getAudioDevices()
  devices.forEach(device => {
    console.log(`${device.name} - Active: ${device.isActive}`)
  })
}
```

#### `setAudioDevice(deviceId: number): boolean`

Sets the active audio output device.

**Parameters:**

- `deviceId: number` - The ID of the device to activate

**Returns:** `true` if successful, `false` otherwise

**Example:**

```typescript
import { AudioDevices } from 'react-native-nitro-player'

if (AudioDevices) {
  const success = AudioDevices.setAudioDevice(deviceId)
  console.log(`Device switch: ${success ? 'success' : 'failed'}`)
}
```

### `AudioRoutePicker` (iOS only)

iOS-specific API for displaying the native audio route picker (AirPlay menu).

#### `showRoutePicker(): void`

Shows the native AVRoutePickerView for selecting audio output routes like AirPlay, Bluetooth, etc.

**Example:**

```typescript
import { AudioRoutePicker } from 'react-native-nitro-player'

if (AudioRoutePicker) {
  AudioRoutePicker.showRoutePicker()
}
```

## Repeat Mode

Control how tracks repeat during playback.

### `setRepeatMode(mode: RepeatMode): boolean`

Sets the repeat mode for the player.

**Parameters:**

- `mode: 'off' | 'Playlist' | 'track'` - The repeat mode to set
  - `'off'` - No repeat, playlist stops at the end
  - `'Playlist'` - Repeat the entire playlist
  - `'track'` - Repeat the current track only

**Returns:** `true` if successful, `false` otherwise

**Example:**

```typescript
import { TrackPlayer } from 'react-native-nitro-player'

// Turn off repeat
TrackPlayer.setRepeatMode('off')

// Repeat entire playlist
TrackPlayer.setRepeatMode('Playlist')

// Repeat current track
TrackPlayer.setRepeatMode('track')
```

## Usage Examples

### Using React Hooks

The library provides convenient React hooks for reactive state management:

```typescript
import {
  useOnChangeTrack,
  useOnPlaybackStateChange,
  useOnPlaybackProgressChange,
  useOnSeek,
  useAndroidAutoConnection,
} from 'react-native-nitro-player'

function PlayerComponent() {
  // Get current track
  const { track, reason } = useOnChangeTrack()

  // Get playback state (playing, paused, stopped)
  const { state, reason: stateReason } = useOnPlaybackStateChange()

  // Get playback progress
  const { position, totalDuration, isManuallySeeked } = useOnPlaybackProgressChange()

  // Get seek events
  const { position: seekPosition, totalDuration: seekDuration } = useOnSeek()

  // Check Android Auto connection
  const { isConnected } = useAndroidAutoConnection()

  return (
    <View>
      {track && (
        <Text>Now Playing: {track.title} by {track.artist}</Text>
      )}
      <Text>State: {state}</Text>
      <Text>Progress: {position} / {totalDuration}</Text>
    </View>
  )
}
```

### Managing Playlists

```typescript
import { PlayerQueue } from 'react-native-nitro-player'
import type { TrackItem, Playlist } from 'react-native-nitro-player'

// Get all playlists
const playlists = PlayerQueue.getAllPlaylists()

// Get a specific playlist
const playlist = PlayerQueue.getPlaylist(playlistId)

// Get current playing playlist
const currentPlaylistId = PlayerQueue.getCurrentPlaylistId()

// Update playlist metadata
PlayerQueue.updatePlaylist(playlistId, {
  name: 'Updated Name',
  description: 'New description',
  artwork: 'https://example.com/new-artwork.jpg',
})

// Add a single track
PlayerQueue.addTrackToPlaylist(playlistId, newTrack)

// Add multiple tracks
PlayerQueue.addTracksToPlaylist(playlistId, [track1, track2, track3])

// Remove a track
PlayerQueue.removeTrackFromPlaylist(playlistId, trackId)

// Reorder tracks
PlayerQueue.reorderTrackInPlaylist(playlistId, trackId, newIndex)

// Delete a playlist
PlayerQueue.deletePlaylist(playlistId)
```

### Listening to Events

```typescript
import { PlayerQueue, TrackPlayer } from 'react-native-nitro-player'

// Listen to playlist changes
PlayerQueue.onPlaylistsChanged((playlists, operation) => {
  console.log('Playlists updated:', operation)
  // operation can be: 'add', 'remove', 'clear', 'update'
})

// Listen to specific playlist changes
PlayerQueue.onPlaylistChanged((playlistId, playlist, operation) => {
  console.log('Playlist changed:', playlistId, operation)
})

// Listen to track changes
TrackPlayer.onChangeTrack((track, reason) => {
  console.log('Track changed:', track.title, reason)
  // reason can be: 'user_action', 'skip', 'end', 'error'
})

// Listen to playback state changes
TrackPlayer.onPlaybackStateChange((state, reason) => {
  console.log('State changed:', state, reason)
})

// Listen to seek events
TrackPlayer.onSeek((position, totalDuration) => {
  console.log('Seeked to:', position)
})

// Listen to playback progress
TrackPlayer.onPlaybackProgressChange(
  (position, totalDuration, isManuallySeeked) => {
    console.log('Progress:', position, '/', totalDuration)
  }
)

// Listen to Android Auto connection changes
TrackPlayer.onAndroidAutoConnectionChange(connected => {
  console.log('Android Auto:', connected ? 'Connected' : 'Disconnected')
})
```

### Getting Player State

```typescript
import { TrackPlayer } from 'react-native-nitro-player'

const state = TrackPlayer.getState()

console.log(state.currentState) // 'playing' | 'paused' | 'stopped'
console.log(state.currentPosition) // current position in seconds
console.log(state.totalDuration) // total duration in seconds
console.log(state.currentTrack) // current TrackItem or null
console.log(state.currentPlaylistId) // current playlist ID or null
console.log(state.currentIndex) // current track index in playlist
```

## Track Item Structure

Each track must follow this structure:

```typescript
interface TrackItem {
  id: string // Unique identifier
  title: string // Track title
  artist: string // Artist name
  album: string // Album name
  duration: number // Duration in seconds
  url: string // Audio file URL
  artwork?: string | null // Optional artwork URL
}
```

## Playlist Structure

```typescript
interface Playlist {
  id: string // Unique identifier
  name: string // Playlist name
  description?: string | null // Optional description
  artwork?: string | null // Optional artwork URL
  tracks: TrackItem[] // Array of tracks
}
```

## Android Auto Customization

Customize how your music library appears in Android Auto with a custom folder structure.

### Basic Setup

By default, all playlists are shown in Android Auto. You can create a custom structure:

```typescript
import { AndroidAutoMediaLibraryHelper } from 'react-native-nitro-player'
import type { MediaLibrary } from 'react-native-nitro-player'

// Check if available (Android only)
if (AndroidAutoMediaLibraryHelper.isAvailable()) {
  const mediaLibrary: MediaLibrary = {
    layoutType: 'grid', // 'grid' or 'list'
    rootItems: [
      {
        id: 'my_music',
        title: '🎵 My Music',
        subtitle: 'Your music collection',
        mediaType: 'folder',
        isPlayable: false,
        layoutType: 'grid',
        children: [
          {
            id: 'favorites',
            title: 'Favorites',
            subtitle: '10 tracks',
            mediaType: 'playlist',
            playlistId: 'my-playlist-id', // References a playlist created with PlayerQueue
            isPlayable: false,
          },
        ],
      },
      {
        id: 'recent',
        title: '🕐 Recently Played',
        mediaType: 'folder',
        isPlayable: false,
        children: [
          // More playlist references...
        ],
      },
    ],
  }

  AndroidAutoMediaLibraryHelper.set(mediaLibrary)
}

// Reset to default (show all playlists)
AndroidAutoMediaLibraryHelper.clear()
```

### MediaLibrary Structure

```typescript
interface MediaLibrary {
  layoutType: 'grid' | 'list' // Default layout for items
  rootItems: MediaItem[] // Top-level items
  appName?: string // Optional app name
  appIconUrl?: string // Optional app icon
}

interface MediaItem {
  id: string // Unique identifier
  title: string // Display title
  subtitle?: string // Optional subtitle
  iconUrl?: string // Optional icon/artwork URL
  isPlayable: boolean // Whether item can be played
  mediaType: 'folder' | 'audio' | 'playlist' // Type of item
  playlistId?: string // Reference to playlist (for playlist items)
  children?: MediaItem[] // Child items (for folders)
  layoutType?: 'grid' | 'list' // Override default layout
}
```

### Example: Organizing Playlists by Genre

```typescript
import {
  PlayerQueue,
  AndroidAutoMediaLibraryHelper,
} from 'react-native-nitro-player'

// Create playlists first
const rockPlaylistId = PlayerQueue.createPlaylist('Rock Classics')
const jazzPlaylistId = PlayerQueue.createPlaylist('Jazz Essentials')
const popPlaylistId = PlayerQueue.createPlaylist('Pop Hits')

// Add tracks to playlists...
PlayerQueue.addTracksToPlaylist(rockPlaylistId, rockTracks)
PlayerQueue.addTracksToPlaylist(jazzPlaylistId, jazzTracks)
PlayerQueue.addTracksToPlaylist(popPlaylistId, popTracks)

// Create custom Android Auto structure
AndroidAutoMediaLibraryHelper.set({
  layoutType: 'list',
  rootItems: [
    {
      id: 'genres',
      title: '🎸 By Genre',
      mediaType: 'folder',
      isPlayable: false,
      layoutType: 'grid',
      children: [
        {
          id: 'rock',
          title: 'Rock',
          mediaType: 'playlist',
          playlistId: rockPlaylistId,
          isPlayable: false,
        },
        {
          id: 'jazz',
          title: 'Jazz',
          mediaType: 'playlist',
          playlistId: jazzPlaylistId,
          isPlayable: false,
        },
        {
          id: 'pop',
          title: 'Pop',
          mediaType: 'playlist',
          playlistId: popPlaylistId,
          isPlayable: false,
        },
      ],
    },
    {
      id: 'all_music',
      title: '📀 All Music',
      mediaType: 'folder',
      isPlayable: false,
      children: [
        {
          id: 'all_rock',
          title: 'Rock Classics',
          mediaType: 'playlist',
          playlistId: rockPlaylistId,
          isPlayable: false,
        },
        {
          id: 'all_jazz',
          title: 'Jazz Essentials',
          mediaType: 'playlist',
          playlistId: jazzPlaylistId,
          isPlayable: false,
        },
        {
          id: 'all_pop',
          title: 'Pop Hits',
          mediaType: 'playlist',
          playlistId: popPlaylistId,
          isPlayable: false,
        },
      ],
    },
  ],
})
```

### Notes

- The `playlistId` field must reference a playlist created with `PlayerQueue.createPlaylist()`
- Changes are immediately reflected in Android Auto
- Use folders to organize playlists hierarchically
- Grid layout is best for album/playlist browsing
- List layout is best for song lists
- Only available on Android (use `isAvailable()` to check)

## Features

- ✅ **Playlist Management**: Create, update, and manage multiple playlists
- ✅ **Playback Controls**: Play, pause, seek, skip tracks
- ✅ **React Hooks**: Built-in hooks for reactive state management
- ✅ **Event Listeners**: Listen to track changes, state changes, and more
- ✅ **Android Auto Support**: Control playback from Android Auto with customizable UI
- ✅ **CarPlay Support**: Control playback from CarPlay (iOS)
- ✅ **Notification Controls**: Show playback controls in notifications
- ✅ **Progress Tracking**: Real-time playback progress updates

## TypeScript Support

The library is written in TypeScript and includes full type definitions. All types are exported for your convenience:

```typescript
import type {
  TrackItem,
  Playlist,
  PlayerState,
  TrackPlayerState,
  QueueOperation,
  Reason,
  PlayerConfig,
  MediaLibrary,
  MediaItem,
  LayoutType,
  MediaType,
} from 'react-native-nitro-player'
```

## Platform Support

- ✅ **iOS**: Full support with CarPlay integration
- ✅ **Android**: Full support with Android Auto integration
- 🎯 **Android Auto Media Library**: Android-only feature for customizing the Android Auto UI

## License

MIT
