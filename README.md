# React Native Nitro Player

A powerful audio player library for React Native with playlist management, playback controls, and support for Android Auto and CarPlay.

Documentation: [https://nitroplayer.riteshshukla.in/](https://nitroplayer.riteshshukla.in/)

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

## API Reference


### React Hooks

| Name                          | Platform | Description                                                                     |
| ----------------------------- | -------- | ------------------------------------------------------------------------------- |
| `useOnChangeTrack`            | Both     | Returns current track and change reason. Updates automatically.                 |
| `useOnPlaybackStateChange`    | Both     | Returns current playback state (playing/paused) and change reason.              |
| `useOnPlaybackProgressChange` | Both     | Returns real-time playback progress, duration, and seek status.                 |
| `useOnSeek`                   | Both     | Returns information about the last seek event (position/duration).              |
| `useNowPlaying`               | Both     | Returns complete player state (track, state, duration, playlist) in one object. |
| `useActualQueue`              | Both     | Returns the efficient playback queue including temporary tracks.                |
| `useShuffleMode`              | Both     | Returns whether shuffle is on. Updates on toggles, reshuffle and remote controls. |
| `usePlaylist`                 | Both     | Manages playlist state, providing access to all playlists and tracks.           |
| `useEqualizer`                | Both     | Controls the 5-band equalizer, including presets and individual band gains.     |
| `useAndroidAutoConnection`    | Both     | Monitors Android Auto connection status.                                        |
| `useAudioDevices`             | Android  | Returns list of available audio output devices.                                 |
| `useDownloadProgress`         | Both     | Tracks download progress for tracks. Returns progress map and overall status.   |
| `useDownloadedTracks`         | Both     | Returns all downloaded tracks and playlists with query helpers.                 |

### TrackPlayer Methods

Command-style methods return **`Promise<void>`** (or another **`Promise`**) and **reject** on failure; **`getRepeatMode()`**, **`getShuffleMode()`** and **`isAndroidAutoConnected()`** are synchronous reads.

| Name                        | Platform | Description                                                         |
| --------------------------- | -------- | ------------------------------------------------------------------- |
| `play()`                    | Both     | **Async**. Resumes playback.                                        |
| `pause()`                   | Both     | **Async**. Pauses playback.                                         |
| `playSong(id, playlistId?)` | Both     | **Async**. Plays a specific song, optionally from a playlist.       |
| `skipToNext()`              | Both     | **Async**. Skips to the next track in the queue.                    |
| `skipToPrevious()`          | Both     | **Async**. Skips to the previous track.                             |
| `seek(position)`            | Both     | **Async**. Seeks to a specific time position in seconds.           |
| `setPlaybackSpeed(speed)`   | Both     | **Async**. Sets playback speed; rejects non-finite and non-positive values. |
| `getPlaybackSpeed()`        | Both     | **Async**. Gets the current playback speed.                         |
| `setVolume(0-100)`          | Both     | **Async**. Sets playback volume (0-100).                            |
| `setRepeatMode(mode)`       | Both     | **Async**. Sets repeat mode (`off`, `track`, `Playlist`).           |
| `getRepeatMode()`           | Both     | **Sync**. Current repeat mode.                                      |
| `setShuffleMode(enabled)`   | Both     | **Async**. Shuffles the live playlist without stopping; `false` restores order. |
| `getShuffleMode()`          | Both     | **Sync**. Whether shuffle is on.                                    |
| `reshuffle()`               | Both     | **Async**. Re-randomizes the upcoming order; current track stays first. |
| `addToUpNext(id)`           | Both     | **Async**. Adds a track to the "up next" queue (FIFO).              |
| `playNext(id)`              | Both     | **Async**. Adds a track to the "play next" stack (LIFO).            |
| `getActualQueue()`          | Both     | **Async**. Full playback queue including temporary tracks.          |
| `getState()`                | Both     | **Async**. Snapshot of player state.                                |
| `skipToIndex(index)`        | Both     | **Async**. Skips to an index in the actual queue (`Promise<boolean>`). |
| `configure(config)`         | Both     | **Async**. Player settings (Android Auto, CarPlay, notification).   |
| `isAndroidAutoConnected()`  | Both     | **Sync**. Android Auto connection.                                  |

### PlayerQueue Methods

Mutations return **`Promise<void>`** (or **`Promise<string>`** for `createPlaylist`). **`getPlaylist`** / **`getAllPlaylists`** / **`getCurrentPlaylistId`** are synchronous reads.

| Name                                    | Platform | Description                                             |
| --------------------------------------- | -------- | ------------------------------------------------------- |
| `createPlaylist(name, ...)`             | Both     | **Async**. Creates a playlist; resolves to playlist ID. |
| `deletePlaylist(id)`                    | Both     | **Async**. Deletes a playlist by ID.                    |
| `updatePlaylist(id, ...)`               | Both     | **Async**. Updates metadata (name, description, artwork). |
| `getPlaylist(id)`                       | Both     | Gets a specific playlist object.                        |
| `getAllPlaylists()`                     | Both     | Gets all available playlists.                           |
| `loadPlaylist(id)`                      | Both     | **Async**. Loads a playlist for playback.               |
| `getCurrentPlaylistId()`                | Both     | Gets the ID of the currently playing playlist.          |
| `addTrackToPlaylist(pid, track)`        | Both     | **Async**. Adds a track to a playlist.                  |
| `addTracksToPlaylist(pid, tracks)`      | Both     | **Async**. Adds multiple tracks to a playlist.         |
| `removeTrackFromPlaylist(pid, tid)`     | Both     | **Async**. Removes a track from a playlist.             |
| `removeTracksFromPlaylist(pid, tids)`   | Both     | **Async**. Removes many tracks in one pass; unknown ids skipped. |
| `reorderTrackInPlaylist(pid, tid, idx)` | Both     | **Async**. Moves a track to a new position.             |

### Platform-Specific APIs

| Name                                     | Platform | Description                                       |
| ---------------------------------------- | -------- | ------------------------------------------------- |
| `AudioDevices.getAudioDevices()`         | Android  | Returns list of available audio devices.          |
| `AudioDevices.setAudioDevice(id)`        | Android  | Sets the active audio output device.              |
| `AudioRoutePicker.showRoutePicker()`     | iOS      | Opens the native AirPlay/Audio Route picker menu. |
| `Cast.showCastPicker()`                  | iOS & Android | Opens the native Google Cast device picker.  |
| `Cast.isCasting()` / `useIsCasting()`    | iOS & Android | Whether playback is routed to a Cast device. |
| `AndroidAutoMediaLibraryHelper.set(...)` | Android  | Sets custom folder structure for Android Auto.    |
| `AndroidAutoMediaLibraryHelper.clear()`  | Android  | Resets Android Auto structure to default.         |

### DownloadManager Methods

| Name                                   | Platform | Description                                                   |
| -------------------------------------- | -------- | ------------------------------------------------------------- |
| `configure(config)`                    | Both     | Configures download settings (storage, concurrency, etc.).    |
| `downloadTrack(track, playlistId?)`    | Both     | **Async**. Downloads a track. Returns download ID.            |
| `downloadPlaylist(playlistId, tracks)` | Both     | **Async**. Downloads all tracks in a playlist.                |
| `pauseDownload(downloadId)`            | Both     | **Async**. Pauses an active download.                         |
| `resumeDownload(downloadId)`           | Both     | **Async**. Resumes a paused download.                         |
| `cancelDownload(downloadId)`           | Both     | **Async**. Cancels a download.                                |
| `isTrackDownloaded(trackId)`           | Both     | **Async**. Checks on-disk download state.                     |
| `getAllDownloadedTracks()`             | Both     | **Async**. Lists persisted downloaded tracks.                 |
| `getEffectiveUrl(track)`               | Both     | **Async**. Local or remote URL from preference + downloads. |
| `syncDownloads()`                      | Both     | **Async**. Reconcile DB with files; returns cleanup count.    |
| `deleteDownloadedTrack(trackId)`       | Both     | **Async**. Deletes a downloaded track.                        |
| `getStorageInfo()`                     | Both     | **Async**. Gets download storage usage information.           |
| `setPlaybackSourcePreference(pref)`    | Both     | Sets playback source: `'auto'`, `'download'`, or `'network'`. |

> [!NOTE]
> See [DOWNLOADS.md](./DOWNLOADS.md) for complete downloads API documentation.

## Quick Start

`TrackPlayer` / `PlayerQueue` commands return **Promises**. The snippets use `await`—run them inside an `async` function, or use `.then()` / `void` / `.catch()` as appropriate.

### 1. Configure the Player

Configure the player before using it in your app:

```typescript
import { TrackPlayer } from 'react-native-nitro-player'

await TrackPlayer.configure({
  androidAutoEnabled: true,
  carPlayEnabled: false,
  showInNotification: true,
  remoteSkipForwardInterval: 15,
  remoteSkipBackwardInterval: 15,
})
```

Remote skip intervals are in seconds. iOS uses them for AirPods/Control Center fixed skip buttons and exposes remote playback rates `0.5, 1.0, 1.25, 1.5, 1.75, 2.0`; Android uses them for the Media3 seek back/forward notification buttons and does not expose a playback-rate media button. Press-and-hold continuous seek is not implemented on either platform. Custom intervals apply to local playback; during a Google Cast session the receiver skips by a fixed 15 seconds.

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
    // Optional custom data (accessible in player state)
    extraPayload: {
      artistId: '123',
      genre: 'Rock',
      isFavorite: true,
    },
  },
]

const playlistId = await PlayerQueue.createPlaylist(
  'My Playlist',
  'Playlist description',
  'https://example.com/playlist-artwork.jpg'
)

await PlayerQueue.addTracksToPlaylist(playlistId, tracks)
```

### 3. Play Music

```typescript
import { TrackPlayer, PlayerQueue } from 'react-native-nitro-player'

await PlayerQueue.loadPlaylist(playlistId)

await TrackPlayer.playSong('song-id', playlistId)

await TrackPlayer.play()
await TrackPlayer.pause()
await TrackPlayer.skipToNext()
await TrackPlayer.skipToPrevious()
await TrackPlayer.seek(30)

await TrackPlayer.setRepeatMode('off')
await TrackPlayer.setRepeatMode('Playlist')
await TrackPlayer.setRepeatMode('track')

await TrackPlayer.setVolume(50)
await TrackPlayer.setVolume(0)
await TrackPlayer.setVolume(100)

// Add temporary tracks to queue
await TrackPlayer.addToUpNext('song-id') // Add to up-next queue (FIFO)
await TrackPlayer.playNext('song-id') // Add to play-next stack (LIFO)
```

### 4. Download for Offline Playback (Optional)

```typescript
import { DownloadManager } from 'react-native-nitro-player'

// Configure downloads
DownloadManager.configure({
  maxConcurrentDownloads: 3,
  backgroundDownloadsEnabled: true,
  downloadArtwork: true,
})

// Download a track
const downloadId = await DownloadManager.downloadTrack(track)

// Download entire playlist
const playlist = PlayerQueue.getPlaylist(playlistId)
await DownloadManager.downloadPlaylist(playlist.id, playlist.tracks)

// Set playback to prefer downloaded tracks
DownloadManager.setPlaybackSourcePreference('auto')
```

> [!NOTE]
> See [DOWNLOADS.md](./DOWNLOADS.md) for complete offline downloads documentation.

## Temporary Queue Management

The player supports adding temporary tracks to the queue without modifying the original playlist. These tracks are automatically removed after playing.

### `addToUpNext(trackId: string): Promise<void>`

Adds a track to the **up-next queue** (FIFO - First In, First Out). Tracks play in the order they were added.

**Behavior:**

- Track is inserted after the current track and any "play next" tracks
- Multiple tracks can be added - they play in the order added
- Track is automatically removed after playing
- Does not modify the original playlist

**Example:**

```typescript
// Add tracks to up-next queue
await TrackPlayer.addToUpNext('song-1') // Will play 3rd
await TrackPlayer.addToUpNext('song-2') // Will play 4th
await TrackPlayer.addToUpNext('song-3') // Will play 5th
// Order: [current] → [song-1] → [song-2] → [song-3]
```

### `playNext(trackId: string): Promise<void>`

Adds a track to the **play-next stack** (LIFO - Last In, First Out). The most recently added track plays first.

**Behavior:**

- Track is inserted immediately after the current track
- Multiple tracks can be added - the last added plays first
- Track is automatically removed after playing
- Does not modify the original playlist

**Example:**

```typescript
// Add tracks to play-next stack
await TrackPlayer.playNext('song-1') // Will play 3rd
await TrackPlayer.playNext('song-2') // Will play 2nd (most recent)
await TrackPlayer.playNext('song-3') // Will play 1st (most recent)
// Order: [current] → [song-3] → [song-2] → [song-1]
```

### Queue Order

The actual playback order is:

```
[original tracks before current]
+ [CURRENT TRACK]
+ [playNext stack (LIFO)]
+ [upNext queue (FIFO)]
+ [original tracks after current]
```

### Clearing Temporary Tracks

Temporary tracks are automatically cleared when:

- `await TrackPlayer.playSong()` is called
- `await PlayerQueue.loadPlaylist()` is called

### `skipToIndex(index: number): Promise<boolean>`

Skips to a specific index in the **actual queue** (the combined queue with temporary tracks).

**Behavior:**

- Takes an index into the actual queue structure
- If the target is a temporary track (playNext or upNext), plays that track
- If the target is beyond temporary tracks (in the remaining original playlist), clears all temporary tracks and plays from the original playlist
- Returns `true` if successful, `false` if the index is invalid

**Example:**

```typescript
// Queue: [track1(0), track2(1, current), playNext-A(2), upNext-B(3), track3(4), track4(5)]

// Skip to playNext track
await TrackPlayer.skipToIndex(2) // Plays playNext-A

// Skip to original playlist track (clears temporary tracks)
await TrackPlayer.skipToIndex(4) // Clears temps, plays track3
```

### Getting the Actual Queue

Use `useActualQueue()` hook to see the complete queue including temporary tracks:

```typescript
import { useActualQueue } from 'react-native-nitro-player'

function QueueView() {
  const { queue, refreshQueue, isLoading } = useActualQueue()

  return (
    <ScrollView>
      {queue.map((track, index) => (
        <View key={track.id}>
          <Text>{index + 1}. {track.title}</Text>
        </View>
      ))}
    </ScrollView>
  )
}
```

**Returns:**

- `queue: TrackItem[]` - Complete queue in playback order
- `refreshQueue: () => void` - Manually refresh the queue
- `isLoading: boolean` - Whether the queue is currently loading

## CurrentPlayingType

The `currentPlayingType` field in `PlayerState` indicates the source of the currently playing track:

| Value          | Description                                              |
| -------------- | -------------------------------------------------------- |
| `'playlist'`   | Playing from the original playlist                       |
| `'play-next'`  | Playing a track added via `playNext()` (LIFO stack)      |
| `'up-next'`    | Playing a track added via `addToUpNext()` (FIFO queue)   |
| `'not-playing'`| No track is currently playing                            |

**Example:**

```typescript
const state = await TrackPlayer.getState()

if (state.currentPlayingType === 'play-next') {
  console.log('Playing a play-next track')
} else if (state.currentPlayingType === 'up-next') {
  console.log('Playing an up-next track')
} else if (state.currentPlayingType === 'playlist') {
  console.log('Playing from the original playlist')
}
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
- Control volume
- Add temporary tracks to queue (`addToUpNext`, `playNext`)
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

### `useNowPlaying()`

Returns the complete current player state (same as `TrackPlayer.getState()`). This hook provides all player information in a single object and automatically updates when the player state changes.

**Returns:**

- `PlayerState` object containing:
  - `currentTrack: TrackItem | null` - The current track being played, or `null` if no track is playing
  - `totalDuration: number` - Total duration of the current track in seconds
  - `currentState: TrackPlayerState` - Current playback state (`'playing'`, `'paused'`, or `'stopped'`)
  - `currentPlaylistId: string | null` - ID of the currently loaded playlist, or `null` if no playlist is loaded
  - `currentIndex: number` - Index of the current track in the playlist (-1 if no track is playing)
  - `currentPlayingType: CurrentPlayingType` - Source of the current track (`'playlist'`, `'play-next'`, `'up-next'`, or `'not-playing'`)

**Note:** This hook is equivalent to calling `TrackPlayer.getState()` but provides reactive updates. It listens to track changes and playback state changes to update automatically. Also dont rely on progress from this hook

### `useActualQueue()`

Returns the actual playback queue including temporary tracks (from `addToUpNext` and `playNext`).

**Returns:**

- `queue: TrackItem[]` - Complete queue in playback order: `[tracks_before_current] + [current] + [playNext_stack] + [upNext_queue] + [remaining_tracks]`
- `refreshQueue: () => void` - Manually refresh the queue (useful after adding tracks)
- `isLoading: boolean` - Whether the queue is currently loading

**Auto-updates when:**

- Track changes
- Temporary tracks are added (`playNext`/`addToUpNext`)
- Playback state changes

**Example:**

```typescript
import { useActualQueue } from 'react-native-nitro-player'

function QueueView() {
  const { queue, refreshQueue, isLoading } = useActualQueue()

  const handleAddToUpNext = async (trackId: string) => {
    await TrackPlayer.addToUpNext(trackId)
    // Refresh queue after adding track
    setTimeout(refreshQueue, 100)
  }

  return (
    <ScrollView>
      {queue.map((track, index) => (
        <View key={track.id}>
          <Text>{index + 1}. {track.title}</Text>
        </View>
      ))}
    </ScrollView>
  )
}
```

### `usePlaylist()`

Manages playlist-related state and provides access to all playlists and tracks.

**Returns:**

- `currentPlaylist: Playlist | null` - The currently loaded playlist
- `currentPlaylistId: string | null` - ID of the currently loaded playlist
- `allPlaylists: Playlist[]` - Array of all playlists
- `allTracks: TrackItem[]` - Array of all tracks from all playlists
- `isLoading: boolean` - Whether playlists are currently loading
- `refreshPlaylists: () => void` - Manually refresh playlist data

**Example:**

```typescript
import { usePlaylist } from 'react-native-nitro-player'

function PlaylistView() {
  const { allPlaylists, allTracks, refreshPlaylists } = usePlaylist()

  return (
    <View>
      <Text>Playlists: {allPlaylists.length}</Text>
      <Text>Total Tracks: {allTracks.length}</Text>
    </View>
  )
}
```

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
  devices.forEach((device) => {
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


## Google Cast

Cast playback to Chromecast / Google TV devices. Casting is **seamless**: it is
implemented as an internal playback-backend swap, so a Cast device behaves like
another output for the existing player. When a session is connected, audio plays
**only on the Cast device**, the local output is silenced automatically, and your
existing queue, transport controls (in-app, lock screen, notification) and events
keep working against the remote. On disconnect, local playback resumes at the same
position.

- **Android** uses Media3's `CastPlayer` (the local ExoPlayer is swapped to it).
- **iOS** uses the Google Cast SDK (`GCKRemoteMediaClient`).

### JS API

```ts
import { Cast, CastButton, useIsCasting, useCastState } from 'react-native-nitro-player'

// Optional: call once early (e.g. on app start) to use your own registered
// Web Receiver. Omit / pass nothing to use the Default Media Receiver.
await Cast.configure('YOUR_RECEIVER_APP_ID')

Cast.isCasting()           // boolean — is playback currently on a Cast device
Cast.getCastState()        // 'no_devices_available' | 'not_connected' | 'connecting' | 'connected'
Cast.getCastDeviceName()   // string | null
Cast.showCastPicker()      // present the native device chooser / disconnect dialog
await Cast.endCastSession() // stop casting, resume locally

// Low-level event listener (the hooks below wrap this)
Cast.onCastStateChange((state, deviceName) => { /* ... */ })
```

> ℹ️ The receiver application ID is fixed for the process lifetime once Cast
> initializes. Call `Cast.configure(id)` as early as possible; otherwise the change
> applies on the next app launch. The **Default Media Receiver** works out of the box.

### Hooks

```tsx
function NowPlaying() {
  const isCasting = useIsCasting() // boolean

  // Or the richer variant:
  const { state, deviceName, isCasting, isReady } = useCastState()

  return <Text>{isCasting ? `Casting to ${deviceName}` : 'Playing locally'}</Text>
}
```

### `<CastButton />`

A ready-to-use button that reflects the live connection state, hides itself when
no devices are available, and opens the native Cast dialog on press.

```tsx
import { CastButton } from 'react-native-nitro-player'

<CastButton size={28} color="#888" activeColor="#1DB954" />
```

Props: `size`, `color`, `activeColor`, `hideWhenNoDevices` (default `true`),
`style`, `onPress` (override the default picker), and `renderIcon` (supply your own
icon — receives `{ state, isCasting, size, color }`). Any other `Pressable` prop is
forwarded. Prefer building your own button? Call `Cast.showCastPicker()` directly.

### Setup

Cast requires native configuration in your **app** (not just the library).

**iOS** — add to `ios/<App>/Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>${PRODUCT_NAME} uses the local network to discover Cast devices.</string>
<key>NSBonjourServices</key>
<array>
  <string>_googlecast._tcp</string>
  <!-- Receiver-specific service. Use _CC1AD845._googlecast._tcp for the Default
       Media Receiver, or _<YOUR_RECEIVER_APP_ID>._googlecast._tcp for a custom one. -->
  <string>_CC1AD845._googlecast._tcp</string>
</array>
<!-- Only if you use Cast guest mode (full SDK): -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>${PRODUCT_NAME} uses Bluetooth to discover nearby Cast devices.</string>
```

The Google Cast SDK is pulled in automatically via the pod dependency — just run
`pod install`. No `AppDelegate` code is required; the library initializes the Cast
context on launch (with the Default Media Receiver, or your `Cast.configure` ID).

**Android** — no app code required. The library declares the Cast `OptionsProvider`
and discovery permissions in its manifest (merged automatically) and initializes the
Cast framework from its playback service at launch. Cast device discovery requires
Google Play services on the device (unavailable on most emulators).

> Apps that also use another Cast `OptionsProvider` (e.g. `react-native-google-cast`)
> must override the merged meta-data with `tools:replace`. To set a custom receiver
> ID without `Cast.configure`, override the
> `com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME` meta-data with
> your own provider.

### Notes & limitations

- **Testing requires a real Cast device** on the same Wi-Fi network — there is no
  simulator/emulator support.
- The full effective queue (playlist + play-next + up-next) is mirrored to the
  device, so skip / previous / seek work remotely.
- On iOS, while casting the lock-screen Now Playing metadata is best-effort; the
  transport buttons themselves control the Cast device.
- If a device has no Google Play services (Android) or the SDK is otherwise
  unavailable, Cast features degrade to inert no-ops (`isCasting` stays `false`).

## Equalizer

The player includes a powerful 5-band equalizer that works on both iOS and Android.

### `useEqualizer()`

Returns the current equalizer state and control methods.

**Returns:**

- `isEnabled: boolean` - Whether the equalizer is currently active
- `bands: EqualizerBand[]` - Current gain settings for all 5 bands
- `currentPreset: string | null` - Name of the currently applied preset
- `setEnabled(enabled: boolean): boolean` - Toggle the equalizer on/off
- `setBandGain(index: number, gainDb: number): boolean` - Set gain for a specific band (range: -12dB to +12dB)
- `setAllBandGains(gains: number[]): boolean` - Set all band gains at once
- `reset(): void` - Reset to flat response

**Bands:**

The equalizer features 5 bands at the following center frequencies:
1. **60 Hz** - Sub-bass/Bass
2. **230 Hz** - Bass/Low-mids
3. **910 Hz** - Mids
4. **3.6 kHz** - Upper-mids/Treble
5. **14 kHz** - High treble/Air

**Example:**

```typescript
import { useEqualizer } from 'react-native-nitro-player'

function EqualizerControl() {
  const { 
    isEnabled, 
    setEnabled, 
    bands, 
    setBandGain, 
    reset 
  } = useEqualizer()

  return (
    <View>
      <Switch 
        value={isEnabled} 
        onValueChange={setEnabled} 
      />
      
      {bands.map((band) => (
        <View key={band.index}>
          <Text>{band.frequencyLabel}</Text>
          <Slider
            minimumValue={-12}
            maximumValue={12}
            value={band.gainDb}
            onSlidingComplete={(value) => setBandGain(band.index, value)}
          />
        </View>
      ))}
      
      <Button title="Reset" onPress={reset} />
    </View>
  )
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

## Shuffle

Native shuffle that never stops playback. The current track keeps playing and becomes index 0; the
rest of the playlist is shuffled behind it. Turning shuffle off restores the playlist order.

```typescript
import { TrackPlayer, useShuffleMode } from 'react-native-nitro-player'

await TrackPlayer.setShuffleMode(true) // current stays, rest shuffled
await TrackPlayer.reshuffle() // new random order, current still first
await TrackPlayer.setShuffleMode(false) // playlist order restored
TrackPlayer.getShuffleMode() // sync boolean

TrackPlayer.onShuffleChange((enabled) => console.log('shuffle', enabled))
const enabled = useShuffleMode() // hook
```

- Shuffle is a player-level setting: `loadPlaylist(id, index)` and `playSong` put the start track first and shuffle the rest.
- `getActualQueue()`, `PlayerState.currentIndex` and `skipToIndex()` use the shuffled order while shuffle is on.
- playNext / upNext still play before the shuffled remainder; repeat `'Playlist'` loops the same shuffled order.
- Tracks added while shuffled land at a random upcoming position; removed tracks drop out.
- The CarPlay / Android Auto shuffle button toggles the same state and fires `onShuffleChange`.

To drop many tracks from the playing playlist without touching the current one:

```typescript
await PlayerQueue.removeTracksFromPlaylist(playlistId, ['track-2', 'track-5'])
```

## Volume Control

Control the playback volume level.

### `setVolume(volume: number): boolean`

Sets the playback volume level.

**Parameters:**

- `volume: number` - Volume level between 0 and 100
  - `0` - Mute (no sound)
  - `50` - Half volume
  - `100` - Maximum volume

**Returns:** `true` if successful, `false` otherwise (e.g., if player is not initialized)

**Example:**

```typescript
import { TrackPlayer } from 'react-native-nitro-player'

// Set volume to 50%
const success = TrackPlayer.setVolume(50)
if (success) {
  console.log('Volume set successfully')
} else {
  console.warn('Failed to set volume')
}

// Mute the player
TrackPlayer.setVolume(0)

// Set to maximum volume
TrackPlayer.setVolume(100)

// Incremental volume control
const currentVolume = 50
TrackPlayer.setVolume(currentVolume + 10) // Increase by 10%
TrackPlayer.setVolume(currentVolume - 10) // Decrease by 10%
```

**Note:** The volume value is automatically clamped to the 0-100 range. Values outside this range will be clamped to the nearest valid value.

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

  // Get complete player state (alternative to individual hooks)
  const nowPlaying = useNowPlaying()

  return (
    <View>
      {track && (
        <Text>Now Playing: {track.title} by {track.artist}</Text>
      )}
      <Text>State: {state}</Text>
      <Text>Progress: {position} / {totalDuration}</Text>
      {/* Or use useNowPlaying for all state at once */}
      <Text>Now Playing State: {nowPlaying.currentState}</Text>
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
TrackPlayer.onAndroidAutoConnectionChange((connected) => {
  console.log('Android Auto:', connected ? 'Connected' : 'Disconnected')
})
```

### Getting Player State

```typescript
import { TrackPlayer } from 'react-native-nitro-player'

const state = await TrackPlayer.getState()

console.log(state.currentState) // 'playing' | 'paused' | 'stopped'
console.log(state.currentPosition) // current position in seconds
console.log(state.totalDuration) // total duration in seconds
console.log(state.currentTrack) // current TrackItem or null
console.log(state.currentPlaylistId) // current playlist ID or null
console.log(state.currentIndex) // current track index in playlist
console.log(state.currentPlayingType) // 'playlist' | 'play-next' | 'up-next' | 'not-playing'
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
  // key-value pairs for arbitrary data
  extraPayload?: {
    [key: string]: string | number | boolean | Record<string, unknown>
  }
}
```

### Custom Track Metadata (extraPayload)

```typescript
const track = {
  // ... standard fields
  extraPayload: {
    externalId: 'sp-12345',
    rating: 4.5,
    tags: ['chill', 'instrumental']
  }
}

// Accessing it later
const { track } = useOnChangeTrack()
if (track?.extraPayload?.rating > 4) {
  console.log('High rated track playing!')
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
- ✅ **Remote Controls**: AirPods, lock screen, and notification skip controls
- ✅ **Volume Control**: Adjust playback volume (0-100)
- ✅ **React Hooks**: Built-in hooks for reactive state management
- ✅ **Event Listeners**: Listen to track changes, state changes, and more
- ✅ **Android Auto Support**: Control playback from Android Auto with customizable UI
- ✅ **CarPlay Support**: Control playback from CarPlay (iOS)
- ✅ **Notification Controls**: Show playback controls in notifications
- ✅ **Progress Tracking**: Real-time playback progress updates
- ✅ **Offline Downloads**: Download tracks and playlists for offline playback
- ✅ **Google Cast**: Seamless casting to Chromecast / Google TV (iOS & Android)

## TypeScript Support

The library is written in TypeScript and includes full type definitions. All types are exported for your convenience:

```typescript
import type {
  TrackItem,
  Playlist,
  PlayerState,
  TrackPlayerState,
  CurrentPlayingType,
  QueueOperation,
  Reason,
  PlayerConfig,
  MediaLibrary,
  MediaItem,
  LayoutType,
  MediaType,
  // Download types
  DownloadConfig,
  DownloadProgress,
  DownloadedTrack,
  DownloadedPlaylist,
  DownloadTask,
  DownloadState,
  DownloadError,
  DownloadStorageInfo,
  PlaybackSource,
} from 'react-native-nitro-player'
```

## Platform Support

- ✅ **iOS**: Full support with CarPlay integration
- ✅ **Android**: Full support with Android Auto integration
- 🎯 **Android Auto Media Library**: Android-only feature for customizing the Android Auto UI

## License

MIT
