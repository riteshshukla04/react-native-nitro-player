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
  PlayerQueue,
  TrackPlayer,
  usePlaylist,
} from 'react-native-nitro-player';
import type { TrackItem } from 'react-native-nitro-player';
import { lazyLoadedTracks, sampleTracks1, sampleTracks2, sampleTracks3 } from '../data/sampleTracks';
import { colors, commonStyles, spacing, borderRadius } from '../styles/theme';

export default function PlaylistsScreen() {
  const {
    allPlaylists: playlists,
    currentPlaylistId,
    currentPlaylist,
    refreshPlaylists,
    isLoading,
  } = usePlaylist();

  const createPlaylist = useCallback((
    name: string,
    description: string,
    tracks: TrackItem[],
  ) => {
    const playlistId = PlayerQueue.createPlaylist(
      name,
      description,
      tracks[0]?.artwork || undefined,
    );
    PlayerQueue.addTracksToPlaylist(playlistId, tracks);
    refreshPlaylists();
  }, [refreshPlaylists]);

  const loadPlaylist = useCallback((playlistId: string) => {
    PlayerQueue.loadPlaylist(playlistId);
    // Refresh to update currentPlaylistId after loading
    setTimeout(refreshPlaylists, 100);
  }, [refreshPlaylists]);

  const deletePlaylist = useCallback((playlistId: string) => {
    PlayerQueue.deletePlaylist(playlistId);
    refreshPlaylists();
  }, [refreshPlaylists]);

  return (
    <SafeAreaView style={commonStyles.container}>
      <ScrollView
        style={commonStyles.scrollView}
        refreshControl={
          <RefreshControl
            refreshing={isLoading}
            onRefresh={refreshPlaylists}
            tintColor={colors.primary}
          />
        }>
        {/* Create Playlists */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>Create Playlists</Text>
          <TouchableOpacity
            style={commonStyles.button}
            onPress={() =>
              createPlaylist('Chill Vibes', 'Relaxing music', sampleTracks1)
            }>
            <Text style={commonStyles.buttonText}>Create "Chill Vibes"</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={commonStyles.button}
            onPress={() =>
              createPlaylist('Nature Sounds', 'Sounds of nature', sampleTracks2)
            }>
            <Text style={commonStyles.buttonText}>Create "Nature Sounds"</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={commonStyles.button}
            onPress={() =>
              createPlaylist('Test Tracks', '19 test songs for performance testing', sampleTracks3)
            }>
            <Text style={commonStyles.buttonText}>Create "Test Tracks" (19 songs)</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={commonStyles.button}
            onPress={() => {
              createPlaylist('Lazy Loaded Tracks', `${lazyLoadedTracks.length} Test Tracks with empty URLs for lazy loading`, lazyLoadedTracks)
            }}>
            <Text style={commonStyles.buttonText}>{`Create "Lazy Loaded Tracks" (${lazyLoadedTracks.length} songs)`}</Text>
          </TouchableOpacity>
        </View>

        {/* Playlists List */}
        <View style={commonStyles.section}>
          <Text style={commonStyles.sectionTitle}>
            My Playlists ({playlists.length})
          </Text>
          {playlists.map((playlist) => (
            <View
              key={playlist.id}
              style={[
                styles.playlistCard,
                playlist.id === currentPlaylistId && styles.activePlaylistCard,
              ]}>
              <View style={styles.playlistInfo}>
                <Text style={styles.playlistName}>
                  {playlist.name}
                  {playlist.id === currentPlaylistId && ' ✓'}
                </Text>
                <Text style={styles.playlistDescription}>
                  {playlist.description}
                </Text>
                <Text style={styles.playlistMeta}>
                  {playlist.tracks.length} tracks
                </Text>
              </View>
              <View style={styles.playlistActions}>
                {playlist.id !== currentPlaylistId && (
                  <TouchableOpacity
                    style={commonStyles.smallButton}
                    onPress={() => loadPlaylist(playlist.id)}>
                    <Text style={commonStyles.buttonText}>Load</Text>
                  </TouchableOpacity>
                )}
                <TouchableOpacity
                  style={[commonStyles.smallButton, styles.dangerButton]}
                  onPress={() => deletePlaylist(playlist.id)}>
                  <Text style={commonStyles.buttonText}>Delete</Text>
                </TouchableOpacity>
              </View>
            </View>
          ))}
          {playlists.length === 0 && (
            <Text style={commonStyles.infoText}>
              No playlists yet. Create one above!
            </Text>
          )}
        </View>

        {/* Current Playlist Tracks */}
        {currentPlaylist && (
          <View style={commonStyles.section}>
            <Text style={commonStyles.sectionTitle}>Current Playlist Tracks</Text>
            {currentPlaylist.tracks.map((track, index) => (
              <View key={track.id} style={styles.trackCard}>
                <Text style={styles.trackNumber}>{index + 1}.</Text>
                <View style={styles.trackInfo}>
                  <Text style={styles.trackCardTitle}>{track.title}</Text>
                  <Text style={styles.trackCardArtist}>{track.artist}</Text>
                </View>
                <TouchableOpacity
                  style={styles.iconButton}
                  onPress={async () => await TrackPlayer.playSong(track.id)}>
                  <Text>▶️</Text>
                </TouchableOpacity>
              </View>
            ))}
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  playlistCard: {
    backgroundColor: colors.cardBackground,
    padding: spacing.md,
    borderRadius: borderRadius.md,
    marginBottom: spacing.sm,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  activePlaylistCard: {
    borderColor: colors.activeBorder,
    backgroundColor: colors.activeBackground,
  },
  playlistInfo: {
    marginBottom: spacing.sm,
  },
  playlistName: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 4,
  },
  playlistDescription: {
    fontSize: 14,
    color: colors.textSecondary,
    marginBottom: 4,
  },
  playlistMeta: {
    fontSize: 12,
    color: colors.textTertiary,
  },
  playlistActions: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  dangerButton: {
    backgroundColor: colors.danger,
  },
  trackCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.cardBackground,
    padding: spacing.md,
    borderRadius: borderRadius.md,
    marginBottom: spacing.sm,
  },
  trackNumber: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.textSecondary,
    marginRight: spacing.md,
    width: 30,
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
  iconButton: {
    padding: spacing.sm,
  },
});
