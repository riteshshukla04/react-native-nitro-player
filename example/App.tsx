/**
 * Sample React Native App with Tabs
 * Refactored and organized structure
 *
 * @format
 */

import React from 'react';
import { StatusBar } from 'react-native';
import { TrackPlayer } from 'react-native-nitro-player';
import AppNavigator from './src/navigation/AppNavigator';

// Configure TrackPlayer
TrackPlayer.configure({
  androidAutoEnabled: true,
  carPlayEnabled: false,
  showInNotification: true,
  lookaheadCount: 3,
});

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

export default  function App() {
  return (
    <>
      <StatusBar barStyle="dark-content" />
      <AppNavigator />
    </>
  );
}
