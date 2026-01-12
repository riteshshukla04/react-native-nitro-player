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
});

export default function App() {
  return (
    <>
      <StatusBar barStyle="dark-content" />
      <AppNavigator />
    </>
  );
}
