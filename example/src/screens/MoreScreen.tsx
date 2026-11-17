import React, { useState } from 'react';
import {
  StyleSheet,
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  Platform,
  SafeAreaView,
} from 'react-native';
import {
  TrackPlayer,
  CastButton,
  useAudioOutputs,
  useCastState,
} from 'react-native-nitro-player';
import { colors, commonStyles, spacing, borderRadius } from '../styles/theme';

const NOTIFICATION_ICONS = [
  { label: '🎵 Music Note', value: 'ic_notification' },
  { label: '🎧 Headphones', value: 'ic_notification_alt' },
];

export default function MoreScreen() {
  const [volume, setVolume] = useState(50);
  const { outputs } = useAudioOutputs();
  const [notificationIcon, setNotificationIcon] = useState('ic_notification');
  const { state: castState, deviceName, isCasting } = useCastState();

  const castStatusText =
    castState === 'connected'
      ? `Connected to ${deviceName ?? 'device'}`
      : castState === 'connecting'
        ? 'Connecting…'
        : castState === 'no_devices_available'
          ? 'No Cast devices found'
          : 'Tap to cast';

  const handleVolumeChange = (newVolume: number) => {
    setVolume(newVolume);
    void TrackPlayer.setVolume(newVolume);
  };

  const handleNotificationIconChange = (icon: string) => {
    setNotificationIcon(icon);
    void TrackPlayer.configure({ androidNotificationIcon: icon });
  };

  return (
    <SafeAreaView style={commonStyles.container}>
      <ScrollView style={commonStyles.scrollView}>
        {/* Google Cast */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>Google Cast</Text>
          <View style={styles.castRow}>
            <CastButton
              size={30}
              color={colors.text}
              activeColor={colors.primary}
              hideWhenNoDevices={false}
            />
            <Text
              style={[styles.castStatus, isCasting && styles.castStatusActive]}>
              {castStatusText}
            </Text>
          </View>
        </View>

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

        {/* Notification Icon (Android) */}
        {Platform.OS === 'android' && (
          <View style={commonStyles.section}>
            <Text style={commonStyles.sectionTitle}>Notification Icon</Text>
            <Text style={commonStyles.infoText}>
              Switch the media notification small icon, then check the
              notification shade / lock screen.
            </Text>
            <View style={styles.iconButtons}>
              {NOTIFICATION_ICONS.map((icon) => {
                const active = notificationIcon === icon.value;
                return (
                  <TouchableOpacity
                    key={icon.value}
                    style={[
                      commonStyles.button,
                      styles.iconButton,
                      active && styles.iconButtonActive,
                    ]}
                    onPress={() => handleNotificationIconChange(icon.value)}>
                    <Text style={commonStyles.buttonText}>
                      {active ? '✓ ' : ''}
                      {icon.label}
                    </Text>
                  </TouchableOpacity>
                );
              })}
            </View>
          </View>
        )}

        {/* Audio Output: updates when headphones connect or disconnect */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>Audio Output</Text>
          {outputs.length > 0 ? (
            outputs.map(output => (
              <View key={output.id} style={styles.deviceCard}>
                <Text style={styles.deviceName}>{output.name}</Text>
                <Text style={styles.deviceType}>
                  {output.type} · {output.id}
                </Text>
              </View>
            ))
          ) : (
            <Text style={commonStyles.infoText}>No audio output detected</Text>
          )}
        </View>

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
  castRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
  },
  castStatus: {
    fontSize: 15,
    color: colors.textSecondary,
  },
  castStatusActive: {
    color: colors.primary,
    fontWeight: '600',
  },
  volumeControls: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  iconButtons: {
    flexDirection: 'row',
    gap: spacing.sm,
    marginTop: spacing.sm,
  },
  iconButton: {
    flex: 1,
  },
  iconButtonActive: {
    backgroundColor: colors.success,
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
