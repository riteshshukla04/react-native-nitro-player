---
sidebar_position: 4
sidebar_label: '📥 DownloadManager'
tags: [android, ios]
---

# DownloadManager

<span className="badge badge--success">Android</span> <span className="badge badge--secondary">iOS</span>

The `DownloadManager` handles offline playback and file management. React Native Nitro Player supports downloading tracks and playlists for offline playback, enabling users to save music locally and play it without an internet connection.

## Prerequisites

### Android

Add the following to your `AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />

    <application>
        <!-- Required for background downloads with notifications -->
        <service
            android:name="androidx.work.impl.foreground.SystemForegroundService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />
    </application>
</manifest>
```

> [!IMPORTANT]
> The `SystemForegroundService` with `foregroundServiceType="dataSync"` is required for downloads to work properly in the background and display download progress notifications.

### iOS

No additional setup required for iOS.

## Quick Start

### 1. Configure Download Manager

```typescript
import { DownloadManager } from 'react-native-nitro-player'

DownloadManager.configure({
  maxConcurrentDownloads: 3,
  autoRetry: true,
  maxRetryAttempts: 3,
  backgroundDownloadsEnabled: true,
  downloadArtwork: true,
  wifiOnlyDownloads: false,
  storageLocation: 'private', // 'private' or 'public'
})
```

### 2. Monitor Progress

```typescript
import { useDownloadProgress } from 'react-native-nitro-player'

function DownloadProgressView() {
  const { progressList, overallProgress, isDownloading } = useDownloadProgress()

  return (
    <View>
      <Text>Overall Progress: {Math.round(overallProgress * 100)}%</Text>
      <Text>Downloading: {isDownloading ? 'Yes' : 'No'}</Text>

      {progressList.map((progress) => (
        <View key={progress.trackId}>
          <Text>{progress.trackId}</Text>
          <Text>Progress: {Math.round(progress.progress * 100)}%</Text>
          <Text>State: {progress.state}</Text>
        </View>
      ))}
    </View>
  )
}
```

## API Reference

### Configuration

#### `configure(config)`
Configures download settings.
- **config**: [`DownloadConfig`](#downloadconfig)

```typescript
DownloadManager.configure({
  maxConcurrentDownloads: 3,
  backgroundDownloadsEnabled: true,
  downloadArtwork: true,
})
```

#### `getConfig()`
Returns the current configuration.
- **Returns**: [`DownloadConfig`](#downloadconfig)

```typescript
const config = DownloadManager.getConfig()
```

### Downloading

#### `downloadTrack(track, playlistId?)`
Downloads a single track.
- **track**: [`TrackItem`](./player-queue#trackitem)
- **playlistId**: `string` (optional)
- **Returns**: `Promise<string>` (downloadId)

```typescript
const downloadId = await DownloadManager.downloadTrack(trackItem)
```

#### `downloadPlaylist(playlistId, tracks)`
Downloads all tracks in a playlist.
- **playlistId**: `string`
- **tracks**: [`TrackItem[]`](./player-queue#trackitem)
- **Returns**: `Promise<string[]>` (downloadIds)

```typescript
const ids = await DownloadManager.downloadPlaylist('playlist-id', tracks)
```

#### `retryDownload(downloadId)`
Retries a failed download.
- **downloadId**: `string`

```typescript
await DownloadManager.retryDownload('download-id')
```

### Control

#### `pauseDownload(downloadId)`
Pauses an active download.
- **downloadId**: `string`

```typescript
await DownloadManager.pauseDownload('download-id')
```

#### `resumeDownload(downloadId)`
Resumes a paused download.
- **downloadId**: `string`

```typescript
await DownloadManager.resumeDownload('download-id')
```

#### `cancelDownload(downloadId)`
Cancels a download and removes partial files.
- **downloadId**: `string`

```typescript
await DownloadManager.cancelDownload('download-id')
```

#### `pauseAllDownloads()`
Pauses all active downloads.
```typescript
await DownloadManager.pauseAllDownloads()
```

#### `resumeAllDownloads()`
Resumes all paused downloads.
```typescript
await DownloadManager.resumeAllDownloads()
```

#### `cancelAllDownloads()`
Cancels all active downloads.
```typescript
await DownloadManager.cancelAllDownloads()
```

### Status & Queries

#### `getQueueStatus()`
Gets the overall status of the download queue.
- **Returns**: [`DownloadQueueStatus`](#downloadqueuestatus)

```typescript
const status = DownloadManager.getQueueStatus()
// { isDownloading: true, pendingCount: 2, activeCount: 1 }
```

#### `getActiveDownloads()`
Returns a list of all active download tasks.
- **Returns**: [`DownloadTask[]`](#downloadtask)

```typescript
const tasks = DownloadManager.getActiveDownloads()
```

#### `getDownloadTask(downloadId)`
Gets a specific download task by ID.
- **downloadId**: `string`
- **Returns**: [`DownloadTask`](#downloadtask) | `null`

```typescript
const task = DownloadManager.getDownloadTask('download-id')
```

#### `isDownloading(trackId)`
Checks if a specific track is currently downloading.
- **trackId**: `string`
- **Returns**: `boolean`

```typescript
const isDownloading = DownloadManager.isDownloading('track-id')
```

#### `getDownloadState(trackId)`
Gets the precise download state for a track.
- **trackId**: `string`
- **Returns**: [`DownloadState`](#downloadstate) | `null`

```typescript
const state = DownloadManager.getDownloadState('track-id')
```

#### `isTrackDownloaded(trackId)`
Checks if a track is fully downloaded.
- **trackId**: `string`
- **Returns**: `boolean`

```typescript
const isDownloaded = DownloadManager.isTrackDownloaded('track-id')
```

#### `isPlaylistDownloaded(playlistId)`
Checks if an entire playlist is fully downloaded.
- **playlistId**: `string`
- **Returns**: `boolean`

```typescript
const isComplete = DownloadManager.isPlaylistDownloaded('playlist-id')
```

#### `isPlaylistPartiallyDownloaded(playlistId)`
Checks if a playlist has at least one downloaded track.
- **playlistId**: `string`
- **Returns**: `boolean`

```typescript
const isPartial = DownloadManager.isPlaylistPartiallyDownloaded('playlist-id')
```

### Downloaded Content

#### `getAllDownloadedTracks()`
Returns a list of all downloaded tracks.
- **Returns**: [`DownloadedTrack[]`](#downloadedtrack)

```typescript
const tracks = DownloadManager.getAllDownloadedTracks()
```

#### `getDownloadedTrack(trackId)`
Gets a specific downloaded track object.
- **trackId**: `string`
- **Returns**: [`DownloadedTrack`](#downloadedtrack) | `null`

```typescript
const track = DownloadManager.getDownloadedTrack('track-id')
```

#### `getAllDownloadedPlaylists()`
Returns a list of all downloaded playlists.
- **Returns**: [`DownloadedPlaylist[]`](#downloadedplaylist)

```typescript
const playlists = DownloadManager.getAllDownloadedPlaylists()
```

#### `getDownloadedPlaylist(playlistId)`
Gets a specific downloaded playlist object.
- **playlistId**: `string`
- **Returns**: [`DownloadedPlaylist`](#downloadedplaylist) | `null`

```typescript
const playlist = DownloadManager.getDownloadedPlaylist('playlist-id')
```

#### `getLocalPath(trackId)`
Gets the local file path for a downloaded track.
- **trackId**: `string`
- **Returns**: `string` | `null`

```typescript
const path = DownloadManager.getLocalPath('track-id')
```

#### `getEffectiveUrl(track)`
Gets the effective URL for a track (local if downloaded, remote otherwise).
- **track**: [`TrackItem`](./player-queue#trackitem)
- **Returns**: `string`

```typescript
const url = DownloadManager.getEffectiveUrl(track)
```

### Storage Management

#### `getStorageInfo()`
Gets storage usage information.
- **Returns**: [`Promise<DownloadStorageInfo>`](#downloadstorageinfo)

```typescript
const info = await DownloadManager.getStorageInfo()
// { used: 1024, total: 50000, free: 48976 }
```

#### `deleteDownloadedTrack(trackId)`
Deletes a downloaded track from storage.
- **trackId**: `string`

```typescript
await DownloadManager.deleteDownloadedTrack('track-id')
```

#### `deleteDownloadedPlaylist(playlistId)`
Deletes a downloaded playlist and all its tracks.
- **playlistId**: `string`

```typescript
await DownloadManager.deleteDownloadedPlaylist('playlist-id')
```

#### `deleteAllDownloads()`
Deletes all downloaded content.
```typescript
await DownloadManager.deleteAllDownloads()
```

### Playback Preference

#### `setPlaybackSourcePreference(pref)`
Sets the preference for playback source.
- **pref**: [`PlaybackSource`](#playbacksource)

- `'auto'`: Use downloaded file if available, otherwise stream.
- `'download'`: Only play downloaded files.
- `'network'`: Always stream from network.

```typescript
DownloadManager.setPlaybackSourcePreference('auto')
```

#### `getPlaybackSourcePreference()`
Gets the current playback source preference.
- **Returns**: [`PlaybackSource`](#playbacksource)

```typescript
const pref = DownloadManager.getPlaybackSourcePreference()
```

## Types

### `DownloadConfig`

Configuration options for the download manager.

```typescript
interface DownloadConfig {
  maxConcurrentDownloads?: number
  autoRetry?: boolean
  maxRetryAttempts?: number
  backgroundDownloadsEnabled?: boolean
  downloadArtwork?: boolean
  customDownloadPath?: string | null
  wifiOnlyDownloads?: boolean
  storageLocation?: 'private' | 'public'
}
```

### `DownloadTask`

Represents an active or completed download task.

```typescript
interface DownloadTask {
  downloadId: string
  trackId: string
  playlistId?: string | null
  state: DownloadState
  progress: DownloadProgress
  createdAt: number
  startedAt?: number | null
  completedAt?: number | null
  error?: DownloadError | null
  retryCount: number
}
```

### `DownloadState`

Current state of a download.

```typescript
type DownloadState =
  | 'pending'
  | 'downloading'
  | 'paused'
  | 'completed'
  | 'failed'
  | 'cancelled'
```

### `DownloadProgress`

Progress information for a download.

```typescript
interface DownloadProgress {
  trackId: string
  downloadId: string
  bytesDownloaded: number
  totalBytes: number
  progress: number // 0.0 to 1.0
  state: DownloadState
}
```

### `DownloadedTrack`

Details of a downloaded track.

```typescript
interface DownloadedTrack {
  trackId: string
  originalTrack: TrackItem
  localPath: string
  localArtworkPath?: string | null
  downloadedAt: number
  fileSize: number
  storageLocation: 'private' | 'public'
}
```

### `DownloadedPlaylist`

Details of a downloaded playlist.

```typescript
interface DownloadedPlaylist {
  playlistId: string
  originalPlaylist: Playlist
  downloadedTracks: DownloadedTrack[]
  totalSize: number
  downloadedAt: number
  isComplete: boolean
}
```

### `DownloadStorageInfo`

Storage usage statistics.

```typescript
interface DownloadStorageInfo {
  used: number
  total: number
  free: number
}
```

### `DownloadQueueStatus`

Status of the download queue.

```typescript
interface DownloadQueueStatus {
  pendingCount: number
  activeCount: number
  completedCount: number
  failedCount: number
  totalBytesToDownload: number
  totalBytesDownloaded: number
  overallProgress: number
}
```

### `PlaybackSource`

Source preference for playback.

```typescript
type PlaybackSource = 'auto' | 'download' | 'network'
```

## Best Practices

1. **Configure on App Start**: Configure the download manager when your app initializes.
2. **Handle Errors**: Always listen to `onDownloadStateChange` to handle download errors gracefully.
3. **WiFi-Only for Large Downloads**: Enable `wifiOnlyDownloads` for better user experience.
4. **Monitor Storage**: Regularly check `getStorageInfo()` to avoid running out of space.
5. **Sync Downloads**: Call `syncDownloads()` periodically to clean up orphaned records.
6. **Use Auto Playback Source**: Set playback source to `'auto'` to seamlessly use downloaded tracks when available.
7. **Background Downloads**: Enable `backgroundDownloadsEnabled` for better user experience on Android.
