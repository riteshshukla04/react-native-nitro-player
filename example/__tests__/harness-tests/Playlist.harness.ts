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
  beforeAll(async () => {
    console.log('Clearing all existing playlists before tests...');
    const existingPlaylists = PlayerQueue.getAllPlaylists();
    for (const playlist of existingPlaylists) {
      try {
        await PlayerQueue.deletePlaylist(playlist.id);
      } catch (e) {
        console.warn('Error deleting existing playlist:', e);
      }
    }
  });

  beforeEach(() => {
    console.log('Setting up test...');
    createdPlaylistIds = [];
  });

  afterEach(async () => {
    console.log('Cleaning up test...');

    for (const id of createdPlaylistIds) {
      try {
        await PlayerQueue.deletePlaylist(id);
      } catch (e) {
        console.warn('Error deleting playlist:', e);
      }
    }
    createdPlaylistIds = [];
  });

  // ============================================
  // PLAYLIST CRUD OPERATIONS
  // ============================================

  describe('Playlist Creation', () => {
    it('should create playlist with all fields', async () => {
      const playlistId = await PlayerQueue.createPlaylist(
        'My Playlist',
        'Playlist description',
        'https://example.com/playlist-artwork.jpg'
      );
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const actualPlaylist = [{
        artwork: 'https://example.com/playlist-artwork.jpg',
        description: 'Playlist description',
        id: playlistId,
        name: 'My Playlist',
        tracks: sampleTracks1,
      }];

      expect(PlayerQueue.getAllPlaylists()).toStrictEqual(actualPlaylist);
    });

    it('should create playlist with minimal fields', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Minimal Playlist');
      createdPlaylistIds.push(playlistId);

      const playlist = PlayerQueue.getPlaylist(playlistId);

      expect(playlist).not.toBeNull();
      expect(playlist?.name).toBe('Minimal Playlist');
      expect(playlist?.description).toBeUndefined();
      expect(playlist?.artwork).toBeUndefined();
      expect(playlist?.tracks).toStrictEqual([]);
    });

    it('should create multiple playlists independently', async () => {
      const playlist1Id = await PlayerQueue.createPlaylist('Playlist 1', 'First playlist');
      const playlist2Id = await PlayerQueue.createPlaylist('Playlist 2', 'Second playlist');
      const playlist3Id = await PlayerQueue.createPlaylist('Playlist 3', 'Third playlist');

      createdPlaylistIds.push(playlist1Id, playlist2Id, playlist3Id);

      await PlayerQueue.addTracksToPlaylist(playlist1Id, [sampleTracks1[0]]);
      await PlayerQueue.addTracksToPlaylist(playlist2Id, [sampleTracks1[1]]);
      await PlayerQueue.addTracksToPlaylist(playlist3Id, [sampleTracks1[2]]);

      const allPlaylists = PlayerQueue.getAllPlaylists();

      expect(allPlaylists.length).toBe(3);
      expect(allPlaylists[0].tracks.length).toBe(1);
      expect(allPlaylists[1].tracks.length).toBe(1);
      expect(allPlaylists[2].tracks.length).toBe(1);
    });
  });

  describe('Playlist Retrieval', () => {
    it('should get playlist by id', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Test Playlist', 'Test description');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const playlist = PlayerQueue.getPlaylist(playlistId);

      expect(playlist).not.toBeNull();
      expect(playlist?.id).toBe(playlistId);
      expect(playlist?.name).toBe('Test Playlist');
      expect(playlist?.description).toBe('Test description');
      expect(playlist?.tracks).toStrictEqual(sampleTracks1);
    });

    it('should return null for non-existent playlist', async () => {
      const playlist = PlayerQueue.getPlaylist('non-existent-id');
      expect(playlist).toBeNull();
    });

    it('should get all playlists', async () => {
      const id1 = await PlayerQueue.createPlaylist('Playlist A');
      const id2 = await PlayerQueue.createPlaylist('Playlist B');
      createdPlaylistIds.push(id1, id2);

      const allPlaylists = PlayerQueue.getAllPlaylists();

      expect(allPlaylists.length).toBe(2);
      expect(allPlaylists.map(p => p.name)).toContain('Playlist A');
      expect(allPlaylists.map(p => p.name)).toContain('Playlist B');
    });
  });

  describe('Playlist Update', () => {
    it('should update playlist name', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Original Name', 'Description');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.updatePlaylist(playlistId, 'Updated Name');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.name).toBe('Updated Name');
      expect(playlist?.description).toBe('Description');
    });

    it('should update playlist description', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Name', 'Original Description');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.updatePlaylist(playlistId, undefined, 'Updated Description');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.name).toBe('Name');
      expect(playlist?.description).toBe('Updated Description');
    });

    it('should update playlist artwork', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Name', 'Description', 'original.jpg');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.updatePlaylist(playlistId, undefined, undefined, 'updated.jpg');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.artwork).toBe('updated.jpg');
    });

    it('should update all playlist fields at once', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Old Name', 'Old Desc', 'old.jpg');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.updatePlaylist(playlistId, 'New Name', 'New Desc', 'new.jpg');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.name).toBe('New Name');
      expect(playlist?.description).toBe('New Desc');
      expect(playlist?.artwork).toBe('new.jpg');
    });
  });

  describe('Playlist Deletion', () => {
    it('should delete playlist', async () => {
      const playlistId = await PlayerQueue.createPlaylist('To Delete');
      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      await PlayerQueue.deletePlaylist(playlistId);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist).toBeNull();
    });

    it('should remove deleted playlist from all playlists', async () => {
      const id1 = await PlayerQueue.createPlaylist('Keep This');
      const id2 = await PlayerQueue.createPlaylist('Delete This');
      createdPlaylistIds.push(id1); // Only track the one we keep

      await PlayerQueue.deletePlaylist(id2);

      const allPlaylists = PlayerQueue.getAllPlaylists();
      expect(allPlaylists.length).toBe(1);
      expect(allPlaylists[0].id).toBe(id1);
    });
  });

  // ============================================
  // TRACK MANAGEMENT
  // ============================================

  describe('Adding Tracks', () => {
    it('should add single track to playlist', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Single Track Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(1);
      expect(playlist?.tracks[0]).toStrictEqual(sampleTracks1[0]);
    });

    it('should add multiple tracks to playlist', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Multiple Tracks Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(sampleTracks1.length);
      expect(playlist?.tracks).toStrictEqual(sampleTracks1);
    });

    it('should add track at specific index', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Index Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, [sampleTracks1[0], sampleTracks1[2]]);
      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[1], 1);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(3);
      expect(playlist?.tracks[0].id).toBe('1');
      expect(playlist?.tracks[1].id).toBe('2');
      expect(playlist?.tracks[2].id).toBe('3');
    });

    it('should add tracks at specific index', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Batch Index Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);
      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[2]);
      await PlayerQueue.addTracksToPlaylist(playlistId, [sampleTracks2[0], sampleTracks2[1]], 1);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(4);
      expect(playlist?.tracks[0].id).toBe('1');
      expect(playlist?.tracks[1].id).toBe('4');
      expect(playlist?.tracks[2].id).toBe('5');
      expect(playlist?.tracks[3].id).toBe('3');
    });

    it('should handle adding duplicate tracks', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Duplicate Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);
      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(2);
      expect(playlist?.tracks[0]).toStrictEqual(sampleTracks1[0]);
      expect(playlist?.tracks[1]).toStrictEqual(sampleTracks1[0]);
    });
  });

  describe('Removing Tracks', () => {
    it('should remove track from playlist', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Remove Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
      await PlayerQueue.removeTrackFromPlaylist(playlistId, '2');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(2);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['1', '3']);
    });

    it('should remove all instances of duplicate tracks', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Remove Duplicates Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);
      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[1]);
      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);

      await PlayerQueue.removeTrackFromPlaylist(playlistId, '1');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(1);
      expect(playlist?.tracks[0].id).toBe('2');
    });

    it('should handle removing non-existent track', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Remove Non-existent Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      // This should not throw an error
      await PlayerQueue.removeTrackFromPlaylist(playlistId, 'non-existent-id');

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(3);
    });
  });

  describe('Reordering Tracks', () => {
    it('should reorder track to beginning', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Reorder Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
      await PlayerQueue.reorderTrackInPlaylist(playlistId, '3', 0);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['3', '1', '2']);
    });

    it('should reorder track to end', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Reorder End Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
      await PlayerQueue.reorderTrackInPlaylist(playlistId, '1', 2);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['2', '3', '1']);
    });

    it('should reorder track to middle', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Reorder Middle Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
      await PlayerQueue.reorderTrackInPlaylist(playlistId, '1', 1);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['2', '1', '3']);
    });

    it('should handle complex reordering sequence', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Complex Reorder Test');
      createdPlaylistIds.push(playlistId);

      const tracks = [
        createTestTrack('A', 'Track A'),
        createTestTrack('B', 'Track B'),
        createTestTrack('C', 'Track C'),
        createTestTrack('D', 'Track D'),
        createTestTrack('E', 'Track E'),
      ];

      await PlayerQueue.addTracksToPlaylist(playlistId, tracks);

      // Move E to position 1
      await PlayerQueue.reorderTrackInPlaylist(playlistId, 'E', 1);
      let playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['A', 'E', 'B', 'C', 'D']);

      // Move A to position 3
      await PlayerQueue.reorderTrackInPlaylist(playlistId, 'A', 3);
      playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['E', 'B', 'C', 'A', 'D']);

      // Move D to position 0
      await PlayerQueue.reorderTrackInPlaylist(playlistId, 'D', 0);
      playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.map(t => t.id)).toStrictEqual(['D', 'E', 'B', 'C', 'A']);
    });
  });

  // ============================================
  // PLAYLIST LOADING
  // ============================================

  describe('Playlist Loading', () => {
    it('should load playlist', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Load Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
      await PlayerQueue.loadPlaylist(playlistId);

      const currentPlaylistId = PlayerQueue.getCurrentPlaylistId();
      expect(currentPlaylistId).toBe(playlistId);
    });

    it('should switch between playlists', async () => {
      const playlist1Id = await PlayerQueue.createPlaylist('Playlist 1');
      const playlist2Id = await PlayerQueue.createPlaylist('Playlist 2');
      createdPlaylistIds.push(playlist1Id, playlist2Id);

      await PlayerQueue.addTracksToPlaylist(playlist1Id, sampleTracks1);
      await PlayerQueue.addTracksToPlaylist(playlist2Id, sampleTracks2);

      await PlayerQueue.loadPlaylist(playlist1Id);
      expect(PlayerQueue.getCurrentPlaylistId()).toBe(playlist1Id);

      await PlayerQueue.loadPlaylist(playlist2Id);
      expect(PlayerQueue.getCurrentPlaylistId()).toBe(playlist2Id);
    });
  });

  // ============================================
  // EDGE CASES AND COMPLEX SCENARIOS
  // ============================================

  describe('Edge Cases', () => {
    it('should handle empty playlist operations', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Empty Playlist');
      createdPlaylistIds.push(playlistId);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks).toStrictEqual([]);

      // Try to remove from empty playlist
      await PlayerQueue.removeTrackFromPlaylist(playlistId, 'non-existent');
      expect(playlist?.tracks).toStrictEqual([]);
    });

    it('should handle large playlist with many tracks', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Large Playlist');
      createdPlaylistIds.push(playlistId);

      const manyTracks: TrackItem[] = [];
      for (let i = 0; i < 100; i++) {
        manyTracks.push(createTestTrack(`track-${i}`, `Track ${i}`));
      }

      await PlayerQueue.addTracksToPlaylist(playlistId, manyTracks);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(100);
    });

    it('should maintain playlist integrity after multiple operations', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Integrity Test');
      createdPlaylistIds.push(playlistId);

      // Add tracks
      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      // Update playlist
      await PlayerQueue.updatePlaylist(playlistId, 'Updated Name', 'Updated Description');

      // Add more tracks
      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks2);

      // Remove a track
      await PlayerQueue.removeTrackFromPlaylist(playlistId, '2');

      // Reorder tracks
      await PlayerQueue.reorderTrackInPlaylist(playlistId, '4', 0);

      const playlist = PlayerQueue.getPlaylist(playlistId);

      expect(playlist?.name).toBe('Updated Name');
      expect(playlist?.description).toBe('Updated Description');
      expect(playlist?.tracks.length).toBe(4);
      expect(playlist?.tracks[0].id).toBe('4');
    });

    it('should handle rapid successive operations', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Rapid Operations Test');
      createdPlaylistIds.push(playlistId);

      // Perform multiple operations in quick succession
      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[0]);
      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[1]);
      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[2]);
      await PlayerQueue.removeTrackFromPlaylist(playlistId, '2');
      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks2[0]);
      await PlayerQueue.reorderTrackInPlaylist(playlistId, '4', 0);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks.length).toBe(3);
      expect(playlist?.tracks[0].id).toBe('4');
    });

    it('should handle special characters in playlist metadata', async () => {
      const specialName = "Test's \"Playlist\" with <special> & chars!";
      const specialDesc = "Description with émojis 🎵🎶 and symbols @#$%";

      const playlistId = await PlayerQueue.createPlaylist(specialName, specialDesc);
      createdPlaylistIds.push(playlistId);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.name).toBe(specialName);
      expect(playlist?.description).toBe(specialDesc);
    });

    it('should handle playlist with tracks having null/undefined optional fields', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Null Fields Test');
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

      await PlayerQueue.addTrackToPlaylist(playlistId, trackWithNulls);

      const playlist = PlayerQueue.getPlaylist(playlistId);
      expect(playlist?.tracks[0].artwork).toBeNull();
    });
  });

  describe('Complex Integration Scenarios', () => {
    it('should handle creating, modifying, and deleting multiple playlists', async () => {
      // Create multiple playlists
      const ids = [
        await PlayerQueue.createPlaylist('Rock Classics'),
        await PlayerQueue.createPlaylist('Jazz Standards'),
        await PlayerQueue.createPlaylist('Electronic Beats'),
      ];
      createdPlaylistIds.push(...ids);

      // Add different tracks to each
      await PlayerQueue.addTracksToPlaylist(ids[0], [sampleTracks1[0]]);
      await PlayerQueue.addTracksToPlaylist(ids[1], [sampleTracks1[1]]);
      await PlayerQueue.addTracksToPlaylist(ids[2], [sampleTracks1[2]]);

      // Update one
      await PlayerQueue.updatePlaylist(ids[1], 'Modern Jazz');

      // Delete one
      await PlayerQueue.deletePlaylist(ids[2]);
      createdPlaylistIds = createdPlaylistIds.filter(id => id !== ids[2]);

      const allPlaylists = PlayerQueue.getAllPlaylists();
      expect(allPlaylists.length).toBe(2);
      expect(allPlaylists.find(p => p.name === 'Modern Jazz')).toBeDefined();
      expect(allPlaylists.find(p => p.name === 'Electronic Beats')).toBeUndefined();
    });

    it('should handle moving tracks between playlists', async () => {
      const playlist1Id = await PlayerQueue.createPlaylist('Source Playlist');
      const playlist2Id = await PlayerQueue.createPlaylist('Destination Playlist');
      createdPlaylistIds.push(playlist1Id, playlist2Id);

      await PlayerQueue.addTracksToPlaylist(playlist1Id, sampleTracks1);

      // "Move" a track by adding to second playlist and removing from first
      const trackToMove = sampleTracks1[1];
      await PlayerQueue.addTrackToPlaylist(playlist2Id, trackToMove);
      await PlayerQueue.removeTrackFromPlaylist(playlist1Id, trackToMove.id);

      const playlist1 = PlayerQueue.getPlaylist(playlist1Id);
      const playlist2 = PlayerQueue.getPlaylist(playlist2Id);

      expect(playlist1?.tracks.length).toBe(2);
      expect(playlist2?.tracks.length).toBe(1);
      expect(playlist2?.tracks[0].id).toBe(trackToMove.id);
    });

    it('should handle playlist with mixed track sources', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Mixed Sources');
      createdPlaylistIds.push(playlistId);

      // Add tracks from different sample sets
      await PlayerQueue.addTracksToPlaylist(playlistId, [sampleTracks1[0], sampleTracks1[1]]);
      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks2);
      await PlayerQueue.addTrackToPlaylist(playlistId, createTestTrack('custom', 'Custom Track'));

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

      const playlistId = await PlayerQueue.createPlaylist('Callback Test', 'Test Description');
      createdPlaylistIds.push(playlistId);

      // Wait for callback to trigger
      await waitForNextTick();

      expect(operations).toContain('add');
      expect(changedPlaylists.length).toBeGreaterThan(0);
      expect(changedPlaylists[changedPlaylists.length - 1].some(p => p.id === playlistId)).toBe(true);
    });

    it('should trigger onPlaylistsChanged when playlist is deleted', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Delete Callback Test');
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
      await PlayerQueue.deletePlaylist(playlistId);
      createdPlaylistIds = createdPlaylistIds.filter(id => id !== playlistId);

      await waitForNextTick();

      expect(operations).toContain('remove');
      expect(deletedPlaylistId).toBe(playlistId);
    });

    it('should trigger onPlaylistsChanged when playlist is updated', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Update Callback Test', 'Original');
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
      await PlayerQueue.updatePlaylist(playlistId, 'Updated Name', 'Updated Description');

      await waitForNextTick();

      expect(operations).toContain('update');
      expect(updatedPlaylists.length).toBeGreaterThan(0);
      const updatedPlaylist = updatedPlaylists[0].find(p => p.id === playlistId);
      expect(updatedPlaylist?.name).toBe('Updated Name');
    });

    it('should trigger onPlaylistChanged when tracks are added', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Track Add Callback Test');
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
      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      await waitForNextTick();

      expect(changedPlaylistIds).toContain(playlistId);
      expect(operations).toContain('add');
      const relevantPlaylist = changedPlaylists.find(p => p.id === playlistId);
      expect(relevantPlaylist?.tracks.length).toBe(sampleTracks1.length);
    });

    it('should trigger onPlaylistChanged when track is removed', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Track Remove Callback Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const changedPlaylistIds: string[] = [];
      const operations: (string | undefined)[] = [];

      PlayerQueue.onPlaylistChanged((id, playlist, operation) => {
        if (id === playlistId && operation === 'remove') {
          changedPlaylistIds.push(id);
          operations.push(operation);
        }
      });

      await waitForNextTick();
      await PlayerQueue.removeTrackFromPlaylist(playlistId, '2');

      await waitForNextTick();

      expect(changedPlaylistIds).toContain(playlistId);
      expect(operations).toContain('remove');
    });

    it('should trigger onPlaylistChanged when tracks are reordered', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Reorder Callback Test');
      createdPlaylistIds.push(playlistId);

      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const changedPlaylistIds: string[] = [];
      const operations: (string | undefined)[] = [];

      PlayerQueue.onPlaylistChanged((id, playlist, operation) => {
        if (id === playlistId) {
          changedPlaylistIds.push(id);
          operations.push(operation);
        }
      });

      await waitForNextTick();
      await PlayerQueue.reorderTrackInPlaylist(playlistId, '3', 0);

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

      const playlistId = await PlayerQueue.createPlaylist('Multi Listener Test');
      createdPlaylistIds.push(playlistId);

      // Wait for callbacks to trigger
      await waitForNextTick();

      expect(listener1Changes.length).toBeGreaterThan(0);
      expect(listener2Changes.length).toBeGreaterThan(0);
      expect(listener1Changes[listener1Changes.length - 1].some(p => p.id === playlistId)).toBe(true);
      expect(listener2Changes[listener2Changes.length - 1].some(p => p.id === playlistId)).toBe(true);
    });

    it('should handle multiple onPlaylistChanged listeners', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Multi Playlist Listener Test');
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
      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      await waitForNextTick();

      expect(listener1Ids).toContain(playlistId);
      expect(listener2Ids).toContain(playlistId);
    });

    it('should trigger callbacks for multiple operations in sequence', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Sequential Operations Test');
      createdPlaylistIds.push(playlistId);

      const operations: (string | undefined)[] = [];

      PlayerQueue.onPlaylistChanged((id, playlist, operation) => {
        if (id === playlistId) {
          operations.push(operation);
        }
      });

      await waitForNextTick();

      // Perform multiple operations
      await PlayerQueue.addTracksToPlaylist(playlistId, [sampleTracks1[0]]);
      await waitForNextTick();

      await PlayerQueue.addTrackToPlaylist(playlistId, sampleTracks1[1]);
      await waitForNextTick();

      await PlayerQueue.removeTrackFromPlaylist(playlistId, '1');
      await waitForNextTick();

      await PlayerQueue.updatePlaylist(playlistId, 'Updated Name');
      await waitForNextTick();

      // Should have triggered for add, add, remove, update
      expect(operations.filter(op => op === 'add').length).toBeGreaterThanOrEqual(2);
      expect(operations).toContain('remove');
      expect(operations).toContain('update');
    });

    it('should handle callbacks with complex playlist modifications', async () => {
      const playlist1Id = await PlayerQueue.createPlaylist('Complex Test 1');
      const playlist2Id = await PlayerQueue.createPlaylist('Complex Test 2');
      createdPlaylistIds.push(playlist1Id, playlist2Id);

      const allChanges: Array<{ id: string; operation?: string }> = [];

      PlayerQueue.onPlaylistChanged((id, playlist, operation) => {
        allChanges.push({ id, operation });
      });

      await waitForNextTick();

      // Modify both playlists
      await PlayerQueue.addTracksToPlaylist(playlist1Id, sampleTracks1);
      await PlayerQueue.addTracksToPlaylist(playlist2Id, sampleTracks2);
      await waitForNextTick();

      await PlayerQueue.updatePlaylist(playlist1Id, 'Updated Playlist 1');
      await waitForNextTick();

      await PlayerQueue.removeTrackFromPlaylist(playlist2Id, '4');
      await waitForNextTick();

      // Should have changes for both playlists
      expect(allChanges.some(c => c.id === playlist1Id)).toBe(true);
      expect(allChanges.some(c => c.id === playlist2Id)).toBe(true);
      expect(allChanges.filter(c => c.operation === 'add').length).toBeGreaterThanOrEqual(2);
    });

    it('should handle callbacks when playlist is loaded', async () => {
      const playlistId = await PlayerQueue.createPlaylist('Load Callback Test');
      createdPlaylistIds.push(playlistId);
      await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

      const changedIds: string[] = [];

      PlayerQueue.onPlaylistChanged((id) => {
        changedIds.push(id);
      });

      await waitForNextTick();
      await PlayerQueue.loadPlaylist(playlistId);

      await waitForNextTick();

      // Loading might trigger a callback depending on implementation
      // At minimum, verify no errors occurred
      expect(PlayerQueue.getCurrentPlaylistId()).toBe(playlistId);
    });
  });
});