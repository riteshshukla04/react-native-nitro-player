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
  useOnChangeTrack,
  useOnPlaybackStateChange,
  useOnPlaybackProgressChange,
  AudioRoutePicker,
  useNowPlaying,
} from 'react-native-nitro-player';
import type { RepeatMode } from 'react-native-nitro-player';
import { colors, commonStyles, spacing, borderRadius } from '../styles/theme';

export default function PlayerScreen() {
  const { track: currentTrack } = useOnChangeTrack();
  console.log('useNowPlaying', useNowPlaying());
  const { state: playbackState } = useOnPlaybackStateChange();
  const { position: playbackPosition, totalDuration } =
    useOnPlaybackProgressChange();
  const [repeatMode, setRepeatMode] = useState<RepeatMode>('off');

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  const cycleRepeatMode = () => {
    const modes: RepeatMode[] = ['off', 'Playlist', 'track'];
    const currentIndex = modes.indexOf(repeatMode);
    const nextMode = modes[(currentIndex + 1) % modes.length];
    setRepeatMode(nextMode);
    TrackPlayer.setRepeatMode(nextMode);
  };

  return (
    <SafeAreaView style={commonStyles.container}>
      <ScrollView style={commonStyles.scrollView}>
        {/* Now Playing */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>Now Playing</Text>
          {currentTrack ? (
            <View style={commonStyles.card}>
              <Text style={styles.trackTitle}>{currentTrack.title}</Text>
              <Text style={styles.trackArtist}>{currentTrack.artist}</Text>
              <Text style={styles.trackAlbum}>{currentTrack.album}</Text>
            </View>
          ) : (
            <Text style={commonStyles.infoText}>No track playing</Text>
          )}
        </View>

        {/* Progress */}
        <View style={commonStyles.section}>
          <View style={styles.progressContainer}>
            <Text style={styles.timeText}>{formatTime(playbackPosition)}</Text>
            <View style={styles.progressBar}>
              <View
                style={[
                  styles.progressFill,
                  {
                    width: `${totalDuration > 0 ? (playbackPosition / totalDuration) * 100 : 0}%`,
                  },
                ]}
              />
            </View>
            <Text style={styles.timeText}>{formatTime(totalDuration)}</Text>
          </View>
        </View>

        {/* Playback Controls */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>Controls</Text>
          <View style={styles.controlsRow}>
            <TouchableOpacity
              style={styles.controlButton}
              onPress={() => TrackPlayer.skipToPrevious()}>
              <Text style={styles.controlButtonText}>⏮️</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.controlButton, styles.playButton]}
              onPress={() =>
                playbackState === 'playing'
                  ? TrackPlayer.pause()
                  : TrackPlayer.play()
              }>
              <Text style={styles.playButtonText}>
                {playbackState === 'playing' ? '⏸️' : '▶️'}
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.controlButton}
              onPress={() => TrackPlayer.skipToNext()}>
              <Text style={styles.controlButtonText}>⏭️</Text>
            </TouchableOpacity>
          </View>
          <View style={styles.secondaryControls}>
            <TouchableOpacity
              style={commonStyles.smallButton}
              onPress={cycleRepeatMode}>
              <Text style={commonStyles.buttonText}>🔁 {repeatMode}</Text>
            </TouchableOpacity>
            {Platform.OS === 'ios' && (
              <TouchableOpacity
                style={commonStyles.smallButton}
                onPress={() => {
                  try {
                    AudioRoutePicker?.showRoutePicker();
                  } catch {
                    console.log('AudioRoutePicker not available');
                  }
                }}>
                <Text style={commonStyles.buttonText}>🔊 Route</Text>
              </TouchableOpacity>
            )}
          </View>
        </View>

        {/* Seek Controls */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>Seek</Text>
          <View style={styles.seekRow}>
            <TouchableOpacity
              style={styles.seekButton}
              onPress={() => TrackPlayer.seek(30)}>
              <Text style={commonStyles.buttonText}>30s</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.seekButton}
              onPress={() => TrackPlayer.seek(60)}>
              <Text style={commonStyles.buttonText}>60s</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.seekButton}
              onPress={() =>
                totalDuration > 10 && TrackPlayer.seek(totalDuration - 10)
              }>
              <Text style={commonStyles.buttonText}>-10s</Text>
            </TouchableOpacity>
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  trackTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: colors.text,
    marginBottom: 4,
  },
  trackArtist: {
    fontSize: 16,
    color: colors.textSecondary,
    marginBottom: 4,
  },
  trackAlbum: {
    fontSize: 14,
    color: colors.textTertiary,
  },
  progressContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  progressBar: {
    flex: 1,
    height: 4,
    backgroundColor: colors.progressBackground,
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: colors.primary,
  },
  timeText: {
    fontSize: 12,
    color: colors.textSecondary,
    width: 40,
    textAlign: 'center',
  },
  controlsRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 20,
    marginBottom: spacing.lg,
  },
  controlButton: {
    width: 50,
    height: 50,
    borderRadius: borderRadius.xl,
    backgroundColor: colors.cardBackground,
    justifyContent: 'center',
    alignItems: 'center',
  },
  playButton: {
    width: 70,
    height: 70,
    borderRadius: borderRadius.xxl,
    backgroundColor: colors.primary,
  },
  controlButtonText: {
    fontSize: 24,
  },
  playButtonText: {
    fontSize: 32,
  },
  secondaryControls: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: spacing.md,
  },
  seekRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    gap: spacing.sm,
  },
  seekButton: {
    flex: 1,
    backgroundColor: colors.primary,
    padding: spacing.md,
    borderRadius: borderRadius.md,
    alignItems: 'center',
  },
});
