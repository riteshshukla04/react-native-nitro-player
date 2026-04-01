---
sidebar_position: 3
sidebar_label: '📋 PlayerQueue'
tags: [android, ios]
---

# PlayerQueue

<span className="badge badge--success">Android</span> <span className="badge badge--secondary">iOS</span>

The `PlayerQueue` object manages playlists and tracks.

**Playlist mutations** (`createPlaylist`, `loadPlaylist`, `addTracksToPlaylist`, …) return **Promises** and reject on failure. **`getPlaylist`** and **`getAllPlaylists`** are synchronous reads from the native cache.

## Methods

### `createPlaylist(name, description, artwork)`

Creates a new playlist.
- **name**: `string`
- **description**: `string` (optional)
- **artwork**: `string` (optional URL)
- **Returns**: `Promise<string>` (playlistId)

```typescript
const playlistId = await PlayerQueue.createPlaylist(
  'My Jams',
  'Favorites',
  'https://artwork.url'
)
```

### `deletePlaylist(id)`

Deletes a playlist by ID.
- **id**: `string`
- **Returns:** `Promise<void>`

```typescript
await PlayerQueue.deletePlaylist('playlist-id')
```

### `updatePlaylist(id, name, description, artwork)`

Updates playlist metadata.
- **id**: `string`
- **name**: `string` (optional)
- **description**: `string` (optional)
- **artwork**: `string` (optional)
- **Returns:** `Promise<void>`

```typescript
await PlayerQueue.updatePlaylist('playlist-id', 'New Name', 'New Description')
```

### `getPlaylist(id)`

Gets a specific playlist object.
- **id**: `string`
- **Returns**: [`Playlist`](#playlist) | `null`

```typescript
const playlist = PlayerQueue.getPlaylist('playlist-id')
```

### `getAllPlaylists()`

Gets all available playlists.
- **Returns**: [`Playlist[]`](#playlist)

```typescript
const playlists = PlayerQueue.getAllPlaylists()
```

### `loadPlaylist(id)`

Loads a playlist into the player context.
- **id**: `string`
- **Returns:** `Promise<void>`

```typescript
await PlayerQueue.loadPlaylist('playlist-id')
```

### `getCurrentPlaylistId()`

Gets the ID of the currently playing playlist.
- **Returns**: `string` | `null`

```typescript
const id = PlayerQueue.getCurrentPlaylistId()
```

### `addTrackToPlaylist(pid, track)`

Adds a track to a playlist.
- **pid**: `string` (playlistId)
- **track**: [`TrackItem`](#trackitem)
- **Returns:** `Promise<void>`

```typescript
await PlayerQueue.addTrackToPlaylist('playlist-id', trackItem)
```

### `addTracksToPlaylist(pid, tracks)`

Adds multiple tracks to a playlist.
- **pid**: `string` (playlistId)
- **tracks**: [`TrackItem[]`](#trackitem)
- **Returns:** `Promise<void>`

```typescript
await PlayerQueue.addTracksToPlaylist('playlist-id', [track1, track2])
```

### `removeTrackFromPlaylist(pid, tid)`

Removes a track from a playlist.
- **pid**: `string` (playlistId)
- **tid**: `string` (trackId)
- **Returns:** `Promise<void>`

```typescript
await PlayerQueue.removeTrackFromPlaylist('playlist-id', 'track-id')
```

### `reorderTrackInPlaylist(pid, tid, idx)`

Moves a track to a new position in the playlist.
- **pid**: `string` (playlistId)
- **tid**: `string` (trackId)
- **idx**: `number` (new index)
- **Returns:** `Promise<void>`

```typescript
await PlayerQueue.reorderTrackInPlaylist('playlist-id', 'track-id', 0)
```

## Types

### `Playlist`

Represents a collection of tracks.

```typescript
interface Playlist {
  id: string
  name: string
  description?: string
  artwork?: string
  tracks: TrackItem[]
}
```

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
