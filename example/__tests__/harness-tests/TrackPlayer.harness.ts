import { describe, it, expect, beforeEach, afterEach } from 'react-native-harness';
import { TrackPlayer, PlayerQueue } from 'react-native-nitro-player';
import type { TrackItem } from 'react-native-nitro-player';
import { sampleTracks1, sampleTracks2 } from '../../src/data/sampleTracks';

describe('TrackPlayer - Comprehensive Tests', () => {
    let createdPlaylistIds: string[] = [];
    let playlist1Id: string;
    let playlist2Id: string;
    let playlist3Id: string;

    // Helper to wait for callbacks to trigger and events to propagate
    const waitForNextTick = async () => {
        await new Promise<void>(resolve => setTimeout(resolve, 100));
    };

    // Helper to create a test track
    const createTestTrack = (id: string, title: string): TrackItem => ({
        id,
        title,
        artist: 'Test Artist',
        album: 'Test Album',
        duration: 180.0,
        url: `https://example.com/${id}.mp3`,
        artwork: `https://example.com/${id}.jpg`,
    });

    beforeEach(() => {
        console.log('Setting up TrackPlayer test...');

        // Clean up any existing playlists
        try {
            const existingPlaylists = PlayerQueue.getAllPlaylists();
            existingPlaylists.forEach(playlist => {
                try {
                    PlayerQueue.deletePlaylist(playlist.id);
                } catch (e) {
                    console.warn('Error deleting existing playlist:', e);
                }
            });
        } catch (e) {
            console.warn('Error getting existing playlists:', e);
        }

        createdPlaylistIds = [];

        // Create test playlists
        playlist1Id = PlayerQueue.createPlaylist('Test Playlist 1', 'First test playlist');
        playlist2Id = PlayerQueue.createPlaylist('Test Playlist 2', 'Second test playlist');
        playlist3Id = PlayerQueue.createPlaylist('Test Playlist 3', 'Third test playlist');

        createdPlaylistIds.push(playlist1Id, playlist2Id, playlist3Id);

        // Add tracks to playlists
        PlayerQueue.addTracksToPlaylist(playlist1Id, sampleTracks1);
        PlayerQueue.addTracksToPlaylist(playlist2Id, sampleTracks2);
        PlayerQueue.addTracksToPlaylist(playlist3Id, [
            createTestTrack('p3-1', 'Playlist 3 Track 1'),
            createTestTrack('p3-2', 'Playlist 3 Track 2'),
            createTestTrack('p3-3', 'Playlist 3 Track 3'),
        ]);
    });

    afterEach(() => {
        // Clean up playlists
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
    // TEMPORARY QUEUE MANAGEMENT - playNext (LIFO)
    // ============================================

    describe('playNext (LIFO)', () => {
        it('should add single track to play-next stack', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // Add track from playlist 2 to play next
            await TrackPlayer.playNext('4');

            const queue = await TrackPlayer.getActualQueue();

            // Queue should be: [1 (current), 4 (playNext), 2, 3, ...]
            expect(queue.length).toBeGreaterThan(2);
            expect(queue[0].id).toBe('1'); // Current track
            expect(queue[1].id).toBe('4'); // PlayNext track
            expect(queue[2].id).toBe('2'); // Next original track
        });

        it('should add multiple tracks in LIFO order (last added plays first)', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // Add tracks in order - using tracks from playlist2 and playlist3
            await TrackPlayer.playNext('4'); // From playlist2 - Will play 3rd
            await TrackPlayer.playNext('5'); // From playlist2 - Will play 2nd
            await TrackPlayer.playNext('p3-1'); // From playlist3 - Will play 1st (most recent)

            const queue = await TrackPlayer.getActualQueue();

            // Queue should be: [1 (current), p3-1, 5, 4, 2, 3, ...]
            expect(queue[0].id).toBe('1');
            expect(queue[1].id).toBe('p3-1'); // Last added, plays first
            expect(queue[2].id).toBe('5');
            expect(queue[3].id).toBe('4');
            expect(queue[4].id).toBe('2'); // Original playlist continues
        });

        it('should add playNext tracks from different playlists', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // Add tracks from different playlists
            await TrackPlayer.playNext('4'); // From playlist2
            await TrackPlayer.playNext('p3-1'); // From playlist3
            await TrackPlayer.playNext('5'); // From playlist2

            const queue = await TrackPlayer.getActualQueue();

            // LIFO order: 5, p3-1, 4
            expect(queue[1].id).toBe('5');
            expect(queue[2].id).toBe('p3-1');
            expect(queue[3].id).toBe('4');
        });

        it('should clear playNext stack when loading new playlist', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.playNext('4');
            await TrackPlayer.playNext('5');

            // Load different playlist - should clear playNext
            PlayerQueue.loadPlaylist(playlist2Id);

            const queue = await TrackPlayer.getActualQueue();

            // Should only have playlist2 tracks, no playNext tracks
            expect(queue.every(track => ['4', '5'].includes(track.id))).toBe(true);
        });
    });

    // ============================================
    // TEMPORARY QUEUE MANAGEMENT - addToUpNext (FIFO)
    // ============================================

    describe('addToUpNext (FIFO)', () => {
        it('should add single track to up-next queue', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.addToUpNext('4');

            const queue = await TrackPlayer.getActualQueue();

            // Queue should have track 4 after current track
            expect(queue[0].id).toBe('1');
            expect(queue.some(t => t.id === '4')).toBe(true);
        });

        it('should add multiple tracks in FIFO order (first added plays first)', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // Add tracks in order: song-4, song-5, p3-1
            await TrackPlayer.addToUpNext('4'); // Will play 1st
            await TrackPlayer.addToUpNext('5'); // Will play 2nd
            await TrackPlayer.addToUpNext('p3-1'); // Will play 3rd

            const queue = await TrackPlayer.getActualQueue();

            // Find the upNext tracks in queue
            const track4Index = queue.findIndex(t => t.id === '4');
            const track5Index = queue.findIndex(t => t.id === '5');
            const trackP3Index = queue.findIndex(t => t.id === 'p3-1');

            // FIFO order: 4, 5, p3-1
            expect(track4Index).toBeLessThan(track5Index);
            expect(track5Index).toBeLessThan(trackP3Index);
        });

        it('should add upNext tracks from different playlists', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // Add tracks from different playlists
            await TrackPlayer.addToUpNext('4'); // From playlist2
            await TrackPlayer.addToUpNext('p3-1'); // From playlist3
            await TrackPlayer.addToUpNext('5'); // From playlist2

            const queue = await TrackPlayer.getActualQueue();

            // FIFO order: 4, p3-1, 5
            const track4Index = queue.findIndex(t => t.id === '4');
            const trackP3Index = queue.findIndex(t => t.id === 'p3-1');
            const track5Index = queue.findIndex(t => t.id === '5');

            expect(track4Index).toBeLessThan(trackP3Index);
            expect(trackP3Index).toBeLessThan(track5Index);
        });

        it('should clear upNext queue when loading new playlist', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.addToUpNext('4');
            await TrackPlayer.addToUpNext('5');

            // Load different playlist - should clear upNext
            PlayerQueue.loadPlaylist(playlist2Id);

            const queue = await TrackPlayer.getActualQueue();

            // Should only have playlist2 tracks
            expect(queue.every(track => ['4', '5'].includes(track.id))).toBe(true);
        });
    });

    // // ============================================
    // // COMBINED playNext + upNext
    // // ============================================

    describe('Combined playNext + upNext', () => {
        it('should maintain correct queue order: current → playNext(LIFO) → upNext(FIFO) → remaining', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // Add playNext tracks (LIFO)
            await TrackPlayer.playNext('p3-1'); // Will be 3rd in playNext
            await TrackPlayer.playNext('p3-2'); // Will be 2nd in playNext
            await TrackPlayer.playNext('p3-3'); // Will be 1st in playNext (most recent)

            // Add upNext tracks (FIFO)
            await TrackPlayer.addToUpNext('4'); // Will be 1st in upNext
            await TrackPlayer.addToUpNext('5'); // Will be 2nd in upNext
            await TrackPlayer.addToUpNext('p3-2'); // Will be 3rd in upNext (using p3-2 instead of non-existent 6)

            const queue = await TrackPlayer.getActualQueue();

            // Expected order: [1, p3-3, p3-2, p3-1, 4, 5, p3-2, 2, 3, ...]
            // Note: p3-2 appears twice - once in playNext stack, once in upNext queue
            expect(queue[0].id).toBe('1'); // Current

            // PlayNext stack (LIFO)
            expect(queue[1].id).toBe('p3-3');
            expect(queue[2].id).toBe('p3-2');
            expect(queue[3].id).toBe('p3-1');

            // UpNext queue (FIFO)
            expect(queue[4].id).toBe('4');
            expect(queue[5].id).toBe('5');
            // p3-2 appears again in upNext
            expect(queue[6].id).toBe('p3-2');

            // Original playlist continues
            expect(queue[7].id).toBe('2');
        });

        it('should handle complex cross-playlist scenario', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // Mix playNext and upNext from all 3 playlists
            await TrackPlayer.playNext('4'); // playlist2
            await TrackPlayer.addToUpNext('p3-1'); // playlist3
            await TrackPlayer.playNext('2'); // playlist1
            await TrackPlayer.addToUpNext('5'); // playlist2
            await TrackPlayer.playNext('p3-2'); // playlist3

            const queue = await TrackPlayer.getActualQueue();

            // PlayNext (LIFO): p3-2, 2, 4
            // UpNext (FIFO): p3-1, 5
            expect(queue[0].id).toBe('1');
            expect(queue[1].id).toBe('p3-2'); // Last playNext
            expect(queue[2].id).toBe('2');
            expect(queue[3].id).toBe('4'); // First playNext
            expect(queue[4].id).toBe('p3-1'); // First upNext
            expect(queue[5].id).toBe('5'); // Second upNext
        });
    });

    // // ============================================
    // // EVENT LISTENERS
    // // ============================================

    describe('Event Listeners', () => {
        it('should trigger onChangeTrack when skipping to next', async () => {
            const changedTracks: TrackItem[] = [];
            const reasons: (string | undefined)[] = [];

            TrackPlayer.onChangeTrack((track, reason) => {
                changedTracks.push(track);
                reasons.push(reason);
            });

            PlayerQueue.loadPlaylist(playlist1Id);
            await waitForNextTick();

            await TrackPlayer.playSong('1', playlist1Id);
            await waitForNextTick();

            TrackPlayer.skipToNext();
            await waitForNextTick();

            expect(changedTracks.length).toBeGreaterThan(0);
            expect(changedTracks.some(t => t.id === '2')).toBe(true);
        });

        it('should trigger onChangeTrack when playing a song', async () => {
            const changedTracks: TrackItem[] = [];

            TrackPlayer.onChangeTrack((track) => {
                changedTracks.push(track);
            });


            await TrackPlayer.playSong('1', playlist1Id);
            await waitForNextTick();

            expect(changedTracks.some(t => t.id === '1')).toBe(true);
        });

        it('should trigger onPlaybackStateChange on play', async () => {
            const states: string[] = [];

            TrackPlayer.onPlaybackStateChange((state) => {
                states.push(state);
            });

            PlayerQueue.loadPlaylist(playlist1Id);
            TrackPlayer.pause()
            TrackPlayer.play();
            await waitForNextTick();

            expect(states).toContain('playing');
        });

        it('should trigger onPlaybackStateChange on pause', async () => {
            const states: string[] = [];

            TrackPlayer.onPlaybackStateChange((state) => {
                states.push(state);
            });

            PlayerQueue.loadPlaylist(playlist1Id);
            TrackPlayer.play();
            await waitForNextTick();

            TrackPlayer.pause();
            await waitForNextTick();

            expect(states).toContain('paused');
        });

        it('should trigger onSeek when seeking', async () => {
            const seekPositions: number[] = [];

            TrackPlayer.onSeek((position) => {
                seekPositions.push(position);
            });

            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);
            await waitForNextTick();

            TrackPlayer.seek(30);
            await waitForNextTick();

            expect(seekPositions).toContain(30);
        });

        it('should handle multiple onChangeTrack listeners', async () => {
            const listener1Tracks: TrackItem[] = [];
            const listener2Tracks: TrackItem[] = [];


            TrackPlayer.onChangeTrack((track) => {
                listener1Tracks.push(track);
            });

            TrackPlayer.onChangeTrack((track) => {
                listener2Tracks.push(track);
            });
            await TrackPlayer.playSong('1', playlist1Id);

            await waitForNextTick();
            expect(listener1Tracks.length).toBeGreaterThan(0);
            expect(listener2Tracks.length).toBeGreaterThan(0);
            expect(listener1Tracks[listener1Tracks.length - 1].id).toBe('1');
            expect(listener2Tracks[listener2Tracks.length - 1].id).toBe('1');
        });

        // it('should handle multiple onPlaybackStateChange listeners', async () => {
        //     const listener1States: string[] = [];
        //     const listener2States: string[] = [];

        //     TrackPlayer.onPlaybackStateChange((state) => {
        //         listener1States.push(state);
        //     });

        //     TrackPlayer.onPlaybackStateChange((state) => {
        //         listener2States.push(state);
        //     });

        //     await waitForNextTick();

        //     PlayerQueue.loadPlaylist(playlist1Id);
        //     TrackPlayer.play();
        //     await waitForNextTick();
        //     TrackPlayer.pause();
        //     await waitForNextTick();

        //     expect(listener1States.length).toBeGreaterThan(0);
        //     expect(listener2States.length).toBeGreaterThan(0);
        // });
    });

    // // ============================================
    // // PLAYBACK CONTROLS
    // // ============================================

    describe('Playback Controls', () => {
        it('should play and pause correctly', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);

            TrackPlayer.play();
            let state = await TrackPlayer.getState();
            expect(state.currentState).toBe('playing');

            TrackPlayer.pause();
            state = await TrackPlayer.getState();
            expect(state.currentState).toBe('paused');
        });

        it('should skip to next track', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            TrackPlayer.skipToNext();

            const state = await TrackPlayer.getState();
            expect(state.currentTrack?.id).toBe('2');
        });

        it('should skip to previous track', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('2', playlist1Id);

            TrackPlayer.skipToPrevious();

            const state = await TrackPlayer.getState();
            expect(state.currentTrack?.id).toBe('1');
        });

        it('should seek to position', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            TrackPlayer.seek(30);

            // Position should be around 30 seconds
            const state = await TrackPlayer.getState();
            expect(state.currentPosition).toBeGreaterThanOrEqual(29);
            expect(state.currentPosition).toBeLessThanOrEqual(31);
        });

        it('should set repeat mode to off', async () => {
            const success = TrackPlayer.setRepeatMode('off');
            expect(success).toBe(true);
        });

        it('should set repeat mode to Playlist', async () => {
            const success = TrackPlayer.setRepeatMode('Playlist');
            expect(success).toBe(true);
        });

        it('should set repeat mode to track', async () => {
            const success = TrackPlayer.setRepeatMode('track');
            expect(success).toBe(true);
        });

        it('should set volume to 50%', async () => {
            const success = TrackPlayer.setVolume(50);
            expect(success).toBe(true);
        });

        it('should set volume to 0 (mute)', async () => {
            const success = TrackPlayer.setVolume(0);
            expect(success).toBe(true);
        });

        it('should set volume to 100 (max)', async () => {
            const success = TrackPlayer.setVolume(100);
            expect(success).toBe(true);
        });

        it('should clamp volume below 0', async () => {
            const success = TrackPlayer.setVolume(-10);
            expect(success).toBe(true);
            // Volume should be clamped to 0
        });

        it('should clamp volume above 100', async () => {
            const success = TrackPlayer.setVolume(150);
            expect(success).toBe(true);
            // Volume should be clamped to 100
        });
    });

    // // ============================================
    // // STATE MANAGEMENT
    // // ============================================

    describe('State Management', () => {
        it('should return correct state after loading playlist', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);

            const state = await TrackPlayer.getState();
            expect(state.currentPlaylistId).toBe(playlist1Id);
        });

        it('should return correct state after playing song', async () => {
            await TrackPlayer.playSong('1', playlist1Id);

            const state = await TrackPlayer.getState();
            expect(state.currentTrack?.id).toBe('1');
            expect(state.currentPlaylistId).toBe(playlist1Id);
        });

        it('should return correct actual queue', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);

            const queue = await TrackPlayer.getActualQueue();
            expect(queue.length).toBe(sampleTracks1.length);
            expect(queue[0].id).toBe('1');
        });

        it('should update state after skip', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            TrackPlayer.skipToNext();

            const state = await TrackPlayer.getState();
            expect(state.currentTrack?.id).toBe('2');
            expect(state.currentIndex).toBe(1);
        });

        it('should maintain playlist ID across track changes', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            TrackPlayer.skipToNext();
            TrackPlayer.skipToNext();

            const state = await TrackPlayer.getState();
            expect(state.currentPlaylistId).toBe(playlist1Id);
        });
    });

    // // ============================================
    // // EDGE CASES
    // // ============================================

    describe('Edge Cases', () => {
        it('should handle playNext with non-existent track ID', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // This should not crash
            await expect(TrackPlayer.playNext('non-existent-id')).resolves.not.toThrow();
        });

        it('should handle addToUpNext with non-existent track ID', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // This should not crash
            await expect(TrackPlayer.addToUpNext('non-existent-id')).resolves.not.toThrow();
        });

        it('should handle seek beyond track duration', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // Seek to 1000 seconds (beyond duration)
            expect(() => {
                TrackPlayer.seek(1000);
            }).not.toThrow();
        });

        it('should handle skip at last track with repeat off', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            TrackPlayer.setRepeatMode('off');

            // Play last track
            await TrackPlayer.playSong('3', playlist1Id);

            // Skip to next should not crash
            expect(() => {
                TrackPlayer.skipToNext();
            }).not.toThrow();
        });

        it('should handle skip at first track going previous', async () => {
            PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // Skip to previous should not crash
            expect(() => {
                TrackPlayer.skipToPrevious();
            }).not.toThrow();
        });
    });
});
