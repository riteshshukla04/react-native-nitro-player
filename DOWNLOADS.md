# Offline Downloads

React Native Nitro Player supports downloading tracks and playlists for offline playback. This feature enables users to save music locally and play it without an internet connection.

## Prerequisites

### Android Setup

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

### iOS Setup

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

### 2. Download Tracks

```typescript
import { DownloadManager } from 'react-native-nitro-player'
import type { TrackItem } from 'react-native-nitro-player'

const track: TrackItem = {
  id: '1',
  title: 'Song Title',
  artist: 'Artist Name',
  album: 'Album Name',
  duration: 180.0,
  url: 'https://example.com/song.mp3',
  artwork: 'https://example.com/artwork.jpg',
}

// Download a single track
const downloadId = await DownloadManager.downloadTrack(track)

// Download a track as part of a playlist
const downloadId = await DownloadManager.downloadTrack(track, 'playlist-id')
```

### 3. Download Playlists

```typescript
import { PlayerQueue, DownloadManager } from 'react-native-nitro-player'

const playlist = PlayerQueue.getPlaylist('playlist-id')
const downloadIds = await DownloadManager.downloadPlaylist(
  playlist.id,
  playlist.tracks
)
```

### 4. Monitor Download Progress

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

## React Hooks

### `useDownloadProgress(options?)`

Track download progress for one or more tracks.

**Options:**

- `trackIds?: string[]` - Track specific track IDs
- `downloadIds?: string[]` - Track specific download IDs
- `activeOnly?: boolean` - Only track active downloads

**Returns:**

- `progressMap: Map<string, DownloadProgress>` - Map of trackId to progress
- `progressList: DownloadProgress[]` - Array of all tracked progress
- `overallProgress: number` - Overall progress (0-1)
- `isDownloading: boolean` - Whether any download is in progress
- `getProgress: (trackId: string) => DownloadProgress | undefined` - Get progress for a specific track

**Example:**

```typescript
import { useDownloadProgress } from 'react-native-nitro-player'

function TrackDownloadProgress({ trackId }: { trackId: string }) {
  const { getProgress } = useDownloadProgress({ trackIds: [trackId] })
  const progress = getProgress(trackId)

  if (!progress) return null

  return (
    <View>
      <Text>{Math.round(progress.progress * 100)}%</Text>
      <ProgressBar progress={progress.progress} />
    </View>
  )
}
```

### `useDownloadedTracks()`

Access all downloaded tracks and playlists.

**Returns:**

- `downloadedTracks: DownloadedTrack[]` - All downloaded tracks
- `downloadedPlaylists: DownloadedPlaylist[]` - All downloaded playlists
- `isTrackDownloaded: (trackId: string) => boolean` - Check if track is downloaded
- `isPlaylistDownloaded: (playlistId: string) => boolean` - Check if playlist is fully downloaded
- `isPlaylistPartiallyDownloaded: (playlistId: string) => boolean` - Check if playlist is partially downloaded
- `getDownloadedTrack: (trackId: string) => DownloadedTrack | undefined` - Get downloaded track info
- `getDownloadedPlaylist: (playlistId: string) => DownloadedPlaylist | undefined` - Get downloaded playlist info
- `refresh: () => void` - Refresh downloaded content list
- `isLoading: boolean` - Loading state

**Example:**

```typescript
import { useDownloadedTracks } from 'react-native-nitro-player'

function DownloadedTracksView() {
  const { downloadedTracks, isTrackDownloaded, refresh } = useDownloadedTracks()

  return (
    <View>
      <Button title="Refresh" onPress={refresh} />
      {downloadedTracks.map((track) => (
        <View key={track.trackId}>
          <Text>{track.originalTrack.title}</Text>
          <Text>Size: {(track.fileSize / 1024 / 1024).toFixed(2)} MB</Text>
        </View>
      ))}
    </View>
  )
}
```

## DownloadManager API

### Configuration

#### `configure(config: DownloadConfig): void`

Configure the download manager.

**Config Options:**

- `storageLocation?: 'private' | 'public'` - Where to store downloads
- `maxConcurrentDownloads?: number` - Max simultaneous downloads (default: 3)
- `autoRetry?: boolean` - Auto-retry failed downloads (default: true)
- `maxRetryAttempts?: number` - Max retry attempts (default: 3)
- `backgroundDownloadsEnabled?: boolean` - Enable background downloads (default: true)
- `downloadArtwork?: boolean` - Download artwork images (default: true)
- `customDownloadPath?: string | null` - Custom download directory
- `wifiOnlyDownloads?: boolean` - Only download on WiFi (default: false)

#### `getConfig(): DownloadConfig`

Get current configuration.

### Download Operations

#### `downloadTrack(track: TrackItem, playlistId?: string): Promise<string>`

Download a single track. Returns the download ID for tracking.

#### `downloadPlaylist(playlistId: string, tracks: TrackItem[]): Promise<string[]>`

Download an entire playlist. Returns array of download IDs.

### Download Control

#### `pauseDownload(downloadId: string): Promise<void>`

Pause an active download.

#### `resumeDownload(downloadId: string): Promise<void>`

Resume a paused download.

#### `cancelDownload(downloadId: string): Promise<void>`

Cancel a download and remove partial files.

#### `retryDownload(downloadId: string): Promise<void>`

Retry a failed download.

#### `pauseAllDownloads(): Promise<void>`

Pause all active downloads.

#### `resumeAllDownloads(): Promise<void>`

Resume all paused downloads.

#### `cancelAllDownloads(): Promise<void>`

Cancel all downloads.

### Download Status

#### `getDownloadTask(downloadId: string): DownloadTask | null`

Get download task information by download ID.

#### `getActiveDownloads(): DownloadTask[]`

Get all active download tasks.

#### `getQueueStatus(): DownloadQueueStatus`

Get overall download queue status.

**Returns:**

```typescript
{
  pendingCount: number
  activeCount: number
  completedCount: number
  failedCount: number
  totalBytesToDownload: number
  totalBytesDownloaded: number
  overallProgress: number // 0.0 to 1.0
}
```

#### `isDownloading(trackId: string): boolean`

Check if a track is currently downloading.

#### `getDownloadState(trackId: string): DownloadState | null`

Get download state for a track. States: `'pending'`, `'downloading'`, `'paused'`, `'completed'`, `'failed'`, `'cancelled'`.

### Downloaded Content Queries

#### `isTrackDownloaded(trackId: string): boolean`

Check if a track is downloaded.

#### `isPlaylistDownloaded(playlistId: string): boolean`

Check if all tracks in a playlist are downloaded.

#### `isPlaylistPartiallyDownloaded(playlistId: string): boolean`

Check if at least one track in a playlist is downloaded.

#### `getDownloadedTrack(trackId: string): DownloadedTrack | null`

Get downloaded track information.

#### `getAllDownloadedTracks(): DownloadedTrack[]`

Get all downloaded tracks.

#### `getDownloadedPlaylist(playlistId: string): DownloadedPlaylist | null`

Get downloaded playlist information.

#### `getAllDownloadedPlaylists(): DownloadedPlaylist[]`

Get all downloaded playlists.

#### `getLocalPath(trackId: string): string | null`

Get local file path for a downloaded track.

### Deletion

#### `deleteDownloadedTrack(trackId: string): Promise<void>`

Delete a downloaded track and its files.

#### `deleteDownloadedPlaylist(playlistId: string): Promise<void>`

Delete all tracks in a downloaded playlist.

#### `deleteAllDownloads(): Promise<void>`

Delete all downloaded content.

### Storage Management

#### `getStorageInfo(): Promise<DownloadStorageInfo>`

Get storage usage information.

**Returns:**

```typescript
{
  totalDownloadedSize: number // bytes
  trackCount: number
  playlistCount: number
  availableSpace: number // bytes
  totalSpace: number // bytes
}
```

#### `syncDownloads(): number`

Validate all downloads and remove orphaned records. Returns the number of orphaned records cleaned up.

### Playback Source Preference

#### `setPlaybackSourcePreference(preference: PlaybackSource): void`

Set playback source preference: `'auto'`, `'download'`, or `'network'`.

- `'auto'` - Use downloaded version if available, otherwise stream
- `'download'` - Only play downloaded tracks
- `'network'` - Always stream from network

#### `getPlaybackSourcePreference(): PlaybackSource`

Get current playback source preference.

#### `getEffectiveUrl(track: TrackItem): string`

Get the effective URL for a track (local or network based on preference and availability).

### Event Callbacks

#### `onDownloadProgress(callback: (progress: DownloadProgress) => void): void`

Listen to download progress updates.

```typescript
DownloadManager.onDownloadProgress(progress => {
  console.log(`${progress.trackId}: ${Math.round(progress.progress * 100)}%`)
})
```

#### `onDownloadStateChange(callback: (downloadId, trackId, state, error?) => void): void`

Listen to download state changes.

```typescript
DownloadManager.onDownloadStateChange((downloadId, trackId, state, error) => {
  console.log(`${trackId} is now ${state}`)
  if (error) {
    console.error('Download error:', error.message)
  }
})
```

#### `onDownloadComplete(callback: (downloadedTrack: DownloadedTrack) => void): void`

Listen to download completion events.

```typescript
DownloadManager.onDownloadComplete(downloadedTrack => {
  console.log(`Downloaded: ${downloadedTrack.originalTrack.title}`)
})
```

## Type Definitions

### `DownloadProgress`

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

```typescript
interface DownloadedTrack {
  trackId: string
  originalTrack: TrackItem
  localPath: string
  localArtworkPath?: string | null
  downloadedAt: number // Unix timestamp
  fileSize: number // bytes
  storageLocation: 'private' | 'public'
}
```

### `DownloadedPlaylist`

```typescript
interface DownloadedPlaylist {
  playlistId: string
  originalPlaylist: Playlist
  downloadedTracks: DownloadedTrack[]
  totalSize: number // bytes
  downloadedAt: number // Unix timestamp
  isComplete: boolean // All tracks downloaded
}
```

### `DownloadTask`

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

### `DownloadError`

```typescript
interface DownloadError {
  code: string
  message: string
  reason: DownloadErrorReason
  isRetryable: boolean
}

type DownloadErrorReason =
  | 'network_error'
  | 'storage_full'
  | 'file_not_found'
  | 'permission_denied'
  | 'invalid_url'
  | 'timeout'
  | 'unknown'
```

## Usage Examples

### Download with Progress Tracking

```typescript
import { DownloadManager, useDownloadProgress } from 'react-native-nitro-player'

function DownloadButton({ track }: { track: TrackItem }) {
  const [downloadId, setDownloadId] = useState<string | null>(null)
  const { getProgress } = useDownloadProgress({
    trackIds: [track.id],
  })

  const handleDownload = async () => {
    const id = await DownloadManager.downloadTrack(track)
    setDownloadId(id)
  }

  const progress = getProgress(track.id)

  return (
    <View>
      {!progress ? (
        <Button title="Download" onPress={handleDownload} />
      ) : (
        <View>
          <Text>{Math.round(progress.progress * 100)}%</Text>
          <Text>{progress.state}</Text>
        </View>
      )}
    </View>
  )
}
```

### Offline Playback

```typescript
import { DownloadManager, TrackPlayer } from 'react-native-nitro-player'

// Set preference to use downloaded tracks when available
DownloadManager.setPlaybackSourcePreference('auto')

// Play a track (will use local file if downloaded)
await TrackPlayer.playSong('track-id')

// Check what URL will be used
const track = { id: 'track-id', url: 'https://...' /* ... */ }
const effectiveUrl = DownloadManager.getEffectiveUrl(track)
console.log('Playing from:', effectiveUrl) // Local path or network URL
```

### Storage Management

```typescript
import { DownloadManager } from 'react-native-nitro-player'

async function showStorageInfo() {
  const info = await DownloadManager.getStorageInfo()

  console.log(`Downloaded: ${info.trackCount} tracks`)
  console.log(
    `Total size: ${(info.totalDownloadedSize / 1024 / 1024).toFixed(2)} MB`
  )
  console.log(`Available: ${(info.availableSpace / 1024 / 1024).toFixed(2)} MB`)
}

// Clean up orphaned records
const cleaned = DownloadManager.syncDownloads()
console.log(`Cleaned up ${cleaned} orphaned records`)
```

### Download Queue Management

```typescript
import { DownloadManager } from 'react-native-nitro-player'

// Get queue status
const status = DownloadManager.getQueueStatus()
console.log(`Active: ${status.activeCount}`)
console.log(`Pending: ${status.pendingCount}`)
console.log(`Overall: ${Math.round(status.overallProgress * 100)}%`)

// Pause all downloads
await DownloadManager.pauseAllDownloads()

// Resume all downloads
await DownloadManager.resumeAllDownloads()

// Cancel all downloads
await DownloadManager.cancelAllDownloads()
```

## Best Practices

1. **Configure on App Start**: Configure the download manager when your app initializes.

2. **Handle Errors**: Always listen to `onDownloadStateChange` to handle download errors gracefully.

3. **WiFi-Only for Large Downloads**: Enable `wifiOnlyDownloads` for better user experience.

4. **Monitor Storage**: Regularly check `getStorageInfo()` to avoid running out of space.

5. **Sync Downloads**: Call `syncDownloads()` periodically to clean up orphaned records.

6. **Use Auto Playback Source**: Set playback source to `'auto'` to seamlessly use downloaded tracks when available.

7. **Background Downloads**: Enable `backgroundDownloadsEnabled` for better user experience on Android.
