import React, { useCallback } from 'react';
import {
  StyleSheet,
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  SafeAreaView,
  RefreshControl,
} from 'react-native';
import {
  TrackPlayer,
  useOnChangeTrack,
  usePlaylist,
  useActualQueue,
} from 'react-native-nitro-player';
import type { TrackItem } from 'react-native-nitro-player';
import { colors, commonStyles, spacing, borderRadius } from '../styles/theme';

export default function UpNextScreen() {
  const { allTracks: availableTracks, refreshPlaylists, isLoading: playlistLoading } = usePlaylist();
  const { track: currentTrack } = useOnChangeTrack();
  const { queue: actualQueue, refreshQueue, isLoading: queueLoading } = useActualQueue();

  const handleAddToUpNext = useCallback((trackId: string) => {
    TrackPlayer.addToUpNext(trackId);
    console.log('Added to Up Next:', trackId);
    // Refresh queue after a short delay to allow native side to update
    setTimeout(refreshQueue, 100);
  }, [refreshQueue]);

  const handlePlayNext = useCallback((trackId: string) => {
    TrackPlayer.playNext(trackId);
    console.log('Added to Play Next:', trackId);
    // Refresh queue after a short delay to allow native side to update
    setTimeout(refreshQueue, 100);
  }, [refreshQueue]);

  const handleRefresh = useCallback(() => {
    refreshPlaylists();
    refreshQueue();
  }, [refreshPlaylists, refreshQueue]);

  return (
    <SafeAreaView style={commonStyles.container}>
      <ScrollView
        style={commonStyles.scrollView}
        refreshControl={
          <RefreshControl
            refreshing={playlistLoading || queueLoading}
            onRefresh={handleRefresh}
            tintColor={colors.primary}
          />
        }>
        {/* Explanation */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>🎵 Up Next & Play Next</Text>
          <View style={styles.infoBox}>
            <Text style={commonStyles.infoText}>
              • <Text style={styles.bold}>Add to Up Next (FIFO):</Text> Songs play
              in the order they were added
            </Text>
            <Text style={commonStyles.infoText}>
              • <Text style={styles.bold}>Play Next (LIFO):</Text> Last added song
              plays first
            </Text>
            <Text style={commonStyles.infoText}>
              • Temporary tracks are auto-removed after playing
            </Text>
          </View>
        </View>

        {/* Currently Playing */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>Currently Playing</Text>
          {currentTrack ? (
            <View style={commonStyles.card}>
              <Text style={styles.trackTitle}>{currentTrack.title}</Text>
              <Text style={styles.trackArtist}>{currentTrack.artist}</Text>
            </View>
          ) : (
            <Text style={commonStyles.infoText}>No track playing</Text>
          )}
        </View>

        {/* Available Tracks */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>
            Available Tracks ({availableTracks.length})
          </Text>
          {availableTracks.length > 0 ? (
            <>
              <Text style={styles.sectionSubtitle}>
                From all playlists - add to your queue
              </Text>
              {availableTracks.map((track) => (
                <View key={track.id} style={styles.trackCard}>
                  <View style={styles.trackInfo}>
                    <Text style={styles.trackCardTitle}>{track.title}</Text>
                    <Text style={styles.trackCardArtist}>
                      {track.artist} • {track.album}
                    </Text>
                  </View>
                  <View style={styles.trackActions}>
                    <TouchableOpacity
                      style={[commonStyles.smallButton, styles.primaryButton]}
                      onPress={() => handleAddToUpNext(track.id)}>
                      <Text style={commonStyles.buttonText}>+ Up Next</Text>
                    </TouchableOpacity>
                    <TouchableOpacity
                      style={[commonStyles.smallButton, styles.secondaryButton]}
                      onPress={() => handlePlayNext(track.id)}>
                      <Text style={commonStyles.buttonText}>⏭️ Play Next</Text>
                    </TouchableOpacity>
                  </View>
                </View>
              ))}
            </>
          ) : (
            <View style={styles.emptyState}>
              <Text style={styles.emptyStateText}>📝</Text>
              <Text style={commonStyles.infoText}>
                Create playlists in the Playlists tab to see available tracks
              </Text>
            </View>
          )}
        </View>

        {/* Current Queue View */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>
            📋 Actual Queue ({actualQueue.length})
          </Text>
          {actualQueue.length > 0 ? (
            <>
              <View style={styles.queueContainer}>
                {actualQueue.map((track: TrackItem, index: number) => {
                  const isCurrentTrack = currentTrack?.id === track.id;
                  return (
                    <View
                      key={`${track.id}-${index}`}
                      style={[
                        styles.queueItem,
                        isCurrentTrack && styles.currentTrackItem,
                      ]}>
                      <Text style={styles.queueItemLabel}>
                        {isCurrentTrack ? '▶️' : `${index + 1}`}
                      </Text>
                      <View style={styles.queueItemInfo}>
                        <Text style={styles.queueItemTitle}>{track.title}</Text>
                        <Text style={styles.queueItemArtist}>
                          {track.artist}
                        </Text>
                      </View>
                    </View>
                  );
                })}
              </View>

              <View style={styles.infoBox}>
                <Text style={commonStyles.infoText}>
                  💡 Tip: This shows the actual playback order including temporary
                  tracks from "Play Next" and "+ Up Next"
                </Text>
              </View>
            </>
          ) : (
            <View style={styles.emptyState}>
              <Text style={styles.emptyStateText}>🎵</Text>
              <Text style={commonStyles.infoText}>
                Load a playlist and start playing to see the queue
              </Text>
            </View>
          )}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  infoBox: {
    backgroundColor: colors.infoBackground,
    padding: spacing.md,
    borderRadius: borderRadius.md,
    borderLeftWidth: 4,
    borderLeftColor: colors.infoBorder,
    marginTop: spacing.md,
  },
  bold: {
    fontWeight: '700',
    color: colors.text,
  },
  trackTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: colors.text,
    marginBottom: 4,
  },
  trackArtist: {
    fontSize: 16,
    color: colors.textSecondary,
  },
  trackCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.cardBackground,
    padding: spacing.md,
    borderRadius: borderRadius.md,
    marginBottom: spacing.sm,
  },
  trackInfo: {
    flex: 1,
  },
  trackCardTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.text,
  },
  trackCardArtist: {
    fontSize: 13,
    color: colors.textSecondary,
  },
  sectionSubtitle: {
    fontSize: 13,
    color: colors.textSecondary,
    marginBottom: spacing.md,
    fontStyle: 'italic',
  },
  trackActions: {
    flexDirection: 'row',
    gap: 4,
  },
  primaryButton: {
    backgroundColor: colors.success,
  },
  secondaryButton: {
    backgroundColor: colors.secondary,
  },
  queueContainer: {
    backgroundColor: colors.cardBackground,
    borderRadius: borderRadius.md,
    overflow: 'hidden',
  },
  queueItem: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  currentTrackItem: {
    backgroundColor: colors.activeBackground,
    borderLeftWidth: 4,
    borderLeftColor: colors.primary,
  },
  queueItemLabel: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.textSecondary,
    width: 40,
    textAlign: 'center',
  },
  queueItemInfo: {
    flex: 1,
    marginLeft: spacing.sm,
  },
  queueItemTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 2,
  },
  queueItemArtist: {
    fontSize: 13,
    color: colors.textSecondary,
  },
  queueSectionHeader: {
    backgroundColor: colors.background,
    padding: spacing.sm,
    paddingHorizontal: spacing.md,
  },
  queueSectionTitle: {
    fontSize: 12,
    fontWeight: '700',
    color: colors.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  emptyQueue: {
    padding: spacing.xl,
    alignItems: 'center',
  },
  emptyState: {
    padding: spacing.xl * 2,
    alignItems: 'center',
  },
  emptyStateText: {
    fontSize: 48,
    marginBottom: spacing.md,
  },
});
