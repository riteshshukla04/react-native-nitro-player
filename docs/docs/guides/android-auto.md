---
sidebar_position: 2
sidebar_label: '🚗 Android Auto'
tags: [android]
---

# Android Auto

<span className="badge badge--success">Android</span>

React Native Nitro Player provides native support for Android Auto, allowing you to control playback and browse media directly from your car's head unit.

## Setup

### 1. Enable Android Auto

Enable the feature when configuring the player:

```typescript
import { TrackPlayer } from 'react-native-nitro-player'

TrackPlayer.configure({
  androidAutoEnabled: true,
  // ... other config
})
```

### 2. Native Configuration

You must configure your Android app to declare support for Android Auto.

#### **AndroidManifest.xml**

Add the following to your `android/app/src/main/AndroidManifest.xml`:

1. **Declare Android Auto support:**

```xml
<manifest ...>
    <!-- ... permissions ... -->

    <!-- Declare Android Auto support -->
    <uses-feature
        android:name="android.hardware.type.automotive"
        android:required="false" />

    <application ...>
        <!-- ... -->

        <!-- Android Auto metadata -->
        <meta-data
            android:name="com.google.android.gms.car.application"
            android:resource="@xml/automotive_app_desc" />

        <!-- MediaBrowserService for Android Auto -->
        <service
            android:name="com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>

    </application>
</manifest>
```

#### **automotive_app_desc.xml**

Create a file at `android/app/src/main/res/xml/automotive_app_desc.xml` with the following content:

```xml
<?xml version="1.0" encoding="utf-8"?>
<automotiveApp>
    <uses name="media" />
</automotiveApp>
```

### 3. Connection Status

You can monitor the connection status to update your UI or logic when the phone connects to a car.

```typescript
import { useAndroidAutoConnection } from 'react-native-nitro-player'

function CarConnectionStatus() {
  const { isConnected } = useAndroidAutoConnection()

  return (
    <Text>{isConnected ? 'Connected to Android Auto 🚗' : 'Disconnected'}</Text>
  )
}
```

## Customizing the Media Library

By default, Android Auto will simply list all your playlists. However, `react-native-nitro-player` allows you to define a custom, hierarchical folder structure using `AndroidAutoMediaLibrary`.

This is useful for organizing content into categories like **"Favorites"**, **"By Genre"**, or **"Recently Played"**.

### Basic Usage

Use `AndroidAutoMediaLibrary.setMediaLibrary()` to define your structure.

```typescript
import { 
  AndroidAutoMediaLibrary, 
  PlayerQueue 
} from 'react-native-nitro-player'
import type { MediaLibrary } from 'react-native-nitro-player'

// Define your library structure
const mediaLibrary: MediaLibrary = {
  layoutType: 'grid', // Default layout: 'grid' or 'list'
  rootItems: [
    {
      id: 'my_music',
      title: '🎵 My Music',
      subtitle: 'Your collection',
      mediaType: 'folder',
      isPlayable: false,
      children: [
        {
          id: 'favorites',
          title: 'Favorites',
          mediaType: 'playlist',
          playlistId: 'playlist-id-1', // Must match an ID from PlayerQueue
          isPlayable: false, // Set to false to open the playlist folder
        },
      ],
    },
    {
      id: 'recent',
      title: '🕐 Recently Played',
      mediaType: 'folder',
      isPlayable: false,
      children: [
        // ... more items
      ],
    },
  ],
}

// Apply the structure
AndroidAutoMediaLibrary.setMediaLibrary(JSON.stringify(mediaLibrary))
```

> [!TIP]
> Changes to the media library are applied immediately, even if connected to Android Auto.

### Example: Organizing by Genre

Here is a more complex example of organizing playlists by genre.

```typescript
import {
  PlayerQueue,
  AndroidAutoMediaLibrary,
} from 'react-native-nitro-player'

// 1. Create your playlists
const rockId = PlayerQueue.createPlaylist('Rock Classics')
const jazzId = PlayerQueue.createPlaylist('Jazz Essentials')
const popId = PlayerQueue.createPlaylist('Pop Hits')

// ... add tracks to playlists ...

// 2. Define the Android Auto structure
AndroidAutoMediaLibrary.setMediaLibrary(JSON.stringify({
  layoutType: 'list',
  rootItems: [
    {
      id: 'genres',
      title: '🎸 By Genre',
      mediaType: 'folder',
      isPlayable: false,
      layoutType: 'grid', // Use grid for this folder
      children: [
        {
          id: 'rock',
          title: 'Rock',
          mediaType: 'playlist',
          playlistId: rockId,
          isPlayable: false,
        },
        {
          id: 'jazz',
          title: 'Jazz',
          mediaType: 'playlist',
          playlistId: jazzId,
          isPlayable: false,
        },
        {
          id: 'pop',
          title: 'Pop',
          mediaType: 'playlist',
          playlistId: popId,
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
        // You can reuse playlists in multiple locations
        {
          id: 'all_rock',
          title: 'Rock Classics',
          mediaType: 'playlist',
          playlistId: rockId,
          isPlayable: false,
        },
        // ...
      ],
    },
  ],
}))
```

### Resetting to Default

To revert to the default behavior (showing a flat list of all playlists), use `clearMediaLibrary()`:

```typescript
AndroidAutoMediaLibrary.clearMediaLibrary()
```

## API Reference

### `MediaLibrary` Structure

| Property | Type | Description |
| :--- | :--- | :--- |
| `layoutType` | `'grid' \| 'list'` | Default layout for child items. |
| `rootItems` | `MediaItem[]` | Array of top-level items. |
| `appName` | `string` | Optional app name to display. |
| `appIconUrl` | `string` | Optional URL for app icon. |

### `MediaItem` Structure

| Property | Type | Description |
| :--- | :--- | :--- |
| `id` | `string` | Unique identifier for the item. |
| `title` | `string` | Display title. |
| `subtitle` | `string` | Optional subtitle (secondary text). |
| `iconUrl` | `string` | Optional URL for item artwork/icon. |
| `isPlayable` | `boolean` | If `true`, clicking plays it. If `false`, clicking opens it. |
| `mediaType` | `'folder' \| 'audio' \| 'playlist'` | Type of item. |
| `playlistId` | `string` | **Required** for `playlist` type. helper to load tracks. |
| `children` | `MediaItem[]` | Child items (for folders). |
| `layoutType` | `'grid' \| 'list'` | Override parent's layout type for this folder. |

## Best Practices

- **Hierarchy**: Use folders (`mediaType: 'folder'`) to create a clean hierarchy. Avoid putting everything at the root.
- **Grids vs Lists**:
    - Use `grid` for categories, albums, or playlists (visual browsing).
    - Use `list` for song lists or long text-based details.
- **IDs**: Use stable, unique IDs for your media items.
- **Images**: Ensure `iconUrl` points to valid, accessible URLs (HTTPS is recommended).
