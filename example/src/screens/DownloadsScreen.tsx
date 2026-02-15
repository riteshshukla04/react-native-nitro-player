import React, { useEffect, useState } from 'react';
import {
  StyleSheet,
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  SafeAreaView,
  Alert,
} from 'react-native';
import {
  DownloadManager,
  useDownloadProgress,
  useDownloadedTracks,
  useDownloadActions,
  useDownloadStorage,
} from 'react-native-nitro-player';
import type { TrackItem, DownloadProgress } from 'react-native-nitro-player';
import { colors, commonStyles, spacing, borderRadius, typography } from '../styles/theme';
import { sampleTracks1, sampleTracks2, sampleTracks3 } from '../data/sampleTracks';

export default function DownloadsScreen() {
  const [activeTab, setActiveTab] = useState<'available' | 'downloaded' | 'progress'>('available');

  // Hooks
  const { progressList, isDownloading } = useDownloadProgress();
  const { downloadedTracks, downloadedPlaylists, isTrackDownloaded, refresh } = useDownloadedTracks();
  const { downloadTrack, deleteTrack, configure, setPlaybackSourcePreference } = useDownloadActions();
  const { storageInfo, formattedSize, formattedAvailable } = useDownloadStorage();

  // All available tracks
  const allTracks = [...sampleTracks1, ...sampleTracks2,...sampleTracks3];

  useEffect(() => {
    // Configure download manager on mount
    configure({
      storageLocation: 'private',
      maxConcurrentDownloads: 2,
      backgroundDownloadsEnabled: true,
      downloadArtwork: false,
      wifiOnlyDownloads: false,
    });

    // Set auto-prefer downloaded content
    setPlaybackSourcePreference('auto');
  }, [configure, setPlaybackSourcePreference]);

  const handleDownload = async (track: TrackItem) => {
    try {
      await downloadTrack(track);
      Alert.alert('Download Started', `Downloading "${track.title}"`);
    } catch (error) {
      Alert.alert('Error', `Failed to start download: ${error}`);
    }
  };

  const handleDelete = async (trackId: string) => {
    Alert.alert(
      'Delete Download',
      'Are you sure you want to delete this download?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              await deleteTrack(trackId);
              refresh();
              Alert.alert('Deleted', 'Download removed successfully');
            } catch (error) {
              Alert.alert('Error', `Failed to delete: ${error}`);
            }
          },
        },
      ]
    );
  };

  const handleDeleteAll = async () => {
    Alert.alert(
      'Delete All Downloads',
      'Are you sure you want to delete all downloads?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete All',
          style: 'destructive',
          onPress: async () => {
            try {
              await DownloadManager.deleteAllDownloads();
              refresh();
              Alert.alert('Deleted', 'All downloads removed');
            } catch (error) {
              Alert.alert('Error', `Failed to delete: ${error}`);
            }
          },
        },
      ]
    );
  };

  const renderAvailableTracks = () => (
    <View style={commonStyles.section}>
      <Text style={commonStyles.sectionTitle}>Available Tracks</Text>
      {allTracks.map((track) => {
        const downloaded = isTrackDownloaded(track.id);
        const downloading = progressList.some((p) => p.trackId === track.id);

        return (
          <View key={track.id} style={styles.trackCard}>
            <View style={styles.trackInfo}>
              <Text style={styles.trackTitle}>{track.title}</Text>
              <Text style={styles.trackArtist}>{track.artist}</Text>
              {downloaded && (
                <Text style={styles.downloadedBadge}>Downloaded</Text>
              )}
            </View>
            <View style={styles.trackActions}>
              {downloaded ? (
                <TouchableOpacity
                  style={[commonStyles.smallButton, styles.deleteButton]}
                  onPress={() => handleDelete(track.id)}>
                  <Text style={commonStyles.buttonText}>Delete</Text>
                </TouchableOpacity>
              ) : downloading ? (
                <Text style={styles.downloadingText}>Downloading...</Text>
              ) : (
                <TouchableOpacity
                  style={commonStyles.smallButton}
                  onPress={() => handleDownload(track)}>
                  <Text style={commonStyles.buttonText}>Download</Text>
                </TouchableOpacity>
              )}
            </View>
          </View>
        );
      })}
    </View>
  );

  const renderDownloadedTracks = () => (
    <View style={commonStyles.section}>
      <View style={styles.sectionHeader}>
        <Text style={commonStyles.sectionTitle}>Downloaded ({downloadedTracks.length})</Text>
        {downloadedTracks.length > 0 && (
          <TouchableOpacity
            style={[commonStyles.smallButton, styles.deleteButton]}
            onPress={handleDeleteAll}>
            <Text style={commonStyles.buttonText}>Delete All</Text>
          </TouchableOpacity>
        )}
      </View>

      {downloadedTracks.length === 0 ? (
        <Text style={commonStyles.infoText}>No downloaded tracks yet</Text>
      ) : (
        downloadedTracks.map((download) => (
          <View key={download.trackId} style={styles.trackCard}>
            <View style={styles.trackInfo}>
              <Text style={styles.trackTitle}>{download.originalTrack.title}</Text>
              <Text style={styles.trackArtist}>{download.originalTrack.artist}</Text>
              <Text style={styles.trackSize}>
                {formatBytes(download.fileSize)}
              </Text>
            </View>
            <TouchableOpacity
              style={[commonStyles.smallButton, styles.deleteButton]}
              onPress={() => handleDelete(download.trackId)}>
              <Text style={commonStyles.buttonText}>Delete</Text>
            </TouchableOpacity>
          </View>
        ))
      )}

      {downloadedPlaylists.length > 0 && (
        <>
          <Text style={[commonStyles.sectionTitle, { marginTop: spacing.lg }]}>
            Downloaded Playlists ({downloadedPlaylists.length})
          </Text>
          {downloadedPlaylists.map((playlist) => (
            <View key={playlist.playlistId} style={styles.playlistCard}>
              <Text style={styles.trackTitle}>{playlist.originalPlaylist.name}</Text>
              <Text style={styles.trackArtist}>
                {playlist.downloadedTracks.length} tracks - {formatBytes(playlist.totalSize)}
              </Text>
              <Text style={styles.trackSize}>
                {playlist.isComplete ? 'Complete' : 'Partial'}
              </Text>
            </View>
          ))}
        </>
      )}
    </View>
  );

  const renderProgress = () => (
    <View style={commonStyles.section}>
      <Text style={commonStyles.sectionTitle}>
        Active Downloads ({progressList.length})
      </Text>

      {progressList.length === 0 ? (
        <Text style={commonStyles.infoText}>No active downloads</Text>
      ) : (
        progressList.map((progress) => (
          <ProgressItem key={progress.downloadId} progress={progress} />
        ))
      )}
    </View>
  );

  const renderStorageInfo = () => (
    <View style={commonStyles.section}>
      <Text style={commonStyles.sectionTitle}>Storage</Text>
      <View style={styles.storageInfo}>
        <View style={styles.storageRow}>
          <Text style={styles.storageLabel}>Downloaded:</Text>
          <Text style={styles.storageValue}>{formattedSize}</Text>
        </View>
        <View style={styles.storageRow}>
          <Text style={styles.storageLabel}>Available:</Text>
          <Text style={styles.storageValue}>{formattedAvailable}</Text>
        </View>
        {storageInfo && (
          <>
            <View style={styles.storageRow}>
              <Text style={styles.storageLabel}>Tracks:</Text>
              <Text style={styles.storageValue}>{storageInfo.trackCount}</Text>
            </View>
            <View style={styles.storageRow}>
              <Text style={styles.storageLabel}>Playlists:</Text>
              <Text style={styles.storageValue}>{storageInfo.playlistCount}</Text>
            </View>
          </>
        )}
      </View>
    </View>
  );

  return (
    <SafeAreaView style={commonStyles.container}>
      {/* Tab Bar */}
      <View style={styles.tabBar}>
        <TouchableOpacity
          style={[styles.tab, activeTab === 'available' && styles.activeTab]}
          onPress={() => setActiveTab('available')}>
          <Text style={[styles.tabText, activeTab === 'available' && styles.activeTabText]}>
            Available
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.tab, activeTab === 'downloaded' && styles.activeTab]}
          onPress={() => setActiveTab('downloaded')}>
          <Text style={[styles.tabText, activeTab === 'downloaded' && styles.activeTabText]}>
            Downloaded
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.tab, activeTab === 'progress' && styles.activeTab]}
          onPress={() => setActiveTab('progress')}>
          <Text style={[styles.tabText, activeTab === 'progress' && styles.activeTabText]}>
            Progress {isDownloading && '(...)'}
          </Text>
        </TouchableOpacity>
      </View>

      <ScrollView style={commonStyles.scrollView}>
        {renderStorageInfo()}

        {activeTab === 'available' && renderAvailableTracks()}
        {activeTab === 'downloaded' && renderDownloadedTracks()}
        {activeTab === 'progress' && renderProgress()}
      </ScrollView>
    </SafeAreaView>
  );
}

// Progress Item Component
function ProgressItem({ progress }: { progress: DownloadProgress }) {
  const percentage = Math.round(progress.progress * 100);

  return (
    <View style={styles.progressCard}>
      <View style={styles.progressHeader}>
        <Text style={styles.trackTitle}>Track: {progress.trackId}</Text>
        <Text style={styles.progressPercent}>{percentage}%</Text>
      </View>
      <View style={styles.progressBarContainer}>
        <View style={[styles.progressBar, { width: `${percentage}%` }]} />
      </View>
      <View style={styles.progressDetails}>
        <Text style={styles.progressText}>
          {formatBytes(progress.bytesDownloaded)} / {formatBytes(progress.totalBytes)}
        </Text>
        <Text style={[styles.progressText, styles.stateText]}>
          {progress.state}
        </Text>
      </View>
    </View>
  );
}

// Helper function to format bytes
function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

const styles = StyleSheet.create({
  tabBar: {
    flexDirection: 'row',
    backgroundColor: colors.white,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  tab: {
    flex: 1,
    paddingVertical: spacing.sm,
    alignItems: 'center',
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  activeTab: {
    borderBottomColor: colors.primary,
  },
  tabText: {
    ...typography.button,
    color: colors.textSecondary,
  },
  activeTabText: {
    color: colors.primary,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: spacing.sm,
  },
  trackCard: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.cardBackground,
    padding: spacing.md,
    borderRadius: borderRadius.md,
    marginBottom: spacing.sm,
  },
  trackInfo: {
    flex: 1,
  },
  trackTitle: {
    ...typography.body,
    fontWeight: '600',
    color: colors.text,
  },
  trackArtist: {
    ...typography.caption,
    color: colors.textSecondary,
    marginTop: 2,
  },
  trackSize: {
    ...typography.small,
    color: colors.textTertiary,
    marginTop: 2,
  },
  trackActions: {
    marginLeft: spacing.md,
  },
  deleteButton: {
    backgroundColor: colors.danger,
  },
  downloadedBadge: {
    ...typography.small,
    color: colors.success,
    marginTop: 4,
  },
  downloadingText: {
    ...typography.caption,
    color: colors.primary,
  },
  playlistCard: {
    backgroundColor: colors.cardBackground,
    padding: spacing.md,
    borderRadius: borderRadius.md,
    marginBottom: spacing.sm,
  },
  progressCard: {
    backgroundColor: colors.cardBackground,
    padding: spacing.md,
    borderRadius: borderRadius.md,
    marginBottom: spacing.sm,
  },
  progressHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: spacing.sm,
  },
  progressPercent: {
    ...typography.button,
    color: colors.primary,
  },
  progressBarContainer: {
    height: 6,
    backgroundColor: colors.progressBackground,
    borderRadius: 3,
    overflow: 'hidden',
  },
  progressBar: {
    height: '100%',
    backgroundColor: colors.primary,
    borderRadius: 3,
  },
  progressDetails: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: spacing.sm,
  },
  progressText: {
    ...typography.small,
    color: colors.textSecondary,
  },
  stateText: {
    textTransform: 'capitalize',
  },
  storageInfo: {
    backgroundColor: colors.cardBackground,
    padding: spacing.md,
    borderRadius: borderRadius.md,
  },
  storageRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: spacing.xs,
  },
  storageLabel: {
    ...typography.body,
    color: colors.textSecondary,
  },
  storageValue: {
    ...typography.body,
    fontWeight: '600',
    color: colors.text,
  },
});
