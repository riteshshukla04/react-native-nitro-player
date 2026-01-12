import React, { useEffect, useState } from 'react';
import {
  StyleSheet,
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  Platform,
  SafeAreaView,
} from 'react-native';
import { TrackPlayer, AudioDevices } from 'react-native-nitro-player';
import { colors, commonStyles, spacing, borderRadius } from '../styles/theme';

export default function MoreScreen() {
  const [volume, setVolume] = useState(50);
  const [audioDevices, setAudioDevices] = useState<any[]>([]);

  useEffect(() => {
    if (Platform.OS === 'ios') {
      try {
        const devices = AudioDevices?.getAudioDevices();
        if (devices) {
          setAudioDevices(devices);
        }
      } catch {
        console.log('AudioDevices not available');
      }
    }
  }, []);

  const handleVolumeChange = (newVolume: number) => {
    setVolume(newVolume);
    TrackPlayer.setVolume(newVolume);
  };

  return (
    <SafeAreaView style={commonStyles.container}>
      <ScrollView style={commonStyles.scrollView}>
        {/* Volume Control */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>Volume: {volume}%</Text>
          <View style={styles.volumeControls}>
            <TouchableOpacity
              style={commonStyles.button}
              onPress={() => handleVolumeChange(0)}>
              <Text style={commonStyles.buttonText}>0%</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={commonStyles.button}
              onPress={() => handleVolumeChange(50)}>
              <Text style={commonStyles.buttonText}>50%</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={commonStyles.button}
              onPress={() => handleVolumeChange(100)}>
              <Text style={commonStyles.buttonText}>100%</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Audio Devices (iOS) */}
        {Platform.OS === 'ios' && (
          <View style={commonStyles.section}>
            <Text style={commonStyles.sectionTitle}>Audio Devices</Text>
            {audioDevices.length > 0 ? (
              audioDevices.map((device: any, index: number) => (
                <View key={index} style={styles.deviceCard}>
                  <Text style={styles.deviceName}>{device.name || 'Unknown'}</Text>
                  <Text style={styles.deviceType}>{device.type || 'Unknown'}</Text>
                </View>
              ))
            ) : (
              <Text style={commonStyles.infoText}>No audio devices detected</Text>
            )}
          </View>
        )}

        {/* App Info */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>About</Text>
          <Text style={commonStyles.infoText}>
            React Native Nitro Player Example App
          </Text>
          <Text style={commonStyles.infoText}>Platform: {Platform.OS}</Text>
          <Text style={commonStyles.infoText}>
            Features: Playlists, Up Next, Play Next
          </Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  volumeControls: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  deviceCard: {
    backgroundColor: colors.cardBackground,
    padding: spacing.md,
    borderRadius: borderRadius.md,
    marginBottom: spacing.sm,
  },
  deviceName: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.text,
  },
  deviceType: {
    fontSize: 13,
    color: colors.textSecondary,
  },
});
