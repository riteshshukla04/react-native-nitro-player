import React, { useEffect, useState } from 'react';
import {
  StyleSheet,
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  Platform,
  SafeAreaView,
  Image,
  StatusBar,
} from 'react-native';
import {
  TrackPlayer,
  PlayerQueue,
  useOnChangeTrack,
  useOnPlaybackStateChange,
  useOnPlaybackProgressChange,
  AudioRoutePicker,
  useNowPlaying,
  useTimedMetadata,
} from 'react-native-nitro-player';
import type { RepeatMode } from 'react-native-nitro-player';
import { colors, spacing, borderRadius } from '../styles/theme';
import { radioStreams, sampleTracks1 } from '../data/sampleTracks';

export default function PlayerScreen() {
  const { track: currentTrack } = useOnChangeTrack();
  useNowPlaying();
  const { state: playbackState } = useOnPlaybackStateChange();
  const { position: playbackPosition, totalDuration } =
    useOnPlaybackProgressChange();
  const streamMetadata = useTimedMetadata();
  const streamArtwork = streamMetadata?.artworkUrl ?? streamMetadata?.url;
  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };
  const [playbackSpeed, setPlaybackSpeed] = useState<number>(1);
  const fetchPlaybackSpeed = async () => {
    const current = await TrackPlayer.getPlaybackSpeed();
    console.log('current', current);
    setPlaybackSpeed(current);
  };

  useEffect(() => {
    fetchPlaybackSpeed();
  }, []);

  const setPlaybackSpeedState = (speed: number) => {
    void TrackPlayer.setPlaybackSpeed(speed).then(() => fetchPlaybackSpeed());
  };
  const [quickLoading, setQuickLoading] = useState(false);
  const quickTest = async () => {
    try {
      setQuickLoading(true);
      const playlistId = await PlayerQueue.createPlaylist('Test Playlist', 'Quick test');
      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
      await PlayerQueue.loadPlaylist(playlistId);
      await TrackPlayer.play();
    } catch (e) {
      console.error('Quick test failed:', e);
    } finally {
      setQuickLoading(false);
    }
  };

  const [radioLoading, setRadioLoading] = useState(false);
  const playRadio = async () => {
    try {
      setRadioLoading(true);
      const playlistId = await PlayerQueue.createPlaylist('Live Radio', 'ICY metadata test');
      await PlayerQueue.addTracksToPlaylist(playlistId, radioStreams);
      await PlayerQueue.loadPlaylist(playlistId);
      await TrackPlayer.play();
    } catch (e) {
      console.error('Radio test failed:', e);
    } finally {
      setRadioLoading(false);
    }
  };

  const [repeatMode, setRepeatModeState] = useState<RepeatMode>('off');

  const REPEAT_MODES: RepeatMode[] = ['off', 'track', 'Playlist'];
  const REPEAT_LABELS: Record<RepeatMode, string> = {
    off: '🚫 Off',
    track: '🔂 Track',
    Playlist: '🔁 Playlist',
  };

  const cycleRepeatMode = () => {
    const nextIndex = (REPEAT_MODES.indexOf(repeatMode) + 1) % REPEAT_MODES.length;
    const next = REPEAT_MODES[nextIndex];
    void TrackPlayer.setRepeatMode(next).then(() => setRepeatModeState(next));
  };

  const shuffleCurrentPlaylist = () => {
    const playlistId = PlayerQueue.getCurrentPlaylistId();
    if (!playlistId) {
      console.log('❌ No active playlist to shuffle');
      return;
    }
    // The song keeps playing — only the upcoming order changes.
    void PlayerQueue.shufflePlaylist(playlistId);
  };

  const fetchRepeatMode = async () => {
    const current = TrackPlayer.getRepeatMode();
    setRepeatModeState(current);
  };

  const isPlaying = playbackState === 'playing';
  const progress =
    totalDuration > 0 ? Math.min(1, playbackPosition / totalDuration) : 0;
  const artwork = streamArtwork ?? currentTrack?.artwork;
  const title = streamMetadata?.title ?? currentTrack?.title;
  const artist = streamMetadata?.artist ?? currentTrack?.artist;
  const album = streamMetadata?.album ?? currentTrack?.album;

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}>
        {/* Artwork hero */}
        <View style={styles.artworkShadow}>
          {artwork ? (
            <Image source={{ uri: artwork }} style={styles.artwork} />
          ) : (
            <View style={[styles.artwork, styles.artworkPlaceholder]}>
              <Text style={styles.artworkGlyph}>♪</Text>
            </View>
          )}
        </View>

        {/* Now Playing */}
        <View style={styles.meta}>
          <Text style={styles.eyebrow}>NOW PLAYING</Text>
          <Text style={styles.trackTitle} numberOfLines={1}>
            {title ?? 'Nothing playing'}
          </Text>
          <Text style={styles.trackArtist} numberOfLines={1}>
            {artist ?? 'Load a playlist to get started'}
          </Text>
          {!!album && (
            <Text style={styles.trackAlbum} numberOfLines={1}>
              {album}
            </Text>
          )}
        </View>

        {/* Progress */}
        <View style={styles.progressContainer}>
          <View style={styles.progressBar}>
            <View
              style={[styles.progressFill, { width: `${progress * 100}%` }]}
            />
            <View
              style={[styles.progressKnob, { left: `${progress * 100}%` }]}
            />
          </View>
          <View style={styles.timeRow}>
            <Text style={styles.timeText}>{formatTime(playbackPosition)}</Text>
            <Text style={styles.timeText}>{formatTime(totalDuration)}</Text>
          </View>
        </View>

        {/* Transport controls */}
        <View style={styles.controlsRow}>
          <TouchableOpacity
            style={styles.sideButton}
            onPress={shuffleCurrentPlaylist}>
            <Text style={styles.sideButtonText}>🔀 Shuffle</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.controlButton}
            onPress={() => void TrackPlayer.skipToPrevious()}>
            <Text style={styles.controlButtonText}>⏮</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.playButton}
            onPress={() =>
              isPlaying ? void TrackPlayer.pause() : void TrackPlayer.play()
            }>
            {isPlaying ? (
              <View style={styles.pauseIcon}>
                <View style={styles.pauseBar} />
                <View style={styles.pauseBar} />
              </View>
            ) : (
              <View style={styles.playIcon} />
            )}
          </TouchableOpacity>
          <TouchableOpacity
            style={styles.controlButton}
            onPress={() => void TrackPlayer.skipToNext()}>
            <Text style={styles.controlButtonText}>⏭</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.sideButton, repeatMode !== 'off' && styles.chipActive]}
            onPress={cycleRepeatMode}>
            <Text
              style={[
                styles.sideButtonText,
                repeatMode !== 'off' && styles.chipTextActive,
              ]}>
              {REPEAT_LABELS[repeatMode]}
            </Text>
          </TouchableOpacity>
        </View>
        {Platform.OS === 'ios' && (
          <TouchableOpacity
            style={styles.routeButton}
            onPress={() => {
              try {
                AudioRoutePicker?.showRoutePicker();
              } catch {
                console.log('AudioRoutePicker not available');
              }
            }}>
            <Text style={styles.sideButtonText}>🔊 Route</Text>
          </TouchableOpacity>
        )}

        {/* Sources */}
        <Text style={styles.sectionLabel}>Play something</Text>
        <View style={styles.sourceRow}>
          <TouchableOpacity
            style={[styles.sourceCard, quickLoading && styles.disabled]}
            onPress={quickTest}
            disabled={quickLoading}>
            <Text style={styles.sourceEmoji}>🚀</Text>
            <Text style={styles.sourceTitle}>
              {quickLoading ? 'Loading...' : 'Quick Test — Load & Play'}
            </Text>
            <Text style={styles.sourceSub}>3 sample tracks</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.sourceCard, radioLoading && styles.disabled]}
            onPress={playRadio}
            disabled={radioLoading}>
            <Text style={styles.sourceEmoji}>📻</Text>
            <Text style={styles.sourceTitle}>
              {radioLoading ? 'Loading...' : 'Play Live Radio (ICY metadata)'}
            </Text>
            <Text style={styles.sourceSub}>Live stream metadata</Text>
          </TouchableOpacity>
        </View>

        {/* Seek */}
        <Text style={styles.sectionLabel}>Seek</Text>
        <View style={styles.chipRow}>
          {[
            { label: '30s', onPress: () => void TrackPlayer.seek(30) },
            { label: '60s', onPress: () => void TrackPlayer.seek(60) },
            {
              label: '-10s',
              onPress: () =>
                totalDuration > 10 && void TrackPlayer.seek(totalDuration - 10),
            },
          ].map(item => (
            <TouchableOpacity
              key={item.label}
              style={styles.chip}
              onPress={item.onPress}>
              <Text style={styles.chipText}>{item.label}</Text>
            </TouchableOpacity>
          ))}
        </View>

        {/* Speed */}
        <Text style={styles.sectionLabel}>Speed · {playbackSpeed}x</Text>
        <View style={styles.chipRow}>
          {[0.5, 1, 1.5, 2].map(speed => (
            <TouchableOpacity
              key={speed}
              style={[styles.chip, playbackSpeed === speed && styles.chipActive]}
              onPress={() => setPlaybackSpeedState(speed)}>
              <Text
                style={[
                  styles.chipText,
                  playbackSpeed === speed && styles.chipTextActive,
                ]}>
                {speed}x
              </Text>
            </TouchableOpacity>
          ))}
        </View>

        {/* Repeat */}
        <Text style={styles.sectionLabel}>Repeat Mode</Text>
        <View style={styles.chipRow}>
          {REPEAT_MODES.map(mode => (
            <TouchableOpacity
              key={mode}
              style={[styles.chip, repeatMode === mode && styles.chipActive]}
              onPress={() => {
                void TrackPlayer.setRepeatMode(mode).then(() =>
                  setRepeatModeState(mode),
                );
              }}>
              <Text
                style={[
                  styles.chipText,
                  repeatMode === mode && styles.chipTextActive,
                ]}>
                {REPEAT_LABELS[mode]}
              </Text>
            </TouchableOpacity>
          ))}
          <TouchableOpacity style={styles.chip} onPress={fetchRepeatMode}>
            <Text style={styles.chipText}>🔍 Get</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.xl, paddingBottom: 40 },
  artworkShadow: {
    alignSelf: 'center',
    width: '58%',
    aspectRatio: 1,
    borderRadius: 28,
    backgroundColor: colors.cardBackground,
    elevation: 16,
    shadowColor: colors.primary,
    shadowOpacity: 0.35,
    shadowRadius: 24,
    shadowOffset: { width: 0, height: 12 },
    marginTop: spacing.md,
  },
  artwork: { width: '100%', height: '100%', borderRadius: 28 },
  artworkPlaceholder: {
    backgroundColor: '#23233A',
    alignItems: 'center',
    justifyContent: 'center',
  },
  artworkGlyph: { fontSize: 96, color: colors.primary },
  meta: { marginTop: 22, alignItems: 'center' },
  eyebrow: {
    fontSize: 11,
    letterSpacing: 2,
    fontWeight: '700',
    color: colors.primary,
    marginBottom: 6,
  },
  trackTitle: { fontSize: 24, fontWeight: '800', color: colors.text },
  trackArtist: { fontSize: 16, color: colors.textSecondary, marginTop: 4 },
  trackAlbum: { fontSize: 13, color: colors.textTertiary, marginTop: 2 },
  progressContainer: { marginTop: 20 },
  progressBar: {
    height: 6,
    backgroundColor: colors.progressBackground,
    borderRadius: 3,
    justifyContent: 'center',
  },
  progressFill: {
    height: 6,
    backgroundColor: colors.primary,
    borderRadius: 3,
  },
  progressKnob: {
    position: 'absolute',
    width: 14,
    height: 14,
    marginLeft: -7,
    borderRadius: 7,
    backgroundColor: colors.text,
  },
  timeRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 8,
  },
  timeText: { fontSize: 12, color: colors.textSecondary },
  controlsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 24,
  },
  controlButton: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: colors.cardBackground,
    alignItems: 'center',
    justifyContent: 'center',
  },
  controlButtonText: { fontSize: 20, color: colors.text },
  playButton: {
    width: 76,
    height: 76,
    borderRadius: 38,
    backgroundColor: colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
    elevation: 8,
    shadowColor: colors.primary,
    shadowOpacity: 0.5,
    shadowRadius: 14,
  },
  playIcon: {
    marginLeft: 6,
    width: 0,
    height: 0,
    borderTopWidth: 14,
    borderBottomWidth: 14,
    borderLeftWidth: 24,
    borderTopColor: 'transparent',
    borderBottomColor: 'transparent',
    borderLeftColor: colors.onPrimary,
  },
  pauseIcon: { flexDirection: 'row', gap: 6 },
  pauseBar: {
    width: 8,
    height: 28,
    borderRadius: 2,
    backgroundColor: colors.onPrimary,
  },
  sideButton: {
    paddingHorizontal: 10,
    paddingVertical: 8,
    borderRadius: 16,
    backgroundColor: colors.cardBackground,
  },
  sideButtonText: { fontSize: 11, color: colors.textSecondary, fontWeight: '600' },
  routeButton: { alignSelf: 'center', marginTop: spacing.md, padding: 8 },
  sectionLabel: {
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 0.5,
    color: colors.textSecondary,
    textTransform: 'uppercase',
    marginTop: 30,
    marginBottom: 12,
  },
  sourceRow: { flexDirection: 'row', gap: spacing.md },
  sourceCard: {
    flex: 1,
    backgroundColor: colors.cardBackground,
    borderRadius: borderRadius.card,
    padding: spacing.lg,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
  },
  sourceEmoji: { fontSize: 26, marginBottom: 10 },
  sourceTitle: { fontSize: 14, fontWeight: '700', color: colors.text },
  sourceSub: { fontSize: 12, color: colors.textTertiary, marginTop: 4 },
  disabled: { opacity: 0.5 },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  chip: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 20,
    backgroundColor: colors.cardBackground,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
  },
  chipActive: { backgroundColor: colors.primary, borderColor: colors.primary },
  chipText: { fontSize: 13, fontWeight: '600', color: colors.textSecondary },
  chipTextActive: { color: colors.onPrimary },
});
