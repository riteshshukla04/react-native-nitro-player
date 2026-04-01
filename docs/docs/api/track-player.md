---
sidebar_position: 2
sidebar_label: '🎵 TrackPlayer'
tags: [android, ios]
---

# TrackPlayer

<span className="badge badge--success">Android</span> <span className="badge badge--secondary">iOS</span>

The `TrackPlayer` object is the main interface for controlling playback.

Unless noted, **commands** return `Promise<void>` (or another `Promise`) and **reject** on failure. **`getRepeatMode()`** is a synchronous read. Use `await` or explicit `.catch()` / `try/catch` as needed.

## Methods

### `play()`

Resumes playback of the current track. **Returns:** `Promise<void>`

```typescript
await TrackPlayer.play()
```

### `pause()`

Pauses playback. **Returns:** `Promise<void>`

```typescript
await TrackPlayer.pause()
```

### `playSong(songId, fromPlaylist?)`

Plays a specific song. Optionally specify a playlist ID to ensure context.
- **songId**: `string`
- **fromPlaylist**: `string` (optional)
- **Returns:** `Promise<void>`

```typescript
await TrackPlayer.playSong('song-1', 'playlist-1')
```

### `skipToNext()`

Skips to the next track in the queue. **Returns:** `Promise<void>`

```typescript
await TrackPlayer.skipToNext()
```

### `skipToPrevious()`

Skips to the previous track. **Returns:** `Promise<void>`

```typescript
await TrackPlayer.skipToPrevious()
```

### `seek(position)`

Seeks to a specific time position in seconds.
- **position**: `number` (seconds)
- **Returns:** `Promise<void>`

```typescript
await TrackPlayer.seek(30) // Seek to 30 seconds
```

### `setPlaybackSpeed(speed)`

Sets the playback speed multiplier.
- **speed**: `number` (e.g. `0.5`, `1`, `1.5`, `2`)

```typescript
await TrackPlayer.setPlaybackSpeed(1.5) // 1.5x speed
```

### `getPlaybackSpeed()`

Gets the current playback speed multiplier.
- **Returns**: `Promise<number>`

```typescript
const speed = await TrackPlayer.getPlaybackSpeed() // e.g. 1, 1.5, 2
```

### `setVolume(volume)`

Sets the playback volume (0–100).
- **volume**: `number`
- **Returns:** `Promise<void>`

```typescript
await TrackPlayer.setVolume(50)
```

### `setRepeatMode(mode)`

Sets the repeat mode.
- **mode**: [`RepeatMode`](#repeatmode)
- **Returns:** `Promise<void>`

### `getRepeatMode()`

Returns the current repeat mode (synchronous read).
- **Returns:** [`RepeatMode`](#repeatmode)

```typescript
await TrackPlayer.setRepeatMode('track')
const mode = TrackPlayer.getRepeatMode()
```

### `addToUpNext(trackId)`

Adds a track to the **up-next queue** (FIFO).
- **trackId**: `string`
- **Returns:** `Promise<void>`

```typescript
await TrackPlayer.addToUpNext('song-id')
```

### `playNext(trackId)`

Adds a track to the **play-next stack** (LIFO). Plays immediately after current song.
- **trackId**: `string`
- **Returns:** `Promise<void>`

```typescript
await TrackPlayer.playNext('song-id')
```

### `getActualQueue()`

Returns the full playback queue including temporary tracks.
- **Returns**: `Promise<`[`TrackItem[]`](#trackitem)`>`

```typescript
const queue = await TrackPlayer.getActualQueue()
```

### `getState()`

Gets a snapshot of the current player state (async; resolves when native state is read).
- **Returns**: `Promise<`[`PlayerState`](#playerstate)`>`

```typescript
const state = await TrackPlayer.getState()
```

### `skipToIndex(index)`

Skips to a specific index in the actual queue.
- **index**: `number`
- **Returns:** `Promise<boolean>`

```typescript
const ok = await TrackPlayer.skipToIndex(2)
```

### `configure(config)`

Configures player settings.
- **config**: [`PlayerConfig`](#playerconfig)
- **Returns:** `Promise<void>`

```typescript
await TrackPlayer.configure({
  androidAutoEnabled: true,
  carPlayEnabled: true,
  showInNotification: true,
})
```

### `updateTracks(tracks)`

Updates matching tracks (by `id`) across all playlists. **`url` may be an empty string** to support lazy URL resolution; use `onTracksNeedUpdate`, `getTracksNeedingUrls`, and `getNextTracks` to fill URLs before playback needs them.

- **tracks**: [`TrackItem[]`](#trackitem)
- **Returns:** `Promise<void>`

```typescript
await TrackPlayer.updateTracks([
  { ...track, url: 'https://resolved.cdn/track.mp3' },
])
```

### `getTracksById(trackIds)`

Fetches full `TrackItem` objects for the given ids from loaded playlists.

- **Returns:** `Promise<TrackItem[]>`

### `getTracksNeedingUrls()`

Tracks in the current playlist with missing or empty `url`.

- **Returns:** `Promise<TrackItem[]>`

### `getNextTracks(count)`

Upcoming tracks from the current position (useful for preload).

- **Returns:** `Promise<TrackItem[]>`

### `getCurrentTrackIndex()`

Current index in the active playlist, or `-1` if none.

- **Returns:** `Promise<number>`

### `onTracksNeedUpdate(callback)`

Called when upcoming tracks may need URLs (lookahead preloading for Android Auto / CarPlay, etc.).

### Temporary queue (`playNext` / `upNext`)

Inspect or edit the **play-next** stack (LIFO) and **up-next** queue (FIFO).

| Method | Returns |
|--------|---------|
| `removeFromPlayNext(trackId)` | `Promise<boolean>` |
| `removeFromUpNext(trackId)` | `Promise<boolean>` |
| `clearPlayNext()` | `Promise<void>` |
| `clearUpNext()` | `Promise<void>` |
| `reorderTemporaryTrack(trackId, newIndex)` | `Promise<boolean>` |
| `getPlayNextQueue()` | `Promise<TrackItem[]>` |
| `getUpNextQueue()` | `Promise<TrackItem[]>` |

### `onTemporaryQueueChange(callback)`

Fired when the play-next stack or up-next queue changes.

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
  /** Upcoming tracks to preload URLs for (default: 5) */
  lookaheadCount?: number
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
