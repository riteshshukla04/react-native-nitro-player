import {
  describe,
  it,
  expect,
  beforeEach,
  beforeAll,
  afterEach,
} from 'react-native-harness';
import { PlayerQueue, TrackItem, Playlist } from 'react-native-nitro-player';
import { sampleTracks1, sampleTracks2 } from '../../src/data/sampleTracks';

// Helper to create additional test tracks
const createTestTrack = (id: string, title: string): TrackItem => ({
  id,
  title,
  artist: 'Test Artist',
  album: 'Test Album',
  duration: 180.0,
  url: `https://example.com/track-${id}.mp3`,
  artwork: `https://example.com/artwork-${id}.jpg`,
  extraPayload: undefined,
});

describe('PlayerQueue - Comprehensive Playlist Tests', () => {
  let createdPlaylistIds: string[] = [];

  // Clear all existing playlists before running tests
  beforeAll(() => {
    console.log('Clearing all existing playlists before tests...');
    const existingPlaylists = PlayerQueue.getAllPlaylists();
    existingPlaylists.forEach((playlist) => {
      try {
        PlayerQueue.deletePlaylist(playlist.id);
      } catch (e) {
        console.warn('Error deleting existing playlist:', e);
      }
    });
  });

  beforeEach(() => {
    console.log('Setting up test...');
    createdPlaylistIds = [];
  });

  afterEach(() => {
    console.log('Cleaning up test...');

    // Clean up all created playlists
    createdPlaylistIds.forEach(id => {
      try {
        PlayerQueue.deletePlaylist(id);
      } catch (e) {
        console.warn('Error deleting playlist:', e);
      }
    });
    createdPlaylistIds = [];
  });

  // ============================================
  // PLAYLIST CRUD OPERATIONS
  // ============================================

  describe('Playlist Creation', () => {
    it('should create playlist with all fields', () => {
      const playlistId = PlayerQueue.createPlaylist(
        'My Playlist',
        'Playlist description',
        'https://example.com/playlist-artwork.jpg'
      );
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const actualPlaylist = [{
        artwork: 'https://example.com/playlist-artwork.jpg',
        description: 'Playlist description',
        id: playlistId,
        name: 'My Playlist',
        tracks: sampleTracks1,
      }];

      expect(PlayerQueue.getAllPlaylists()).toStrictEqual(actualPlaylist);
    });

    it('should create playlist with minimal fields', () => {
      const playlistId = PlayerQueue.createPlaylist('Minimal Playlist');
      createdPlaylistIds.push(playlistId);

      const playlist = PlayerQueue.getPlaylist(playlistId);

      expect(playlist).not.toBeNull();
      expect(playlist?.name).toBe('Minimal Playlist');
      expect(playlist?.description).toBeUndefined();
      expect(playlist?.artwork).toBeUndefined();
      expect(playlist?.tracks).toStrictEqual([]);
    });

    it('should create multiple playlists independently', () => {
      const playlist1Id = PlayerQueue.createPlaylist('Playlist 1', 'First playlist');
      const playlist2Id = PlayerQueue.createPlaylist('Playlist 2', 'Second playlist');
      const playlist3Id = PlayerQueue.createPlaylist('Playlist 3', 'Third playlist');

      createdPlaylistIds.push(playlist1Id, playlist2Id, playlist3Id);

      PlayerQueue.addTracksToPlaylist(playlist1Id, [sampleTracks1[0]]);
      PlayerQueue.addTracksToPlaylist(playlist2Id, [sampleTracks1[1]]);
      PlayerQueue.addTracksToPlaylist(playlist3Id, [sampleTracks1[2]]);

      const allPlaylists = PlayerQueue.getAllPlaylists();

      expect(allPlaylists.length).toBe(3);
      expect(allPlaylists[0].tracks.length).toBe(1);
      expect(allPlaylists[1].tracks.length).toBe(1);
      expect(allPlaylists[2].tracks.length).toBe(1);
    });
  });

  describe('Playlist Retrieval', () => {
    it('should get playlist by id', () => {
      const playlistId = PlayerQueue.createPlaylist('Test Playlist', 'Test description');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const playlist = PlayerQueue.getPlaylist(playlistId);

      expect(playlist).not.toBeNull();
      expect(playlist?.id).toBe(playlistId);
      expect(playlist?.name).toBe('Test Playlist');
      expect(playlist?.description).toBe('Test description');
      expect(playlist?.tracks).toStrictEqual(sampleTracks1);
    });

    it('should return null for non-existent playlist', () => {
      const playlist = PlayerQueue.getPlaylist('non-existent-id');
      expect(playlist).toBeNull();
    });

    it('should get all playlists', () => {
      const id1 = PlayerQueue.createPlaylist('Playlist A');
      const id2 = PlayerQueue.createPlaylist('Playlist B');
      createdPlaylistIds.push(id1, id2);

      const allPlaylists = PlayerQueue.getAllPlaylists();

      expect(allPlaylists.length).toBe(2);
      expect(allPlaylists.map(p => p.name)).toContain('Playlist A');
      expect(allPlaylists.map(p => p.name)).toContain('Playlist B');
    });
  });

  describe('Playlist Update', () => {
    it('should update playlist name', () => {
      const playlistId = PlayerQueue.createPlaylist('Original Name', 'Description');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.updatePlaylist(playlistId, 'Updated Name');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.name).toBe('Updated Name');
      expect(playlist?.description).toBe('Description');
    });

    it('should update playlist description', () => {
      const playlistId = PlayerQueue.createPlaylist('Name', 'Original Description');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.updatePlaylist(playlistId, undefined, 'Updated Description');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.name).toBe('Name');
      expect(playlist?.description).toBe('Updated Description');
    });

    it('should update playlist artwork', () => {
      const playlistId = PlayerQueue.createPlaylist('Name', 'Description', 'original.jpg');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.updatePlaylist(playlistId, undefined, undefined, 'updated.jpg');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.artwork).toBe('updated.jpg');
    });

    it('should update all playlist fields at once', () => {
      const playlistId = PlayerQueue.createPlaylist('Old Name', 'Old Desc', 'old.jpg');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.updatePlaylist(playlistId, 'New Name', 'New Desc', 'new.jpg');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.name).toBe('New Name');
      expect(playlist?.description).toBe('New Desc');
      expect(playlist?.artwork).toBe('new.jpg');
    });
  });

  describe('Playlist Deletion', () => {
    it('should delete playlist', () => {
      const playlistId = PlayerQueue.createPlaylist('To Delete');
      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      PlayerQueue.deletePlaylist(playlistId);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist).toBeNull();
    });

    it('should remove deleted playlist from all playlists', () => {
      const id1 = PlayerQueue.createPlaylist('Keep This');
      const id2 = PlayerQueue.createPlaylist('Delete This');
      createdPlaylistIds.push(id1); // Only track the one we keep

      PlayerQueue.deletePlaylist(id2);

      const allPlaylists = PlayerQueue.getAllPlaylists();
      expect(allPlaylists.length).toBe(1);
      expect(allPlaylists[0].id).toBe(id1);
    });
  });

  // ============================================
  // TRACK MANAGEMENT
  // ============================================

  describe('Adding Tracks', () => {
    it('should add single track to playlist', () => {
      const playlistId = PlayerQueue.createPlaylist('Single Track Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(1);
      expect(playlist?.tracks[0]).toStrictEqual(sampleTracks1[0]);
    });

    it('should add multiple tracks to playlist', () => {
      const playlistId = PlayerQueue.createPlaylist('Multiple Tracks Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(sampleTracks1.length);
      expect(playlist?.tracks).toStrictEqual(sampleTracks1);
    });

    it('should add track at specific index', () => {
      const playlistId = PlayerQueue.createPlaylist('Index Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, [sampleTracks1[0], sampleTracks1[2]]);
      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[1], 1);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(3);
      expect(playlist?.tracks[0].id).toBe('1');
      expect(playlist?.tracks[1].id).toBe('2');
      expect(playlist?.tracks[2].id).toBe('3');
    });

    it('should add tracks at specific index', () => {
      const playlistId = PlayerQueue.createPlaylist('Batch Index Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);
      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[2]);
      PlayerQueue.addTracksToPlaylist(playlistId, [sampleTracks2[0], sampleTracks2[1]], 1);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(4);
      expect(playlist?.tracks[0].id).toBe('1');
      expect(playlist?.tracks[1].id).toBe('4');
      expect(playlist?.tracks[2].id).toBe('5');
      expect(playlist?.tracks[3].id).toBe('3');
    });

    it('should handle adding duplicate tracks', () => {
      const playlistId = PlayerQueue.createPlaylist('Duplicate Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);
      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(2);
      expect(playlist?.tracks[0]).toStrictEqual(sampleTracks1[0]);
      expect(playlist?.tracks[1]).toStrictEqual(sampleTracks1[0]);
    });
  });

  describe('Removing Tracks', () => {
    it('should remove track from playlist', () => {
      const playlistId = PlayerQueue.createPlaylist('Remove Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
      PlayerQueue.removeTrackFromPlaylist(playlistId, '2');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(2);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['1', '3']);
    });

    it('should remove all instances of duplicate tracks', () => {
      const playlistId = PlayerQueue.createPlaylist('Remove Duplicates Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);
      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[1]);
      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);

      PlayerQueue.removeTrackFromPlaylist(playlistId, '1');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(1);
      expect(playlist?.tracks[0].id).toBe('2');
    });

    it('should handle removing non-existent track', () => {
      const playlistId = PlayerQueue.createPlaylist('Remove Non-existent Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      // This should not throw an error
      PlayerQueue.removeTrackFromPlaylist(playlistId, 'non-existent-id');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(3);
    });
  });

  describe('Reordering Tracks', () => {
    it('should reorder track to beginning', () => {
      const playlistId = PlayerQueue.createPlaylist('Reorder Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
      PlayerQueue.reorderTrackInPlaylist(playlistId, '3', 0);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['3', '1', '2']);
    });

    it('should reorder track to end', () => {
      const playlistId = PlayerQueue.createPlaylist('Reorder End Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
      PlayerQueue.reorderTrackInPlaylist(playlistId, '1', 2);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['2', '3', '1']);
    });

    it('should reorder track to middle', () => {
      const playlistId = PlayerQueue.createPlaylist('Reorder Middle Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
      PlayerQueue.reorderTrackInPlaylist(playlistId, '1', 1);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['2', '1', '3']);
    });

    it('should handle complex reordering sequence', () => {
      const playlistId = PlayerQueue.createPlaylist('Complex Reorder Test');
      createdPlaylistIds.push(playlistId);

      const tracks = [
        createTestTrack('A', 'Track A'),
        createTestTrack('B', 'Track B'),
        createTestTrack('C', 'Track C'),
        createTestTrack('D', 'Track D'),
        createTestTrack('E', 'Track E'),
      ];

      PlayerQueue.addTracksToPlaylist(playlistId, tracks);

      // Move E to position 1
      PlayerQueue.reorderTrackInPlaylist(playlistId, 'E', 1);
      let playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['A', 'E', 'B', 'C', 'D']);

      // Move A to position 3
      PlayerQueue.reorderTrackInPlaylist(playlistId, 'A', 3);
      playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['E', 'B', 'C', 'A', 'D']);

      // Move D to position 0
      PlayerQueue.reorderTrackInPlaylist(playlistId, 'D', 0);
      playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['D', 'E', 'B', 'C', 'A']);
    });
  });

  // ============================================
  // PLAYLIST LOADING
  // ============================================

  describe('Playlist Loading', () => {
    it('should load playlist', () => {
      const playlistId = PlayerQueue.createPlaylist('Load Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
      PlayerQueue.loadPlaylist(playlistId);

      const currentPlaylistId = PlayerQueue.getCurrentPlaylistId();
      expect(currentPlaylistId).toBe(playlistId);
    });

    it('should switch between playlists', () => {
      const playlist1Id = PlayerQueue.createPlaylist('Playlist 1');
      const playlist2Id = PlayerQueue.createPlaylist('Playlist 2');
      createdPlaylistIds.push(playlist1Id, playlist2Id);

      PlayerQueue.addTracksToPlaylist(playlist1Id, sampleTracks1);
      PlayerQueue.addTracksToPlaylist(playlist2Id, sampleTracks2);

      PlayerQueue.loadPlaylist(playlist1Id);
      expect(PlayerQueue.getCurrentPlaylistId()).toBe(playlist1Id);

      PlayerQueue.loadPlaylist(playlist2Id);
      expect(PlayerQueue.getCurrentPlaylistId()).toBe(playlist2Id);
    });
  });

  // ============================================
  // EDGE CASES AND COMPLEX SCENARIOS
  // ============================================

  describe('Edge Cases', () => {
    it('should handle empty playlist operations', () => {
      const playlistId = PlayerQueue.createPlaylist('Empty Playlist');
      createdPlaylistIds.push(playlistId);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks).toStrictEqual([]);

      // Try to remove from empty playlist
      PlayerQueue.removeTrackFromPlaylist(playlistId, 'non-existent');
      expect(playlist?.tracks).toStrictEqual([]);
    });

    it('should handle large playlist with many tracks', () => {
      const playlistId = PlayerQueue.createPlaylist('Large Playlist');
      createdPlaylistIds.push(playlistId);

      const manyTracks: TrackItem[] = [];
      for (let i = 0; i < 100; i++) {
        manyTracks.push(createTestTrack(`track-${i}`, `Track ${i}`));
      }

      PlayerQueue.addTracksToPlaylist(playlistId, manyTracks);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(100);
    });

    it('should maintain playlist integrity after multiple operations', () => {
      const playlistId = PlayerQueue.createPlaylist('Integrity Test');
      createdPlaylistIds.push(playlistId);

      // Add tracks
      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      // Update playlist
      PlayerQueue.updatePlaylist(playlistId, 'Updated Name', 'Updated Description');

      // Add more tracks
      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks2);

      // Remove a track
      PlayerQueue.removeTrackFromPlaylist(playlistId, '2');

      // Reorder tracks
      PlayerQueue.reorderTrackInPlaylist(playlistId, '4', 0);

      const playlist = PlayerQueue.getPlaylist(playlistId);

      expect(playlist?.name).toBe('Updated Name');
      expect(playlist?.description).toBe('Updated Description');
      expect(playlist?.tracks.length).toBe(4);
      expect(playlist?.tracks[0].id).toBe('4');
    });

    it('should handle rapid successive operations', () => {
      const playlistId = PlayerQueue.createPlaylist('Rapid Operations Test');
      createdPlaylistIds.push(playlistId);

      // Perform multiple operations in quick succession
      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);
      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[1]);
      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[2]);
      PlayerQueue.removeTrackFromPlaylist(playlistId, '2');
      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks2[0]);
      PlayerQueue.reorderTrackInPlaylist(playlistId, '4', 0);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(3);
      expect(playlist?.tracks[0].id).toBe('4');
    });

    it('should handle special characters in playlist metadata', () => {
      const specialName = "Test's \"Playlist\" with <special> & chars!";
      const specialDesc = "Description with émojis 🎵🎶 and symbols @#$%";

      const playlistId = PlayerQueue.createPlaylist(specialName, specialDesc);
      createdPlaylistIds.push(playlistId);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.name).toBe(specialName);
      expect(playlist?.description).toBe(specialDesc);
    });

    it('should handle playlist with tracks having null/undefined optional fields', () => {
      const playlistId = PlayerQueue.createPlaylist('Null Fields Test');
      createdPlaylistIds.push(playlistId);

      const trackWithNulls: TrackItem = {
        id: 'null-track',
        title: 'Track with Nulls',
        artist: 'Artist',
        album: 'Album',
        duration: 180,
        url: 'https://example.com/track.mp3',
        artwork: null,
      };

      PlayerQueue.addTrackToPlaylist(playlistId, trackWithNulls);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks[0].artwork).toBeNull();
    });
  });

  describe('Complex Integration Scenarios', () => {
    it('should handle creating, modifying, and deleting multiple playlists', () => {
      // Create multiple playlists
      const ids = [
        PlayerQueue.createPlaylist('Rock Classics'),
        PlayerQueue.createPlaylist('Jazz Standards'),
        PlayerQueue.createPlaylist('Electronic Beats'),
      ];
      createdPlaylistIds.push(...ids);

      // Add different tracks to each
      PlayerQueue.addTracksToPlaylist(ids[0], [sampleTracks1[0]]);
      PlayerQueue.addTracksToPlaylist(ids[1], [sampleTracks1[1]]);
      PlayerQueue.addTracksToPlaylist(ids[2], [sampleTracks1[2]]);

      // Update one
      PlayerQueue.updatePlaylist(ids[1], 'Modern Jazz');

      // Delete one
      PlayerQueue.deletePlaylist(ids[2]);
      createdPlaylistIds = createdPlaylistIds.filter(id => id !== ids[2]);

      const allPlaylists = PlayerQueue.getAllPlaylists();
      expect(allPlaylists.length).toBe(2);
      expect(allPlaylists.find(p => p.name === 'Modern Jazz')).toBeDefined();
      expect(allPlaylists.find(p => p.name === 'Electronic Beats')).toBeUndefined();
    });

    it('should handle moving tracks between playlists', () => {
      const playlist1Id = PlayerQueue.createPlaylist('Source Playlist');
      const playlist2Id = PlayerQueue.createPlaylist('Destination Playlist');
      createdPlaylistIds.push(playlist1Id, playlist2Id);

      PlayerQueue.addTracksToPlaylist(playlist1Id, sampleTracks1);

      // "Move" a track by adding to second playlist and removing from first
      const trackToMove = sampleTracks1[1];
      PlayerQueue.addTrackToPlaylist(playlist2Id, trackToMove);
      PlayerQueue.removeTrackFromPlaylist(playlist1Id, trackToMove.id);

      const playlist1 = PlayerQueue.getPlaylist(playlist1Id);
      const playlist2 = PlayerQueue.getPlaylist(playlist2Id);

      expect(playlist1?.tracks.length).toBe(2);
      expect(playlist2?.tracks.length).toBe(1);
      expect(playlist2?.tracks[0].id).toBe(trackToMove.id);
    });

    it('should handle playlist with mixed track sources', () => {
      const playlistId = PlayerQueue.createPlaylist('Mixed Sources');
      createdPlaylistIds.push(playlistId);

      // Add tracks from different sample sets
      PlayerQueue.addTracksToPlaylist(playlistId, [sampleTracks1[0], sampleTracks1[1]]);
      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks2);
      PlayerQueue.addTrackToPlaylist(playlistId, createTestTrack('custom', 'Custom Track'));

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(5);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['1', '2', '4', '5', 'custom']);
    });
  });

  // ============================================
  // CALLBACKS AND LISTENERS
  // ============================================

  describe('Playlist Callbacks', () => {
    // Helper to wait for callbacks to trigger
    const waitForNextTick = async () => {
      await new Promise<void>(resolve => setTimeout(resolve, 500));
    };

    it('should trigger onPlaylistsChanged when playlist is created', async () => {
      const changedPlaylists: Playlist[][] = [];
      const operations: (string | undefined)[] = [];

      PlayerQueue.onPlaylistsChanged((playlists, operation) => {
        changedPlaylists.push(playlists);
        operations.push(operation);
      });

      const playlistId = PlayerQueue.createPlaylist('Callback Test', 'Test Description');
      createdPlaylistIds.push(playlistId);

      // Wait for callback to trigger
      await waitForNextTick();

      expect(operations).toContain('add');
      expect(changedPlaylists.length).toBeGreaterThan(0);
      expect(changedPlaylists[changedPlaylists.length - 1].some(p => p.id === playlistId)).toBe(true);
    });

    it('should trigger onPlaylistsChanged when playlist is deleted', async () => {
      const playlistId = PlayerQueue.createPlaylist('Delete Callback Test');
      createdPlaylistIds.push(playlistId);

      const operations: (string | undefined)[] = [];
      let deletedPlaylistId: string | null = null;

      PlayerQueue.onPlaylistsChanged((playlists, operation) => {
        operations.push(operation);
        if (operation === 'remove') {
          deletedPlaylistId = playlistId;
        }
      });

      await waitForNextTick();
      PlayerQueue.deletePlaylist(playlistId);
      createdPlaylistIds = createdPlaylistIds.filter(id => id !== playlistId);

      await waitForNextTick();

      expect(operations).toContain('remove');
      expect(deletedPlaylistId).toBe(playlistId);
    });

    it('should trigger onPlaylistsChanged when playlist is updated', async () => {
      const playlistId = PlayerQueue.createPlaylist('Update Callback Test', 'Original');
      createdPlaylistIds.push(playlistId);

      const operations: (string | undefined)[] = [];
      const updatedPlaylists: Playlist[][] = [];

      PlayerQueue.onPlaylistsChanged((playlists, operation) => {
        operations.push(operation);
        if (operation === 'update') {
          updatedPlaylists.push(playlists);
        }
      });

      await waitForNextTick();
      PlayerQueue.updatePlaylist(playlistId, 'Updated Name', 'Updated Description');

      await waitForNextTick();

      expect(operations).toContain('update');
      expect(updatedPlaylists.length).toBeGreaterThan(0);
      const updatedPlaylist = updatedPlaylists[0].find(p => p.id === playlistId);
      expect(updatedPlaylist?.name).toBe('Updated Name');
    });

    it('should trigger onPlaylistChanged when tracks are added', async () => {
      const playlistId = PlayerQueue.createPlaylist('Track Add Callback Test');
      createdPlaylistIds.push(playlistId);

      const changedPlaylistIds: string[] = [];
      const operations: (string | undefined)[] = [];
      const changedPlaylists: Playlist[] = [];

      PlayerQueue.onPlaylistChanged((id, playlist, operation) => {
        changedPlaylistIds.push(id);
        operations.push(operation);
        changedPlaylists.push(playlist);
      });

      await waitForNextTick();
      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      await waitForNextTick();

      expect(changedPlaylistIds).toContain(playlistId);
      expect(operations).toContain('add');
      const relevantPlaylist = changedPlaylists.find(p => p.id === playlistId);
      expect(relevantPlaylist?.tracks.length).toBe(sampleTracks1.length);
    });

    it('should trigger onPlaylistChanged when track is removed', async () => {
      const playlistId = PlayerQueue.createPlaylist('Track Remove Callback Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const changedPlaylistIds: string[] = [];
      const operations: (string | undefined)[] = [];

      PlayerQueue.onPlaylistChanged((id, playlist, operation) => {
        if (id === playlistId && operation === 'remove') {
          changedPlaylistIds.push(id);
          operations.push(operation);
        }
      });

      await waitForNextTick();
      PlayerQueue.removeTrackFromPlaylist(playlistId, '2');

      await waitForNextTick();

      expect(changedPlaylistIds).toContain(playlistId);
      expect(operations).toContain('remove');
    });

    it('should trigger onPlaylistChanged when tracks are reordered', async () => {
      const playlistId = PlayerQueue.createPlaylist('Reorder Callback Test');
      createdPlaylistIds.push(playlistId);

      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const changedPlaylistIds: string[] = [];
      const operations: (string | undefined)[] = [];

      PlayerQueue.onPlaylistChanged((id, playlist, operation) => {
        if (id === playlistId) {
          changedPlaylistIds.push(id);
          operations.push(operation);
        }
      });

      await waitForNextTick();
      PlayerQueue.reorderTrackInPlaylist(playlistId, '3', 0);

      await waitForNextTick();

      expect(changedPlaylistIds).toContain(playlistId);
      expect(operations).toContain('update');
    });

    it('should handle multiple onPlaylistsChanged listeners', async () => {
      const listener1Changes: Playlist[][] = [];
      const listener2Changes: Playlist[][] = [];

      PlayerQueue.onPlaylistsChanged((playlists) => {
        listener1Changes.push(playlists);
      });

      PlayerQueue.onPlaylistsChanged((playlists) => {
        listener2Changes.push(playlists);
      });

      // Wait for listeners to be registered
      await waitForNextTick();

      const playlistId = PlayerQueue.createPlaylist('Multi Listener Test');
      createdPlaylistIds.push(playlistId);

      // Wait for callbacks to trigger
      await waitForNextTick();

      expect(listener1Changes.length).toBeGreaterThan(0);
      expect(listener2Changes.length).toBeGreaterThan(0);
      expect(listener1Changes[listener1Changes.length - 1].some(p => p.id === playlistId)).toBe(true);
      expect(listener2Changes[listener2Changes.length - 1].some(p => p.id === playlistId)).toBe(true);
    });

    it('should handle multiple onPlaylistChanged listeners', async () => {
      const playlistId = PlayerQueue.createPlaylist('Multi Playlist Listener Test');
      createdPlaylistIds.push(playlistId);

      const listener1Ids: string[] = [];
      const listener2Ids: string[] = [];

      PlayerQueue.onPlaylistChanged((id) => {
        listener1Ids.push(id);
      });

      PlayerQueue.onPlaylistChanged((id) => {
        listener2Ids.push(id);
      });

      await waitForNextTick();
      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      await waitForNextTick();

      expect(listener1Ids).toContain(playlistId);
      expect(listener2Ids).toContain(playlistId);
    });

    it('should trigger callbacks for multiple operations in sequence', async () => {
      const playlistId = PlayerQueue.createPlaylist('Sequential Operations Test');
      createdPlaylistIds.push(playlistId);

      const operations: (string | undefined)[] = [];

      PlayerQueue.onPlaylistChanged((id, playlist, operation) => {
        if (id === playlistId) {
          operations.push(operation);
        }
      });

      await waitForNextTick();

      // Perform multiple operations
      PlayerQueue.addTracksToPlaylist(playlistId, [sampleTracks1[0]]);
      await waitForNextTick();

      PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[1]);
      await waitForNextTick();

      PlayerQueue.removeTrackFromPlaylist(playlistId, '1');
      await waitForNextTick();

      PlayerQueue.updatePlaylist(playlistId, 'Updated Name');
      await waitForNextTick();

      // Should have triggered for add, add, remove, update
      expect(operations.filter(op => op === 'add').length).toBeGreaterThanOrEqual(2);
      expect(operations).toContain('remove');
      expect(operations).toContain('update');
    });

    it('should handle callbacks with complex playlist modifications', async () => {
      const playlist1Id = PlayerQueue.createPlaylist('Complex Test 1');
      const playlist2Id = PlayerQueue.createPlaylist('Complex Test 2');
      createdPlaylistIds.push(playlist1Id, playlist2Id);

      const allChanges: Array<{ id: string; operation?: string }> = [];

      PlayerQueue.onPlaylistChanged((id, playlist, operation) => {
        allChanges.push({ id, operation });
      });

      await waitForNextTick();

      // Modify both playlists
      PlayerQueue.addTracksToPlaylist(playlist1Id, sampleTracks1);
      PlayerQueue.addTracksToPlaylist(playlist2Id, sampleTracks2);
      await waitForNextTick();

      PlayerQueue.updatePlaylist(playlist1Id, 'Updated Playlist 1');
      await waitForNextTick();

      PlayerQueue.removeTrackFromPlaylist(playlist2Id, '4');
      await waitForNextTick();

      // Should have changes for both playlists
      expect(allChanges.some(c => c.id === playlist1Id)).toBe(true);
      expect(allChanges.some(c => c.id === playlist2Id)).toBe(true);
      expect(allChanges.filter(c => c.operation === 'add').length).toBeGreaterThanOrEqual(2);
    });

    it('should handle callbacks when playlist is loaded', async () => {
      const playlistId = PlayerQueue.createPlaylist('Load Callback Test');
      createdPlaylistIds.push(playlistId);
      PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const changedIds: string[] = [];

      PlayerQueue.onPlaylistChanged((id) => {
        changedIds.push(id);
      });

      await waitForNextTick();
      PlayerQueue.loadPlaylist(playlistId);

      await waitForNextTick();

      // Loading might trigger a callback depending on implementation
      // At minimum, verify no errors occurred
      expect(PlayerQueue.getCurrentPlaylistId()).toBe(playlistId);
    });
  });
});