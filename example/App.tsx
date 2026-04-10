/**
 * Sample React Native App with Tabs
 * Refactored and organized structure
 *
 * @format
 */

import React, { useEffect } from 'react';
import { Platform, PermissionsAndroid, StatusBar } from 'react-native';
import { TrackPlayer, CarPlayMediaLibraryHelper } from 'react-native-nitro-player';
import AppNavigator from './src/navigation/AppNavigator';

void TrackPlayer.configure({
  androidAutoEnabled: true,
  carPlayEnabled: true,
  showInNotification: true,
  lookaheadCount: 3,
});

// Set up CarPlay media library (iOS only)
if (Platform.OS === 'ios') {
  CarPlayMediaLibraryHelper.set({
    layoutType: 'list',
    rootItems: [
      {
        id: 'chill_vibes',
        title: 'Chill Vibes',
        subtitle: 'Lofi & relaxation tracks',
        mediaType: 'playlist',
        playlistId: '', // Will be populated after playlist creation
        isPlayable: false,
        iconUrl: 'https://img.freepik.com/free-photo/sunset-time-tropical-beach-sea-with-coconut-palm-tree_74190-1075.jpg?w=740',
      },
      {
        id: 'hip_hop',
        title: 'Hip Hop',
        subtitle: 'Rap & hip hop tracks',
        mediaType: 'playlist',
        playlistId: '', // Will be populated after playlist creation
        isPlayable: false,
        iconUrl: 'https://i.ytimg.com/vi/AMUcevp0sME/hq720.jpg',
      },
    ],
  });
}

TrackPlayer.onTracksNeedUpdate(async (tracks, lookahead) => {
  console.info(`🔄 onTracksNeedUpdate fired! ${tracks.length} tracks need URLs (lookahead: ${lookahead})`);
  console.info('Tracks:', tracks.map((t) => ({ id: t.id, title: t.title })));
  
  // Update tracks with resolved URLs
  const updatedTracks = tracks.map((track) => ({
    ...track,
    url: `https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3`,
  }));
  
  await TrackPlayer.updateTracks(updatedTracks);
})

export default function App() {
  useEffect(() => {
    if (Platform.OS === 'android' && Platform.Version >= 33) {
      PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS);
    }
  }, []);

  return (
    <>
      <StatusBar barStyle="dark-content" />
      <AppNavigator />
    </>
  );
}
