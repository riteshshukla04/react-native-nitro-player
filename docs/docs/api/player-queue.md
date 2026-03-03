---
sidebar_position: 3
sidebar_label: '📋 PlayerQueue'
tags: [android, ios]
---

# PlayerQueue

<span className="badge badge--success">Android</span> <span className="badge badge--secondary">iOS</span>

The `PlayerQueue` object manages playlists and tracks.

## Methods

### `createPlaylist(name, description, artwork)`

Creates a new playlist.
- **name**: `string`
- **description**: `string` (optional)
- **artwork**: `string` (optional URL)
- **Returns**: `string` (playlistId)

```typescript
const playlistId = PlayerQueue.createPlaylist('My Jams', 'Favorites', 'https://artwork.url')
```

### `deletePlaylist(id)`

Deletes a playlist by ID.
- **id**: `string`

```typescript
PlayerQueue.deletePlaylist('playlist-id')
```

### `updatePlaylist(id, name, description, artwork)`

Updates playlist metadata.
- **id**: `string`
- **name**: `string` (optional)
- **description**: `string` (optional)
- **artwork**: `string` (optional)

```typescript
PlayerQueue.updatePlaylist('playlist-id', 'New Name', 'New Description')
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

```typescript
PlayerQueue.loadPlaylist('playlist-id')
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

```typescript
PlayerQueue.addTrackToPlaylist('playlist-id', trackItem)
```

### `addTracksToPlaylist(pid, tracks)`

Adds multiple tracks to a playlist.
- **pid**: `string` (playlistId)
- **tracks**: [`TrackItem[]`](#trackitem)

```typescript
PlayerQueue.addTracksToPlaylist('playlist-id', [track1, track2])
```

### `removeTrackFromPlaylist(pid, tid)`

Removes a track from a playlist.
- **pid**: `string` (playlistId)
- **tid**: `string` (trackId)

```typescript
PlayerQueue.removeTrackFromPlaylist('playlist-id', 'track-id')
```

### `reorderTrackInPlaylist(pid, tid, idx)`

Moves a track to a new position in the playlist.
- **pid**: `string` (playlistId)
- **tid**: `string` (trackId)
- **idx**: `number` (new index)

```typescript
PlayerQueue.reorderTrackInPlaylist('playlist-id', 'track-id', 0)
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
