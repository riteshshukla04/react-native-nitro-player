---
sidebar_position: 2
sidebar_label: '🎵 TrackPlayer'
tags: [android, ios]
---

# TrackPlayer

<span className="badge badge--success">Android</span> <span className="badge badge--secondary">iOS</span>

The `TrackPlayer` object is the main interface for controlling playback.

## Methods

### `play()`

Resumes playback of the current track.

```typescript
TrackPlayer.play()
```

### `pause()`

Pauses playback.

```typescript
TrackPlayer.pause()
```

### `playSong(songId, fromPlaylist?)`

Plays a specific song. Optionally specify a playlist ID to ensure context.
- **songId**: `string`
- **fromPlaylist**: `string` (optional)

```typescript
await TrackPlayer.playSong('song-1', 'playlist-1')
```

### `skipToNext()`

Skips to the next track in the queue.

```typescript
TrackPlayer.skipToNext()
```

### `skipToPrevious()`

Skips to the previous track.

```typescript
TrackPlayer.skipToPrevious()
```

### `seek(position)`

Seeks to a specific time position in seconds.
- **position**: `number` (seconds)

```typescript
TrackPlayer.seek(30) // Seek to 30 seconds
```

### `setVolume(volume)`

Sets the playback volume (0-100).
- **volume**: `number`

```typescript
TrackPlayer.setVolume(50)
```

### `setRepeatMode(mode)`

Sets the repeat mode.
- **mode**: [`RepeatMode`](#repeatmode)

```typescript
TrackPlayer.setRepeatMode('track')
```

### `addToUpNext(trackId)`

Adds a track to the **up-next queue** (FIFO).
- **trackId**: `string`

```typescript
await TrackPlayer.addToUpNext('song-id')
```

### `playNext(trackId)`

Adds a track to the **play-next stack** (LIFO). Plays immediately after current song.
- **trackId**: `string`

```typescript
await TrackPlayer.playNext('song-id')
```

### `getActualQueue()`

Returns the full playback queue including temporary tracks.
- **Returns**: [`TrackItem[]`](#trackitem)

```typescript
const queue = await TrackPlayer.getActualQueue()
```

### `getState()`

Gets the current player state immediately.
- **Returns**: [`PlayerState`](#playerstate)

```typescript
const state = await TrackPlayer.getState()
```

### `skipToIndex(index)`

Skips to a specific index in the actual queue.
- **index**: `number`

```typescript
await TrackPlayer.skipToIndex(2)
```

### `configure(config)`

Configures player settings.
- **config**: [`PlayerConfig`](#playerconfig)

```typescript
TrackPlayer.configure({
  androidAutoEnabled: true,
  carPlayEnabled: true,
  showInNotification: true,
})
```

### `isAndroidAutoConnected()`

Checks if Android Auto is currently connected.
- **Returns**: `boolean`

```typescript
const isConnected = TrackPlayer.isAndroidAutoConnected()
```

## Types

### `TrackItem`

Represents a single audio track.

```typescript
interface TrackItem {
  id: string
  title: string
  artist: string
  album: string
  duration: number
  url: string
  artwork?: string
  extraPayload?: Record<string, any>
}
```

### `PlayerConfig`

Configuration options for the player.

```typescript
interface PlayerConfig {
  androidAutoEnabled?: boolean
  carPlayEnabled?: boolean
  showInNotification?: boolean
}
```

### `RepeatMode`

Playback repeat mode.

```typescript
type RepeatMode = 'off' | 'track' | 'Playlist'
```

### `PlayerState`

Snapshot of the current player state.

```typescript
interface PlayerState {
  currentTrack: TrackItem | null
  currentPosition: number
  totalDuration: number
  currentState: 'playing' | 'paused' | 'stopped'
  currentPlaylistId: string | null
  currentIndex: number
  currentPlayingType: 'playlist' | 'up-next' | 'play-next' | 'not-playing'
}
```
