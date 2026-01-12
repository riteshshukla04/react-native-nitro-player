# Example App Structure

This directory contains the refactored and organized code for the React Native Nitro Player example app.

## Directory Structure

```
src/
├── components/                  # (Empty - for future shared components)
│
├── data/
│   └── sampleTracks.ts          # Sample track data for demos
│
├── navigation/
│   └── AppNavigator.tsx         # Tab navigation setup
│
├── screens/
│   ├── PlayerScreen.tsx         # Main player controls & now playing
│   ├── PlaylistsScreen.tsx      # Playlist management
│   ├── UpNextScreen.tsx         # Up Next & Play Next demo
│   └── MoreScreen.tsx           # Settings & volume control
│
└── styles/
    └── theme.ts                 # Shared colors, spacing, typography
```

## Features by Screen

### 🎵 PlayerScreen
- Now playing track display
- Playback controls (play, pause, skip)
- Progress bar with time display
- Repeat mode toggle
- Seek controls
- Audio route picker (iOS)

### 📝 PlaylistsScreen
- Create sample playlists
- View all playlists
- Load/delete playlists
- View tracks in current playlist
- Play individual tracks

### ⏭️ UpNextScreen
- Demonstrates `addToUpNext()` and `playNext()` functionality
- Shows currently playing track
- Lists available tracks from current playlist
- Quick action buttons for each track
- Example scenario walkthrough

### ⚙️ MoreScreen
- Volume control
- Audio devices (iOS)
- App information

## Theme System

The `theme.ts` file provides centralized:
- **Colors**: Primary, secondary, danger, success, backgrounds, text colors
- **Spacing**: xs, sm, md, lg, xl
- **Border Radius**: sm, md, lg, xl, xxl
- **Typography**: h1, h2, h3, body, bodySmall, caption, small, button
- **Common Styles**: Reusable style objects

## Usage

Import what you need:

```typescript
// Screens
import PlayerScreen from './src/screens/PlayerScreen';

// Data
import { sampleTracks1 } from './src/data/sampleTracks';

// Hooks (from package)
import { usePlaylist } from 'react-native-nitro-player';

// Styles
import { colors, commonStyles, spacing } from './src/styles/theme';
```

## Hooks from Package

### `usePlaylist`

This hook is now part of the `react-native-nitro-player` package!

**Import:**
```typescript
import { usePlaylist } from 'react-native-nitro-player';
```

**Used in:**
- PlaylistsScreen
- UpNextScreen

**Benefits:**
- Single source of truth for playlist data
- Auto-refreshes on changes
- Provides aggregated data (all tracks, all playlists)
- Type-safe with TypeScript
- Available to all users of the package

## Benefits of This Structure

1. **Separation of Concerns**: Each screen is self-contained
2. **Reusability**: Shared styles and data in dedicated folders
3. **Maintainability**: Easy to find and update specific features
4. **Scalability**: Simple to add new screens or components
5. **Type Safety**: TypeScript throughout with proper imports
