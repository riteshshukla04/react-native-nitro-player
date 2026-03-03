---
sidebar_position: 1
sidebar_label: '🎣 React Hooks'
tags: [android, ios]
---

# React Hooks

<span className="badge badge--success">Android</span> <span className="badge badge--secondary">iOS</span>


The library provides a set of React hooks to reactively track player state.

## `useOnChangeTrack`

Returns the current track and the reason why it changed.

```typescript
const { track, reason } = useOnChangeTrack()
```

- **Returns:**
  - `track`: The `TrackItem` that is currently playing, or `undefined`.
  - `reason`: The `Reason` for the change (e.g., `'user_action'`, `'skip'`, `'end'`).

## `useOnPlaybackStateChange`

Returns the current playback state.

```typescript
const { state, reason } = useOnPlaybackStateChange()
```

- **Returns:**
  - `state`: `TrackPlayerState` (`'playing'`, `'paused'`, `'stopped'`, etc.)
  - `reason`: The reason for the state change.

## `useOnPlaybackProgressChange`

Returns real-time playback progress.

```typescript
const { position, totalDuration, isManuallySeeked } = useOnPlaybackProgressChange()
```

- **Returns:**
  - `position`: Current playback position in seconds.
  - `totalDuration`: Total duration of the track in seconds.
  - `isManuallySeeked`: `true` if the user just performed a seek.

## `useNowPlaying`

Returns the complete player state in one object.

```typescript
const playerState = useNowPlaying()
```

- **Returns**: `PlayerState` object containing:
  - `currentTrack`: `TrackItem | null`
  - `totalDuration`: `number`
  - `currentState`: `TrackPlayerState`
  - `currentPlaylistId`: `string | null`
  - `currentIndex`: `number`
  - `currentPlayingType`: `'playlist' | 'play-next' | 'up-next' | 'not-playing'`

## `useActualQueue`

Returns the effective playback queue, including temporary tracks.

```typescript
const { queue, refreshQueue, isLoading } = useActualQueue()
```

- **Returns:**
  - `queue`: Array of `TrackItem` in the order they will play.
  - `refreshQueue`: Function to manually refresh the queue.
  - `isLoading`: Boolean status.

## `usePlaylist`

Manages and retrieves playlist data.

```typescript
const { allPlaylists, allTracks, currentPlaylist } = usePlaylist()
```

- **Returns:**
  - `allPlaylists`: Array of all available `Playlist` objects.
  - `allTracks`: Aggregated list of tracks from all playlists.
  - `currentPlaylist`: The currently active `Playlist`.

## `useEqualizer`

Controls the 5-band equalizer.

```typescript
const { isEnabled, bands, setBandGain, setEnabled } = useEqualizer()
```

## `useDownloadProgress`

Tracks download progress for specific tracks.

```typescript
const { progress, state } = useDownloadProgress(trackId)
```

## `useDownloadedTracks`

Retrieves all downloaded content.

```typescript
const { downloadedTracks, downloadedPlaylists } = useDownloadedTracks()
```

## `useAndroidAutoConnection`

Monitors connection to Android Auto.

```typescript
const { isConnected } = useAndroidAutoConnection()
```

## `useAudioDevices` (Android)

Returns available audio output devices (Android only).

```typescript
const devices = useAudioDevices()
```
