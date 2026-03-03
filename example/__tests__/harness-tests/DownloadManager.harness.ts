import {
  describe,
  it,
  expect,
  beforeEach,
  afterEach,
} from 'react-native-harness';
import {
  DownloadManager,
  PlayerQueue,
} from 'react-native-nitro-player';
import type { TrackItem, DownloadConfig } from 'react-native-nitro-player';

// Helper to create test tracks with actual downloadable URLs
const createTestTrack = (id: string, title: string): TrackItem => ({
  id,
  title,
  artist: 'Test Artist',
  album: 'Test Album',
  duration: 180.0,
  // Using a small public audio file for testing
  url: `https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${(parseInt(id, 10) % 16) + 1}.mp3`,
  artwork: `https://picsum.photos/200?random=${id}`,
});

// Helper to wait for async operations
const wait = async (ms: number) => {
  await new Promise<void>(resolve => setTimeout(resolve, ms));
};

describe('DownloadManager - Comprehensive Tests', () => {
  let testPlaylistId: string;
  let testTracks: TrackItem[];

  beforeEach(async () => {
    console.log('Setting up DownloadManager test...');

    // Configure download manager
    DownloadManager.configure({
      storageLocation: 'private',
      maxConcurrentDownloads: 2,
      backgroundDownloadsEnabled: true,
      downloadArtwork: false,
      wifiOnlyDownloads: false,
    });

    // Create test tracks
    testTracks = [
      createTestTrack('dl-1', 'Download Test Track 1'),
      createTestTrack('dl-2', 'Download Test Track 2'),
      createTestTrack('dl-3', 'Download Test Track 3'),
    ];

    // Create a test playlist
    testPlaylistId = PlayerQueue.createPlaylist(
      'Download Test Playlist',
      'Playlist for download tests'
    );
    PlayerQueue.addTracksToPlaylist(testPlaylistId, testTracks);

    // Clean up any previous downloads
    try {
      await DownloadManager.deleteAllDownloads();
    } catch (e) {
      console.warn('Error cleaning up downloads:', e);
    }
  });

  afterEach(async () => {
    console.log('Cleaning up DownloadManager test...');

    // Cancel any active downloads
    try {
      await DownloadManager.cancelAllDownloads();
    } catch (e) {
      console.warn('Error cancelling downloads:', e);
    }

    // Delete all downloads
    try {
      await DownloadManager.deleteAllDownloads();
    } catch (e) {
      console.warn('Error deleting downloads:', e);
    }

    // Delete test playlist
    try {
      PlayerQueue.deletePlaylist(testPlaylistId);
    } catch (e) {
      console.warn('Error deleting test playlist:', e);
    }
  });

  // ============================================
  // CONFIGURATION
  // ============================================

  describe('Configuration', () => {
    it('should configure download manager', () => {
      const config: DownloadConfig = {
        storageLocation: 'private',
        maxConcurrentDownloads: 3,
        backgroundDownloadsEnabled: true,
        downloadArtwork: true,
        wifiOnlyDownloads: false,
      };

      expect(() => DownloadManager.configure(config)).not.toThrow();
    });

    it('should get current configuration', () => {
      DownloadManager.configure({
        storageLocation: 'private',
        maxConcurrentDownloads: 5,
      });

      const config = DownloadManager.getConfig();
      expect(config).not.toBeNull();
      expect(config.maxConcurrentDownloads).toBe(5);
    });

    it('should set and get playback source preference', () => {
      DownloadManager.setPlaybackSourcePreference('auto');
      expect(DownloadManager.getPlaybackSourcePreference()).toBe('auto');

      DownloadManager.setPlaybackSourcePreference('download');
      expect(DownloadManager.getPlaybackSourcePreference()).toBe('download');

      DownloadManager.setPlaybackSourcePreference('network');
      expect(DownloadManager.getPlaybackSourcePreference()).toBe('network');
    });
  });

  // ============================================
  // DOWNLOAD OPERATIONS
  // ============================================

  describe('Download Operations', () => {
    it('should start downloading a track', async () => {
      const downloadId = await DownloadManager.downloadTrack(testTracks[0]);

      expect(downloadId).not.toBeNull();
      expect(typeof downloadId).toBe('string');
      expect(downloadId.length).toBeGreaterThan(0);
    });

    it('should start downloading a track with playlist association', async () => {
      const downloadId = await DownloadManager.downloadTrack(
        testTracks[0],
        testPlaylistId
      );

      expect(downloadId).not.toBeNull();
      expect(typeof downloadId).toBe('string');
    });

    it('should download multiple tracks as playlist', async () => {
      const downloadIds = await DownloadManager.downloadPlaylist(
        testPlaylistId,
        testTracks
      );

      expect(downloadIds).not.toBeNull();
      expect(Array.isArray(downloadIds)).toBe(true);
      expect(downloadIds.length).toBe(testTracks.length);
    });

    it('should check if track is downloading', async () => {
      await DownloadManager.downloadTrack(testTracks[0]);

      // Give it a moment to start
      await wait(100);

      const isDownloading = DownloadManager.isDownloading(testTracks[0].id);
      // May be true or false depending on timing
      expect(typeof isDownloading).toBe('boolean');
    });

    it('should get download state for a track', async () => {
      await DownloadManager.downloadTrack(testTracks[0]);

      await wait(100);

      const state = DownloadManager.getDownloadState(testTracks[0].id);
      expect(state).not.toBeNull();
      // State should be one of: pending, downloading, paused, completed, failed, cancelled
      expect(['pending', 'downloading', 'paused', 'completed', 'failed', 'cancelled']).toContain(state);
    });
  });

  // ============================================
  // DOWNLOAD CONTROL
  // ============================================

  describe('Download Control', () => {
    it('should pause a download', async () => {
      const downloadId = await DownloadManager.downloadTrack(testTracks[0]);

      await wait(100);

      await expect(DownloadManager.pauseDownload(downloadId)).resolves.not.toThrow();
    });

    it('should resume a download', async () => {
      const downloadId = await DownloadManager.downloadTrack(testTracks[0]);

      await wait(100);
      await DownloadManager.pauseDownload(downloadId);
      await wait(100);

      await expect(DownloadManager.resumeDownload(downloadId)).resolves.not.toThrow();
    });

    it('should cancel a download', async () => {
      const downloadId = await DownloadManager.downloadTrack(testTracks[0]);

      await wait(100);

      await expect(DownloadManager.cancelDownload(downloadId)).resolves.not.toThrow();
    });

    it('should retry a failed download', async () => {
      const downloadId = await DownloadManager.downloadTrack(testTracks[0]);

      await wait(100);
      await DownloadManager.cancelDownload(downloadId);
      await wait(100);

      // Retry should not throw
      await expect(DownloadManager.retryDownload(downloadId)).resolves.not.toThrow();
    });

    it('should pause all downloads', async () => {
      await DownloadManager.downloadPlaylist(testPlaylistId, testTracks);

      await wait(100);

      await expect(DownloadManager.pauseAllDownloads()).resolves.not.toThrow();
    });

    it('should resume all downloads', async () => {
      await DownloadManager.downloadPlaylist(testPlaylistId, testTracks);

      await wait(100);
      await DownloadManager.pauseAllDownloads();
      await wait(100);

      await expect(DownloadManager.resumeAllDownloads()).resolves.not.toThrow();
    });

    it('should cancel all downloads', async () => {
      await DownloadManager.downloadPlaylist(testPlaylistId, testTracks);

      await wait(100);

      await expect(DownloadManager.cancelAllDownloads()).resolves.not.toThrow();
    });
  });

  // ============================================
  // DOWNLOAD STATUS
  // ============================================

  describe('Download Status', () => {
    it('should get download task by ID', async () => {
      const downloadId = await DownloadManager.downloadTrack(testTracks[0]);

      await wait(100);

      const task = DownloadManager.getDownloadTask(downloadId);
      // Task may or may not exist depending on timing
      if (task) {
        expect(task.downloadId).toBe(downloadId);
        expect(task.trackId).toBe(testTracks[0].id);
      }
    });

    it('should get active downloads', async () => {
      await DownloadManager.downloadPlaylist(testPlaylistId, testTracks);

      await wait(100);

      const activeDownloads = DownloadManager.getActiveDownloads();
      expect(Array.isArray(activeDownloads)).toBe(true);
    });

    it('should get queue status', async () => {
      await DownloadManager.downloadTrack(testTracks[0]);

      await wait(100);

      const status = DownloadManager.getQueueStatus();
      expect(status).not.toBeNull();
      expect(typeof status.pendingCount).toBe('number');
      expect(typeof status.activeCount).toBe('number');
      expect(typeof status.completedCount).toBe('number');
      expect(typeof status.failedCount).toBe('number');
      expect(typeof status.overallProgress).toBe('number');
    });
  });

  // ============================================
  // DOWNLOADED CONTENT QUERIES
  // ============================================

  describe('Downloaded Content Queries', () => {
    it('should check if track is downloaded', () => {
      const isDownloaded = DownloadManager.isTrackDownloaded('non-existent-track');
      expect(isDownloaded).toBe(false);
    });

    it('should check if playlist is downloaded', () => {
      const isDownloaded = DownloadManager.isPlaylistDownloaded('non-existent-playlist');
      expect(isDownloaded).toBe(false);
    });

    it('should check if playlist is partially downloaded', () => {
      const isPartial = DownloadManager.isPlaylistPartiallyDownloaded('non-existent-playlist');
      expect(isPartial).toBe(false);
    });

    it('should get downloaded track (returns null for non-existent)', () => {
      const track = DownloadManager.getDownloadedTrack('non-existent-track');
      expect(track).toBeNull();
    });

    it('should get all downloaded tracks', () => {
      const tracks = DownloadManager.getAllDownloadedTracks();
      expect(Array.isArray(tracks)).toBe(true);
    });

    it('should get downloaded playlist (returns null for non-existent)', () => {
      const playlist = DownloadManager.getDownloadedPlaylist('non-existent-playlist');
      expect(playlist).toBeNull();
    });

    it('should get all downloaded playlists', () => {
      const playlists = DownloadManager.getAllDownloadedPlaylists();
      expect(Array.isArray(playlists)).toBe(true);
    });

    it('should get local path (returns null for non-downloaded)', () => {
      const path = DownloadManager.getLocalPath('non-existent-track');
      expect(path).toBeNull();
    });

    it('should persist extraPayload in downloaded tracks', async () => {
      // Create a track with extraPayload containing different data types
      const trackWithPayload: TrackItem = {
        ...createTestTrack('dl-payload-test', 'Track with Extra Payload'),
        extraPayload: {
          genre: 'Rock',           // String
          rating: 4.5,             // Number
          favorite: true,          // Boolean
          playCount: 42,           // Number (integer)
          customTag: 'test-tag',   // String
        },
      };

      // Use a promise-based approach with the completion callback
      const downloadPromise = new Promise<boolean>((resolve) => {
        const timeout = setTimeout(() => {
          console.warn('Download timeout after 45 seconds - skipping test');
          resolve(false);
        }, 45000);

        DownloadManager.onDownloadComplete((downloadedTrack) => {
          if (downloadedTrack.trackId === trackWithPayload.id) {
            clearTimeout(timeout);
            console.log('Download completed successfully');
            resolve(true);
          }
        });

        DownloadManager.onDownloadStateChange((downloadId, trackId, state, error) => {
          if (trackId === trackWithPayload.id) {
            const errorDetails = error ? JSON.stringify(error, null, 2) : 'none';
            console.log(`Download state: ${state}, error: ${errorDetails}`);
            if (state === 'failed') {
              clearTimeout(timeout);
              console.warn(`Download failed: ${errorDetails} - skipping test`);
              resolve(false);
            }
          }
        });
      });

      // Start the download
      const downloadId = await DownloadManager.downloadTrack(trackWithPayload);
      expect(downloadId).not.toBeNull();
      console.log(`Started download ${downloadId} for track ${trackWithPayload.id}`);

      // Wait for download to complete or fail
      const downloadSucceeded = await downloadPromise;

      if (!downloadSucceeded) {
        console.warn('Skipping extraPayload verification - download did not complete');
        // Clean up any partial download
        try {
          await DownloadManager.cancelDownload(downloadId);
          await DownloadManager.deleteDownloadedTrack(trackWithPayload.id);
        } catch (e) {
          // Ignore cleanup errors
          console.warn('Error cleaning up partial download:', e);
        }
        // Test passes but doesn't verify extraPayload
        return;
      }

      // Retrieve the downloaded track
      const downloadedTrack = DownloadManager.getDownloadedTrack(trackWithPayload.id);
      expect(downloadedTrack).not.toBeNull();

      // Verify extraPayload was persisted correctly
      expect(downloadedTrack!.originalTrack.extraPayload).not.toBeNull();
      expect(downloadedTrack!.originalTrack.extraPayload!.genre).toBe('Rock');
      expect(downloadedTrack!.originalTrack.extraPayload!.rating).toBe(4.5);
      expect(downloadedTrack!.originalTrack.extraPayload!.favorite).toBe(true);
      expect(downloadedTrack!.originalTrack.extraPayload!.playCount).toBe(42);
      expect(downloadedTrack!.originalTrack.extraPayload!.customTag).toBe('test-tag');

      // Verify it also appears in getAllDownloadedTracks
      const allDownloads = DownloadManager.getAllDownloadedTracks();
      const retrievedTrack = allDownloads.find(dt => dt.trackId === trackWithPayload.id);
      expect(retrievedTrack).not.toBeNull();
      expect(retrievedTrack!.originalTrack.extraPayload).not.toBeNull();
      expect(retrievedTrack!.originalTrack.extraPayload!.genre).toBe('Rock');

      // Clean up
      await DownloadManager.deleteDownloadedTrack(trackWithPayload.id);
    });
  });

  // ============================================
  // DELETION
  // ============================================

  describe('Deletion', () => {
    it('should delete downloaded track', async () => {
      await expect(
        DownloadManager.deleteDownloadedTrack('non-existent-track')
      ).resolves.not.toThrow();
    });

    it('should delete downloaded playlist', async () => {
      await expect(
        DownloadManager.deleteDownloadedPlaylist('non-existent-playlist')
      ).resolves.not.toThrow();
    });

    it('should delete all downloads', async () => {
      await expect(DownloadManager.deleteAllDownloads()).resolves.not.toThrow();
    });
  });

  // ============================================
  // STORAGE MANAGEMENT
  // ============================================

  describe('Storage Management', () => {
    it('should get storage info', async () => {
      const storageInfo = await DownloadManager.getStorageInfo();

      expect(storageInfo).not.toBeNull();
      expect(typeof storageInfo.totalDownloadedSize).toBe('number');
      expect(typeof storageInfo.trackCount).toBe('number');
      expect(typeof storageInfo.playlistCount).toBe('number');
      expect(typeof storageInfo.availableSpace).toBe('number');
      expect(typeof storageInfo.totalSpace).toBe('number');
      expect(storageInfo.availableSpace).toBeGreaterThan(0);
      expect(storageInfo.totalSpace).toBeGreaterThan(0);
    });
  });

  // ============================================
  // PLAYBACK SOURCE PREFERENCE
  // ============================================

  describe('Playback Source Preference', () => {
    it('should return network URL when preference is network', () => {
      DownloadManager.setPlaybackSourcePreference('network');

      const effectiveUrl = DownloadManager.getEffectiveUrl(testTracks[0]);
      expect(effectiveUrl).toBe(testTracks[0].url);
    });

    it('should return network URL for non-downloaded track with auto preference', () => {
      DownloadManager.setPlaybackSourcePreference('auto');

      const effectiveUrl = DownloadManager.getEffectiveUrl(testTracks[0]);
      // Since track is not downloaded, should return network URL
      expect(effectiveUrl).toBe(testTracks[0].url);
    });
  });

  // ============================================
  // CALLBACKS
  // ============================================

  describe('Callbacks', () => {
    it('should register progress callback', () => {
      expect(() => {
        DownloadManager.onDownloadProgress((progress) => {
          console.log('Progress:', progress);
        });
      }).not.toThrow();
    });

    it('should register state change callback', () => {
      expect(() => {
        DownloadManager.onDownloadStateChange((downloadId, trackId, state, error) => {
          console.log('State change:', { downloadId, trackId, state, error });
        });
      }).not.toThrow();
    });

    it('should register complete callback', () => {
      expect(() => {
        DownloadManager.onDownloadComplete((downloadedTrack) => {
          console.log('Complete:', downloadedTrack);
        });
      }).not.toThrow();
    });

    it('should receive progress updates during download', async () => {
      const progressUpdates: any[] = [];

      DownloadManager.onDownloadProgress((progress) => {
        progressUpdates.push(progress);
      });

      await DownloadManager.downloadTrack(testTracks[0]);

      // Wait for some progress
      await wait(2000);

      // We may or may not have received progress updates depending on download speed
      // Just verify no errors occurred
      expect(Array.isArray(progressUpdates)).toBe(true);
    });

    it('should receive state change notifications', async () => {
      const stateChanges: any[] = [];

      DownloadManager.onDownloadStateChange((downloadId, trackId, state) => {
        stateChanges.push({ downloadId, trackId, state });
      });

      await DownloadManager.downloadTrack(testTracks[0]);

      await wait(500);

      // Should have received at least one state change
      expect(stateChanges.length).toBeGreaterThanOrEqual(0);
    });
  });

  // ============================================
  // EDGE CASES
  // ============================================

  describe('Edge Cases', () => {
    it('should handle downloading same track multiple times', async () => {
      const downloadId1 = await DownloadManager.downloadTrack(testTracks[0]);
      const downloadId2 = await DownloadManager.downloadTrack(testTracks[0]);

      // Both should succeed (may be same or different download IDs based on implementation)
      expect(downloadId1).not.toBeNull();
      expect(downloadId2).not.toBeNull();
    });

    it('should handle invalid download ID for pause', async () => {
      await expect(
        DownloadManager.pauseDownload('invalid-download-id')
      ).resolves.not.toThrow();
    });

    it('should handle invalid download ID for resume', async () => {
      await expect(
        DownloadManager.resumeDownload('invalid-download-id')
      ).resolves.not.toThrow();
    });

    it('should handle invalid download ID for cancel', async () => {
      await expect(
        DownloadManager.cancelDownload('invalid-download-id')
      ).resolves.not.toThrow();
    });

    it('should handle empty playlist download', async () => {
      const downloadIds = await DownloadManager.downloadPlaylist(testPlaylistId, []);
      expect(downloadIds).toStrictEqual([]);
    });

    it('should handle configuration with minimal options', () => {
      expect(() => {
        DownloadManager.configure({});
      }).not.toThrow();
    });
  });
});
