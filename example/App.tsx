/**
 * Sample React Native App with Tabs
 * Refactored and organized structure
 *
 * @format
 */

import React, { useEffect } from 'react';
import { Platform, PermissionsAndroid, StatusBar } from 'react-native';
import { TrackPlayer } from 'react-native-nitro-player';
import AppNavigator from './src/navigation/AppNavigator';
import BenchScreen from './src/screens/BenchScreen';
import { registerAndroidAuto } from './src/androidAuto';

const RUN_BENCH = false;

void TrackPlayer.configure({
  androidAutoEnabled: true,
  carPlayEnabled: false,
  showInNotification: true,
  remoteSkipForwardInterval: 15,
  remoteSkipBackwardInterval: 15,
  lookaheadCount: 3,
  androidNotificationIcon: 'ic_notification', // Android Only
});

// Module scope, not a component: Android Auto can start the app without any UI
registerAndroidAuto().catch((e) => console.error('Android Auto demo failed', e));

TrackPlayer.appStartedWithNotification((track) => {
  console.info(`🔔 appStartedWithNotification fired! track: ${track.id} - ${track.title}`);
});

TrackPlayer.onTracksNeedUpdate(async (tracks, lookahead) => {
  console.info(`🔄 onTracksNeedUpdate fired! ${tracks.length} tracks need URLs (lookahead: ${lookahead})`);
  console.info('Tracks:', tracks.map((t) => ({ id: t.id, title: t.title })));
  
  // Numbered ids get distinct songs
  const updatedTracks = tracks.map((track) => ({
    ...track,
    url: `https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${(Number(track.id.split('-').pop()) % 16 || 0) + 1}.mp3`,
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
      {RUN_BENCH ? <BenchScreen /> : <AppNavigator />}
    </>
  );
}
