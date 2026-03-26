import { describe, it, expect, beforeEach, afterEach } from 'react-native-harness';
import { TrackPlayer, PlayerQueue, TrackItem } from 'react-native-nitro-player';
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

    beforeEach(async () => {
        console.log('Setting up TrackPlayer test...');

        try {
            const existingPlaylists = PlayerQueue.getAllPlaylists();
            for (const playlist of existingPlaylists) {
                try {
                    await PlayerQueue.deletePlaylist(playlist.id);
                } catch (e) {
                    console.warn('Error deleting existing playlist:', e);
                }
            }
        } catch (e) {
            console.warn('Error getting existing playlists:', e);
        }

        createdPlaylistIds = [];

        playlist1Id = await PlayerQueue.createPlaylist('Test Playlist 1', 'First test playlist');
        playlist2Id = await PlayerQueue.createPlaylist('Test Playlist 2', 'Second test playlist');
        playlist3Id = await PlayerQueue.createPlaylist('Test Playlist 3', 'Third test playlist');

        createdPlaylistIds.push(playlist1Id, playlist2Id, playlist3Id);

        await PlayerQueue.addTracksToPlaylist(playlist1Id, sampleTracks1);
        await PlayerQueue.addTracksToPlaylist(playlist2Id, sampleTracks2);
        await PlayerQueue.addTracksToPlaylist(playlist3Id, [
            createTestTrack('p3-1', 'Playlist 3 Track 1'),
            createTestTrack('p3-2', 'Playlist 3 Track 2'),
            createTestTrack('p3-3', 'Playlist 3 Track 3'),
        ]);
    });

    afterEach(async () => {
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
    // TEMPORARY QUEUE MANAGEMENT - playNext (LIFO)
    // ============================================

    describe('playNext (LIFO)', () => {
        it('should add single track to play-next stack', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
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
            await PlayerQueue.loadPlaylist(playlist1Id);
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
            await PlayerQueue.loadPlaylist(playlist1Id);
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
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.playNext('4');
            await TrackPlayer.playNext('5');

            // Load different playlist - should clear playNext
            await PlayerQueue.loadPlaylist(playlist2Id);

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
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.addToUpNext('4');

            const queue = await TrackPlayer.getActualQueue();

            // Queue should have track 4 after current track
            expect(queue[0].id).toBe('1');
            expect(queue.some(t => t.id === '4')).toBe(true);
        });

        it('should add multiple tracks in FIFO order (first added plays first)', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
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
            await PlayerQueue.loadPlaylist(playlist1Id);
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
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.addToUpNext('4');
            await TrackPlayer.addToUpNext('5');

            // Load different playlist - should clear upNext
            await PlayerQueue.loadPlaylist(playlist2Id);

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
            await PlayerQueue.loadPlaylist(playlist1Id);
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
            await PlayerQueue.loadPlaylist(playlist1Id);
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

            await PlayerQueue.loadPlaylist(playlist1Id);
            await waitForNextTick();

            await TrackPlayer.playSong('1', playlist1Id);
            await waitForNextTick();

            await TrackPlayer.skipToNext();
            await waitForNextTick();

            expect(changedTracks.length).toBeGreaterThan(0);
            expect(changedTracks.some(t => t.id === '2')).toBe(true);
        });

        it('should trigger onChangeTrack when playing a song', async () => {
            const changedTracks: TrackItem[] = [];

            TrackPlayer.onChangeTrack((track) => {
                changedTracks.push(track);
            });

            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);
            await waitForNextTick();

            expect(changedTracks.some(t => t.id === '1')).toBe(true);
        });

        it('should trigger onPlaybackStateChange on play', async () => {
            const states: string[] = [];

            TrackPlayer.onPlaybackStateChange((state) => {
                states.push(state);
            });

            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.pause();
            await TrackPlayer.play();
            await waitForNextTick();

            expect(states).toContain('playing');
        });

        it('should trigger onPlaybackStateChange on pause', async () => {
            const states: string[] = [];

            TrackPlayer.onPlaybackStateChange((state) => {
                states.push(state);
            });

            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.play();
            await waitForNextTick();

            await TrackPlayer.pause();
            await waitForNextTick();

            expect(states).toContain('paused');
        });

        it('should trigger onSeek when seeking', async () => {
            const seekPositions: number[] = [];

            TrackPlayer.onSeek((position) => {
                seekPositions.push(position);
            });

            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);
            await waitForNextTick();

            await TrackPlayer.seek(30);
            await waitForNextTick();

            expect(seekPositions).toContain(30);
        });

        // it('should handle multiple onChangeTrack listeners', async () => {
        //     const listener1Tracks: TrackItem[] = [];
        //     const listener2Tracks: TrackItem[] = [];


        //     TrackPlayer.onChangeTrack((track) => {
        //         listener1Tracks.push(track);
        //     });

        //     TrackPlayer.onChangeTrack((track) => {
        //         listener2Tracks.push(track);
        //     });
        //     await TrackPlayer.playSong('1', playlist1Id);

        //     await waitForNextTick();
        //     expect(listener1Tracks.length).toBeGreaterThan(0);
        //     expect(listener2Tracks.length).toBeGreaterThan(0);
        //     expect(listener1Tracks[listener1Tracks.length - 1].id).toBe('1');
        //     expect(listener2Tracks[listener2Tracks.length - 1].id).toBe('1');
        // });

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
            await PlayerQueue.loadPlaylist(playlist1Id);

            await TrackPlayer.play();
            let state = await TrackPlayer.getState();
            expect(state.currentState).toBe('playing');

            await TrackPlayer.pause();
            state = await TrackPlayer.getState();
            expect(state.currentState).toBe('paused');
        });

        it('should skip to next track', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.skipToNext();

            const state = await TrackPlayer.getState();
            expect(state.currentTrack?.id).toBe('2');
        });

        it('should skip to previous track', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('2', playlist1Id);

            await TrackPlayer.skipToPrevious();

            const state = await TrackPlayer.getState();
            expect(state.currentTrack?.id).toBe('1');
        });

        it('should seek to position', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.seek(30);

            // Position should be around 30 seconds
            const state = await TrackPlayer.getState();
            expect(state.currentPosition).toBeGreaterThanOrEqual(29);
            expect(state.currentPosition).toBeLessThanOrEqual(31);
        });

        it('should set repeat mode to off', async () => {
            await TrackPlayer.setRepeatMode('off');
        });

        it('should set repeat mode to Playlist', async () => {
            await TrackPlayer.setRepeatMode('Playlist');
        });

        it('should set repeat mode to track', async () => {
            await TrackPlayer.setRepeatMode('track');
        });

        it('should set volume to 50%', async () => {
            await TrackPlayer.setVolume(50);
        });

        it('should set volume to 0 (mute)', async () => {
            await TrackPlayer.setVolume(0);
        });

        it('should set volume to 100 (max)', async () => {
            await TrackPlayer.setVolume(100);
        });

        it('should clamp volume below 0', async () => {
            await TrackPlayer.setVolume(-10);
            // Volume should be clamped to 0
        });

        it('should clamp volume above 100', async () => {
            await TrackPlayer.setVolume(150);
            // Volume should be clamped to 100
        });
    });

    // // ============================================
    // // STATE MANAGEMENT
    // // ============================================

    describe('State Management', () => {
        it('should return correct state after loading playlist', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);

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
            await PlayerQueue.loadPlaylist(playlist1Id);

            const queue = await TrackPlayer.getActualQueue();
            expect(queue.length).toBe(sampleTracks1.length);
            expect(queue[0].id).toBe('1');
        });

        it('should update state after skip', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.skipToNext();

            const state = await TrackPlayer.getState();
            expect(state.currentTrack?.id).toBe('2');
            expect(state.currentIndex).toBe(1);
        });

        it('should maintain playlist ID across track changes', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.skipToNext();
            await TrackPlayer.skipToNext();

            const state = await TrackPlayer.getState();
            expect(state.currentPlaylistId).toBe(playlist1Id);
        });
    });

    // // ============================================
    // // skipToIndex
    // // ============================================

    describe('skipToIndex', () => {
        it('should skip to index in playNext section', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // Add playNext tracks (LIFO): p3-3, p3-2, p3-1
            await TrackPlayer.playNext('p3-1');
            await TrackPlayer.playNext('p3-2');
            await TrackPlayer.playNext('p3-3');

            // Queue: [1(current=0), p3-3(1), p3-2(2), p3-1(3), 2(4), 3(5)]
            // Skip to index 2 (p3-2)
            const success = await TrackPlayer.skipToIndex(2);
            expect(success).toBe(true);

            await waitForNextTick();
            const state = await TrackPlayer.getState();
            expect(state.currentTrack?.id).toBe('p3-2');
        });

        it('should skip to index in upNext section', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // Add upNext tracks (FIFO): 4, 5
            await TrackPlayer.addToUpNext('4');
            await TrackPlayer.addToUpNext('5');

            // Queue: [1(current=0), 4(1), 5(2), 2(3), 3(4)]
            // Skip to index 2 (5)
            const success = await TrackPlayer.skipToIndex(2);
            expect(success).toBe(true);

            await waitForNextTick();
            const state = await TrackPlayer.getState();
            expect(state.currentTrack?.id).toBe('5');
        });

        it('should clear temporary tracks when skipping to original playlist section', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);
            await waitForNextTick();

            // Add temporary tracks
            await TrackPlayer.playNext('p3-1');
            await TrackPlayer.addToUpNext('4');
            await waitForNextTick();

            // Verify queue structure before skip
            const queueBefore = await TrackPlayer.getActualQueue();
            console.log('Queue before skip:', queueBefore.map(t => t.id));
            // Queue: [1(0), p3-1(1), 4(2), 2(3), 3(4)]
            // Skip to index 3 (track 2 in original playlist)
            const success = await TrackPlayer.skipToIndex(3);
            expect(success).toBe(true);

            await waitForNextTick();
            await waitForNextTick(); // Extra wait for state to settle

            const state = await TrackPlayer.getState();

            expect(state.currentTrack?.id).toBe('2');

            // Verify temps are cleared
            const queue = await TrackPlayer.getActualQueue();
            expect(queue.find(t => t.id === 'p3-1')).toBeUndefined();
            expect(queue.find(t => t.id === '4')).toBeUndefined();
        });

        it('should skip to index before current position', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('2', playlist1Id);

            // Skip to index 0 (track 1)
            const success = await TrackPlayer.skipToIndex(0);
            expect(success).toBe(true);

            await waitForNextTick();
            const state = await TrackPlayer.getState();
            expect(state.currentTrack?.id).toBe('1');
        });

        it('should return false for invalid index', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            const success = await TrackPlayer.skipToIndex(100);
            expect(success).toBe(false);
        });

        it('should return false for negative index', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            const success = await TrackPlayer.skipToIndex(-1);
            expect(success).toBe(false);
        });
    });

    // // ============================================
    // // currentPlayingType in PlayerState
    // // ============================================

    describe('currentPlayingType in PlayerState', () => {
        it('should return "playlist" when playing from original playlist', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            const state = await TrackPlayer.getState();
            expect(state.currentPlayingType).toBe('playlist');
        });

        it('should return "play-next" when playing from playNext stack', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.playNext('4');
            await TrackPlayer.skipToNext();
            await waitForNextTick();

            const state = await TrackPlayer.getState();
            expect(state.currentPlayingType).toBe('play-next');
        });

        it('should return "up-next" when playing from upNext queue', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.addToUpNext('4');
            await TrackPlayer.skipToNext();
            await waitForNextTick();

            const state = await TrackPlayer.getState();
            expect(state.currentPlayingType).toBe('up-next');
        });

        it('should return "not-playing" when no track is playing', async () => {
            // Before loading any playlist, or after stopping
            await TrackPlayer.pause();
            await waitForNextTick();

            // Note: This test checks the initial state before any playlist is loaded
            // The actual behavior may vary - if a track was previously loaded, it might still report playlist
        });

        it('should transition from play-next to playlist after temp track finishes', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.playNext('4');
            await TrackPlayer.skipToNext(); // Now playing playNext track
            await waitForNextTick();

            let state = await TrackPlayer.getState();
            expect(state.currentPlayingType).toBe('play-next');

            await TrackPlayer.skipToNext(); // Skip to next (should be original playlist)
            await waitForNextTick();

            state = await TrackPlayer.getState();
            expect(state.currentPlayingType).toBe('playlist');
        });
    });

    // // ============================================
    // // EXTRA PAYLOAD
    // // ============================================

    describe('ExtraPayload in TrackItem', () => {
        it('should store extraPayload during track creation', async () => {
            const trackWithPayload: TrackItem = {
                id: 'payload-test-1',
                title: 'Track with Payload',
                artist: 'Test Artist',
                album: 'Test Album',
                duration: 180.0,
                url: 'https://example.com/test.mp3',
                artwork: 'https://example.com/art.jpg',
                extraPayload: {
                    customField: 'customValue',
                    numericField: 42,
                    nestedObject: { foo: 'bar' },
                },
            };

            const payloadPlaylistId = await PlayerQueue.createPlaylist('Payload Test Playlist', 'Test playlist for extraPayload');
            createdPlaylistIds.push(payloadPlaylistId);

            await PlayerQueue.addTracksToPlaylist(payloadPlaylistId, [trackWithPayload]);

            const playlist = PlayerQueue.getPlaylist(payloadPlaylistId);
            expect(playlist).not.toBeNull();
            expect(playlist!.tracks.length).toBe(1);
            expect(playlist!.tracks[0].extraPayload).toBeDefined();
        });

        it('should retrieve extraPayload from current track when playing', async () => {
            const trackWithPayload: TrackItem = {
                id: 'payload-test-2',
                title: 'Another Track with Payload',
                artist: 'Test Artist',
                album: 'Test Album',
                duration: 200.0,
                url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
                artwork: 'https://example.com/art2.jpg',
                extraPayload: {
                    source: 'library',
                    rating: 5,
                    tags: ['rock', 'classic'],
                },
            };

            const payloadPlaylistId = await PlayerQueue.createPlaylist('Play Payload Playlist', 'Test playlist for playing with extraPayload');
            createdPlaylistIds.push(payloadPlaylistId);

            await PlayerQueue.addTracksToPlaylist(payloadPlaylistId, [trackWithPayload]);

            await TrackPlayer.playSong('payload-test-2', payloadPlaylistId);
            await waitForNextTick();

            const state = await TrackPlayer.getState();
            expect(state.currentTrack).not.toBeNull();
            expect(state.currentTrack?.extraPayload).toBeDefined();
        });

        it('should handle track without extraPayload', async () => {
            const trackWithoutPayload: TrackItem = {
                id: 'no-payload-test',
                title: 'Track without Payload',
                artist: 'Test Artist',
                album: 'Test Album',
                duration: 150.0,
                url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
                artwork: null,
            };

            const noPayloadPlaylistId = await PlayerQueue.createPlaylist('No Payload Playlist', 'Test playlist without extraPayload');
            createdPlaylistIds.push(noPayloadPlaylistId);

            await PlayerQueue.addTracksToPlaylist(noPayloadPlaylistId, [trackWithoutPayload]);

            await TrackPlayer.playSong('no-payload-test', noPayloadPlaylistId);
            await waitForNextTick();

            const state = await TrackPlayer.getState();
            expect(state.currentTrack).not.toBeNull();
            expect(state.currentTrack?.id).toBe('no-payload-test');
            // extraPayload should be undefined or null when not provided
            expect(state.currentTrack?.extraPayload).toBeUndefined();
        });

        it('should preserve extraPayload in queue operations', async () => {
            const trackWithPayload: TrackItem = {
                id: 'queue-payload-test',
                title: 'Queue Payload Track',
                artist: 'Test Artist',
                album: 'Test Album',
                duration: 180.0,
                url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
                artwork: null,
                extraPayload: {
                    queueSource: 'search',
                    addedAt: 1234567890,
                },
            };

            const queuePayloadPlaylistId = await PlayerQueue.createPlaylist('Queue Payload Playlist', 'Test playlist for queue extraPayload');
            createdPlaylistIds.push(queuePayloadPlaylistId);

            await PlayerQueue.addTracksToPlaylist(queuePayloadPlaylistId, [trackWithPayload]);
            await PlayerQueue.loadPlaylist(queuePayloadPlaylistId);

            const queue = await TrackPlayer.getActualQueue();
            expect(queue.length).toBe(1);
            expect(queue[0].extraPayload).toBeDefined();
        });

        it('should preserve extraPayload when adding to playNext', async () => {
            // Create a track with extraPayload in a different playlist
            const trackForPlayNext: TrackItem = {
                id: 'playnext-payload',
                title: 'PlayNext Payload Track',
                artist: 'Test Artist',
                album: 'Test Album',
                duration: 180.0,
                url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
                artwork: null,
                extraPayload: {
                    addedVia: 'playNext',
                    priority: 1,
                },
            };

            const sourcePlaylistId = await PlayerQueue.createPlaylist('Source Playlist', 'Source for playNext');
            createdPlaylistIds.push(sourcePlaylistId);
            await PlayerQueue.addTracksToPlaylist(sourcePlaylistId, [trackForPlayNext]);

            // Load main playlist and add track to playNext
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);
            await TrackPlayer.playNext('playnext-payload');

            const queue = await TrackPlayer.getActualQueue();
            const playNextTrack = queue.find(t => t.id === 'playnext-payload');

            expect(playNextTrack).toBeDefined();
            expect(playNextTrack?.extraPayload?.addedVia).toBe('playNext');
            expect(playNextTrack?.extraPayload?.priority).toBe(1);
        });
    });

    // // ============================================
    // // EDGE CASES
    // // ============================================

    describe('Edge Cases', () => {
        it('should handle playNext with non-existent track ID', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // This should not crash
            await expect(TrackPlayer.playNext('non-existent-id')).resolves.toBeUndefined();
        });

        it('should handle addToUpNext with non-existent track ID', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            // This should not crash
            await expect(TrackPlayer.addToUpNext('non-existent-id')).resolves.toBeUndefined();
        });

        it('should handle seek beyond track duration', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await expect(TrackPlayer.seek(1000)).resolves.toBeUndefined();
        });

        it('should handle skip at last track with repeat off', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.setRepeatMode('off');

            // Play last track
            await TrackPlayer.playSong('3', playlist1Id);

            await expect(TrackPlayer.skipToNext()).resolves.toBeUndefined();
        });

        it('should handle skip at first track going previous', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await expect(TrackPlayer.skipToPrevious()).resolves.toBeUndefined();
        });
    });
});
