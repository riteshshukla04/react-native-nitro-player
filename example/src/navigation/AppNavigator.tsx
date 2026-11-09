import React from 'react';
import { Text, StyleSheet } from 'react-native';
import { NavigationContainer, DarkTheme } from '@react-navigation/native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import PlayerScreen from '../screens/PlayerScreen';
import PlaylistsScreen from '../screens/PlaylistsScreen';
import UpNextScreen from '../screens/UpNextScreen';
import DownloadsScreen from '../screens/DownloadsScreen';
import MoreScreen from '../screens/MoreScreen';
import { colors } from '../styles/theme';

const navTheme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    primary: colors.primary,
    background: colors.background,
    card: colors.surface,
    text: colors.text,
    border: colors.border,
  },
};

const Tab = createBottomTabNavigator();

export default function AppNavigator() {
  return (
    <NavigationContainer theme={navTheme}>
      <Tab.Navigator
        screenOptions={{
          tabBarActiveTintColor: colors.primary,
          tabBarInactiveTintColor: colors.textTertiary,
          headerStyle: {
            backgroundColor: colors.surface,
          },
          headerTitleStyle: {
            fontWeight: '700',
            color: colors.text,
          },
          headerShadowVisible: false,
          tabBarStyle: {
            backgroundColor: colors.surface,
            borderTopWidth: StyleSheet.hairlineWidth,
            borderTopColor: colors.border,
          },
        }}>
        <Tab.Screen
          name="Player"
          component={PlayerScreen}
          options={{
            tabBarLabel: 'Player',
            tabBarIcon: () => <Text>▶️</Text>,
          }}
        />
        <Tab.Screen
          name="Playlists"
          component={PlaylistsScreen}
          options={{
            tabBarLabel: 'Playlists',
            tabBarIcon: () => <Text>📝</Text>,
          }}
        />
        <Tab.Screen
          name="UpNext"
          component={UpNextScreen}
          options={{
            tabBarLabel: 'Up Next',
            tabBarIcon: () => <Text>⏭️</Text>,
          }}
        />
        <Tab.Screen
          name="Downloads"
          component={DownloadsScreen}
          options={{
            tabBarLabel: 'Downloads',
            tabBarIcon: () => <Text>⬇️</Text>,
          }}
        />
        <Tab.Screen
          name="Equalizer"
          component={require('../screens/EqualizerScreen').default}
          options={{
            tabBarLabel: 'EQ',
            tabBarIcon: () => <Text>🎚️</Text>,
          }}
        />
        <Tab.Screen
          name="More"
          component={MoreScreen}
          options={{
            tabBarLabel: 'More',
            tabBarIcon: () => <Text>⚙️</Text>,
          }}
        />
      </Tab.Navigator>
    </NavigationContainer>
  );
}
