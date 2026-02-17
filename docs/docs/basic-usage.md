---
sidebar_position: 3
sidebar_label: '🚀 Basic Usage'
tags: [android, ios]
---

# Basic Usage

This guide will help you get started with **React Native Nitro Player** by creating a simple playlist and playing music.

## 1. Import Definitions

Import the necessary modules and types from the library.

```typescript
import { 
  TrackPlayer, 
  PlayerQueue, 
  type TrackItem 
} from 'react-native-nitro-player';
```

## 2. Define Sample Tracks

Here are some example tracks to get you started.

> [!NOTE]
> Ensure the URLs are accessible and valid media files.

### Sample Tracks Collection 1

```typescript
const sampleTracks1: TrackItem[] = [
  {
    id: '1',
    title: 'Sunset Drive',
    artist: 'Lofi Beats',
    album: 'Chill Vibes',
    duration: 182.0,
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    artwork: 'https://img.freepik.com/free-photo/sunset-time-tropical-beach-sea-with-coconut-palm-tree_74190-1075.jpg?w=740',
  },
  {
    id: '2',
    title: 'Midnight Rain',
    artist: 'Nightfall',
    album: 'Dreamscapes',
    duration: 204.0,
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    artwork: 'https://via.placeholder.com/150/FF0000/FFFFFF?Text=Midnight',
  },
  {
    id: '3',
    title: 'City Lights',
    artist: 'Synthwave Lab',
    album: 'Neon Streets',
    duration: 195.5,
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    artwork: 'https://via.placeholder.com/150/00FF00/000000?Text=City',
  },
];
```

### Sample Tracks Collection 2

```typescript
const sampleTracks2: TrackItem[] = [
  {
    id: '4',
    title: 'Ocean Waves',
    artist: 'Nature Sounds',
    album: 'Relaxation',
    duration: 300.0,
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
    artwork: 'https://via.placeholder.com/150/0000FF/FFFFFF?Text=Ocean',
  },
  {
    id: '5',
    title: 'Forest Walk',
    artist: 'Nature Sounds',
    album: 'Relaxation',
    duration: 280.0,
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
    artwork: 'https://via.placeholder.com/150/008000/FFFFFF?Text=Forest',
  },
];
```

## 3. Create and Play a Playlist

Now, let's create a playlist using `Sample Tracks Collection 1` and start playback.

```typescript
async function setupPlayer() {
  // 1. Create a new playlist
  const playlistId = PlayerQueue.createPlaylist(
    'Chill Vibes', 
    'Relaxing Lofi Beats', 
    sampleTracks1[0].artwork
  );

  // 2. Add tracks to the playlist
  PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

  // 3. Load the playlist into the player
  PlayerQueue.loadPlaylist(playlistId);

  // 4. Start playback
  // You can play the first song specifically, or just call play() if loaded
  await TrackPlayer.playSong(sampleTracks1[0].id);
}
```

## 4. Playing a Single Song

If you want to play a song from `Sample Tracks Collection 2` immediately:

```typescript
async function playNatureSound() {
  const track = sampleTracks2[0];
  
  // Directly play the song (it will be added to the queue automatically)
  // Note: For best practice, adding to a playlist is recommended.
  
  // Alternatively, create a quick playlist and play
  const naturePlaylistId = PlayerQueue.createPlaylist('Nature', 'Nature Sounds');
  PlayerQueue.addTracksToPlaylist(naturePlaylistId, sampleTracks2);
  PlayerQueue.loadPlaylist(naturePlaylistId);
  
  await TrackPlayer.playSong(track.id);
}
```

## 5. Controlling Playback

Once playback has started, you can control it using `TrackPlayer`.

```typescript
// Pause
TrackPlayer.pause();

// Resume
TrackPlayer.play();

// Skip to next track
TrackPlayer.skipToNext();

// Seek to 30 seconds
TrackPlayer.seek(30);
```
