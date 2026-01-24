import React from 'react';
import { Text } from 'react-native';
import { NavigationContainer } from '@react-navigation/native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import PlayerScreen from '../screens/PlayerScreen';
import PlaylistsScreen from '../screens/PlaylistsScreen';
import UpNextScreen from '../screens/UpNextScreen';
import DownloadsScreen from '../screens/DownloadsScreen';
import MoreScreen from '../screens/MoreScreen';
import { colors } from '../styles/theme';

const Tab = createBottomTabNavigator();

export default function AppNavigator() {
  return (
    <NavigationContainer>
      <Tab.Navigator
        screenOptions={{
          tabBarActiveTintColor: colors.primary,
          tabBarInactiveTintColor: '#8E8E93',
          headerStyle: {
            backgroundColor: '#f8f9fa',
          },
          headerTitleStyle: {
            fontWeight: '600',
          },
          tabBarStyle: {
            backgroundColor: colors.white,
            borderTopWidth: 1,
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
