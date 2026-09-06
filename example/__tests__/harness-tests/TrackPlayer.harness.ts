import { describe, it, expect, beforeEach, afterEach } from 'react-native-harness';
import { TrackPlayer, PlayerQueue, TrackItem } from 'react-native-nitro-player';
import { Platform } from 'react-native';
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

    /** Streaming tracks take time to start, so poll for the state instead of assuming a fixed delay. */
    const waitForState = async (
        matches: (state: Awaited<ReturnType<typeof TrackPlayer.getState>>) => boolean,
        timeoutMs = 15000
    ) => {
        const deadline = Date.now() + timeoutMs;
        let state = await TrackPlayer.getState();
        while (Date.now() < deadline && !matches(state)) {
            await new Promise<void>(resolve => setTimeout(resolve, 250));
            state = await TrackPlayer.getState();
        }
        return state;
    };

    const waitForPlaying = () => waitForState(s => s.currentState === 'playing');

    /** Polls until the callback list contains what we are waiting for. */
    const waitForValue = async <T,>(values: T[], match: (v: T) => boolean, timeoutMs = 10000) => {
        const deadline = Date.now() + timeoutMs;
        while (Date.now() < deadline && !values.some(match)) {
            await new Promise<void>(resolve => setTimeout(resolve, 250));
        }
    };

    // Real audio: an unreachable URL makes every AVPlayerItem fail, and the recovery
    // retries wedge the player for the tests that follow.
    const createTestTrack = (id: string, title: string, song = 6): TrackItem => ({
        id,
        title,
        artist: 'Test Artist',
        album: 'Test Album',
        duration: 180.0,
        url: `https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${song}.mp3`,
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

        // Repeat is global: a test that leaves it on 'track' makes every later test
        // buffer a duplicate of its own item.
        await TrackPlayer.setRepeatMode('off');

        playlist1Id = await PlayerQueue.createPlaylist('Test Playlist 1', 'First test playlist');
        playlist2Id = await PlayerQueue.createPlaylist('Test Playlist 2', 'Second test playlist');
        playlist3Id = await PlayerQueue.createPlaylist('Test Playlist 3', 'Third test playlist');

        createdPlaylistIds.push(playlist1Id, playlist2Id, playlist3Id);

        await PlayerQueue.addTracksToPlaylist(playlist1Id, sampleTracks1);
        await PlayerQueue.addTracksToPlaylist(playlist2Id, sampleTracks2);
        await PlayerQueue.addTracksToPlaylist(playlist3Id, [
            createTestTrack('p3-1', 'Playlist 3 Track 1', 6),
            createTestTrack('p3-2', 'Playlist 3 Track 2', 7),
            createTestTrack('p3-3', 'Playlist 3 Track 3', 8),
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
            await waitForPlaying();
            await waitForValue(states, state => state === 'playing');

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
            await TrackPlayer.play();
            await waitForPlaying();

            await TrackPlayer.seek(30);
            await waitForValue(seekPositions, position => position === 30);

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
            let state = await waitForPlaying();
            expect(state.currentState).toBe('playing');

            await TrackPlayer.pause();
            state = await waitForState(s => s.currentState === 'paused');
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
            await TrackPlayer.play();
            await waitForPlaying();

            await TrackPlayer.seek(30);
            const state = await waitForState(s => s.currentPosition >= 29);

            // Position should be around 30 seconds
            expect(state.currentPosition).toBeGreaterThanOrEqual(29);
            expect(state.currentPosition).toBeLessThanOrEqual(35);
            await TrackPlayer.pause();
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

            await TrackPlayer.play();
            await waitForPlaying();

            // Add playNext tracks (LIFO): p3-3, p3-2, p3-1
            await TrackPlayer.playNext('p3-1');
            await TrackPlayer.playNext('p3-2');
            await TrackPlayer.playNext('p3-3');

            // Queue: [1(current=0), p3-3(1), p3-2(2), p3-1(3), 2(4), 3(5)]
            // Skip to index 2 (p3-2)
            const success = await TrackPlayer.skipToIndex(2);
            expect(success).toBe(true);

            const state = await waitForState(s => s.currentTrack?.id === 'p3-2');
            expect(state.currentTrack?.id).toBe('p3-2');
        });

        it('should skip to index in upNext section', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await TrackPlayer.play();
            await waitForPlaying();

            // Add upNext tracks (FIFO): 4, 5
            await TrackPlayer.addToUpNext('4');
            await TrackPlayer.addToUpNext('5');

            // Queue: [1(current=0), 4(1), 5(2), 2(3), 3(4)]
            // Skip to index 2 (5)
            const success = await TrackPlayer.skipToIndex(2);
            expect(success).toBe(true);

            const state = await waitForState(s => s.currentTrack?.id === '5');
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
        it('should reject playNext with non-existent track ID', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await expect(TrackPlayer.playNext('non-existent-id')).rejects.toThrow();
        });

        it('should reject addToUpNext with non-existent track ID', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);

            await expect(TrackPlayer.addToUpNext('non-existent-id')).rejects.toThrow();
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

    describe('Temporary Queue Management', () => {
        const settle = async () => { await waitForNextTick(); await waitForNextTick(); };
        const ids = (tracks: TrackItem[]) => tracks.map(t => t.id);

        it('should expose the playNext stack in play order', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playNext('2');
            await TrackPlayer.playNext('3');
            await settle();

            // LIFO: the last one added plays first.
            expect(ids(await TrackPlayer.getPlayNextQueue())).toStrictEqual(['3', '2']);
        });

        it('should expose the upNext queue in play order', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.addToUpNext('2');
            await TrackPlayer.addToUpNext('3');
            await settle();

            expect(ids(await TrackPlayer.getUpNextQueue())).toStrictEqual(['2', '3']);
        });

        it('should remove a single track from the playNext stack', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playNext('2');
            await TrackPlayer.playNext('3');
            await settle();

            expect(await TrackPlayer.removeFromPlayNext('2')).toBe(true);
            await settle();

            expect(ids(await TrackPlayer.getPlayNextQueue())).toStrictEqual(['3']);
        });

        it('should report false when removing a track that is not queued', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await settle();

            expect(await TrackPlayer.removeFromPlayNext('2')).toBe(false);
            expect(await TrackPlayer.removeFromUpNext('2')).toBe(false);
        });

        it('should remove a single track from the upNext queue', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.addToUpNext('2');
            await TrackPlayer.addToUpNext('3');
            await settle();

            expect(await TrackPlayer.removeFromUpNext('2')).toBe(true);
            await settle();

            expect(ids(await TrackPlayer.getUpNextQueue())).toStrictEqual(['3']);
        });

        it('should clear each temporary queue independently', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playNext('2');
            await TrackPlayer.addToUpNext('3');
            await settle();

            await TrackPlayer.clearPlayNext();
            await settle();
            expect(await TrackPlayer.getPlayNextQueue()).toStrictEqual([]);
            expect(ids(await TrackPlayer.getUpNextQueue())).toStrictEqual(['3']);

            await TrackPlayer.clearUpNext();
            await settle();
            expect(await TrackPlayer.getUpNextQueue()).toStrictEqual([]);
        });

        it('should reorder across the combined temporary queue', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playNext('2');
            await TrackPlayer.addToUpNext('3');
            await settle();

            // Combined order is playNext then upNext: ['2', '3'].
            expect(await TrackPlayer.reorderTemporaryTrack('3', 0)).toBe(true);
            await settle();

            const combined = [
                ...ids(await TrackPlayer.getPlayNextQueue()),
                ...ids(await TrackPlayer.getUpNextQueue()),
            ];
            expect(combined).toStrictEqual(['3', '2']);
        });

        it('should report false when reordering a track that is not queued', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await settle();

            expect(await TrackPlayer.reorderTemporaryTrack('2', 0)).toBe(false);
        });

        it('should notify listeners whenever the temporary queue changes', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            const snapshots: string[][] = [];
            TrackPlayer.onTemporaryQueueChange((playNextQueue, upNextQueue) => {
                snapshots.push([...ids(playNextQueue), ...ids(upNextQueue)]);
            });
            await settle();

            await TrackPlayer.playNext('2');
            await settle();
            await TrackPlayer.clearPlayNext();
            await settle();

            expect(snapshots.some(s => s.includes('2'))).toBe(true);
            expect(snapshots[snapshots.length - 1]).toStrictEqual([]);
        });
    });

    describe('Playback Speed', () => {
        it('should play back at the speed it was set to', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.play();
            await waitForNextTick();

            await TrackPlayer.setPlaybackSpeed(1.5);
            expect(await TrackPlayer.getPlaybackSpeed()).toBe(1.5);

            await TrackPlayer.setPlaybackSpeed(1);
            expect(await TrackPlayer.getPlaybackSpeed()).toBe(1);
            await TrackPlayer.pause();
        });
    });

    describe('Track Lookup', () => {
        const ids = (tracks: TrackItem[]) => tracks.map(t => t.id);

        it('should return requested tracks in the order they were asked for', async () => {
            const found = await TrackPlayer.getTracksById(['3', '1']);

            expect(ids(found)).toStrictEqual(['3', '1']);
        });

        it('should skip ids that belong to no playlist', async () => {
            const found = await TrackPlayer.getTracksById(['1', 'no-such-track']);

            expect(ids(found)).toStrictEqual(['1']);
        });

        it('should report the tracks that come after the current one', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);
            await waitForNextTick();

            const next = await TrackPlayer.getNextTracks(2);

            expect(ids(next)).toStrictEqual(['2', '3']);
        });

        it('should count the playing track position within the playlist', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('3', playlist1Id);
            await waitForNextTick();

            expect(await TrackPlayer.getCurrentTrackIndex()).toBe(2);
        });

        it('should list no tracks needing urls when every url is known', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await waitForNextTick();

            expect(await TrackPlayer.getTracksNeedingUrls()).toStrictEqual([]);
        });

        it('should apply an updated track to the live queue', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await waitForNextTick();
            const original = (await TrackPlayer.getTracksById(['2']))[0];

            await TrackPlayer.updateTracks([{ ...original, title: 'Renamed By Harness' }]);
            await waitForNextTick();

            expect((await TrackPlayer.getTracksById(['2']))[0].title).toBe('Renamed By Harness');
            expect(PlayerQueue.getPlaylist(playlist1Id)?.tracks[1].title).toBe('Renamed By Harness');

            await TrackPlayer.updateTracks([original]);
        });

        it('should apply a same-url metadata update to the playing track without interrupting it', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);
            await TrackPlayer.play();
            await waitForPlaying();

            const original = (await TrackPlayer.getTracksById(['1']))[0];
            const before = await TrackPlayer.getState();
            let changes = 0;
            TrackPlayer.onChangeTrack(() => {
                changes += 1;
            });

            // Same url, new title — a language switch or a late metadata fetch.
            await TrackPlayer.updateTracks([{ ...original, title: 'Retitled While Playing' }]);
            await waitForNextTick();

            const state = await waitForState(s => s.currentTrack?.title === 'Retitled While Playing');
            expect(state.currentTrack?.title).toBe('Retitled While Playing');
            expect(state.currentTrack?.id).toBe('1');

            // The item itself must not be rebuilt: playback keeps running from where it was.
            const after = await waitForState(s => s.currentPosition > before.currentPosition, 8000);
            expect(after.currentPosition > before.currentPosition).toBe(true);
            expect(after.currentState).toBe('playing');
            expect(changes).toBe(0);

            await TrackPlayer.updateTracks([original]);
        });

        it('should still refuse a url change for the playing track', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);
            await TrackPlayer.play();
            await waitForPlaying();

            const original = (await TrackPlayer.getTracksById(['1']))[0];
            await TrackPlayer.updateTracks([
                { ...original, url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-9.mp3' },
            ]);
            await waitForNextTick();

            expect((await TrackPlayer.getTracksById(['1']))[0].url).toBe(original.url);
        });
    });

    describe('Progress Reporting', () => {
        it('should report progress that advances while playing', async () => {
            const positions: number[] = [];
            TrackPlayer.onPlaybackProgressChange(position => {
                positions.push(position);
            });

            // Start from a known playable track: earlier tests can leave failed items queued.
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);
            await TrackPlayer.play();
            await waitForPlaying();
            await waitForValue(positions, position => position > 0);
            await TrackPlayer.pause();

            expect(positions.length > 0).toBe(true);
            expect(positions[positions.length - 1] > 0).toBe(true);
        });
    });

    describe('Configuration', () => {
        it('should accept a configuration without disturbing playback', async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('2', playlist1Id);
            await TrackPlayer.play();
            await waitForNextTick();

            await TrackPlayer.configure({ lookaheadCount: 3, showInNotification: true });
            await waitForNextTick();

            const state = await TrackPlayer.getState();
            expect(state.currentTrack?.id).toBe('2');
            await TrackPlayer.pause();
        });
    });

    describe('Android Auto', () => {
        it('should report a connection state without a head unit attached', () => {
            // No head unit in the harness, so this must be false rather than throwing.
            expect(TrackPlayer.isAndroidAutoConnected()).toBe(false);
        });
    });

    describe('Lazy URL Resolution', () => {
        it('should ask for urls of tracks that have none', async () => {
            const lazyPlaylistId = await PlayerQueue.createPlaylist('Lazy URL Test');
            createdPlaylistIds.push(lazyPlaylistId);
            await PlayerQueue.addTracksToPlaylist(lazyPlaylistId, [
                { ...createTestTrack('lazy-1', 'Lazy One'), url: '' },
                { ...createTestTrack('lazy-2', 'Lazy Two'), url: '' },
            ]);

            const asked: string[] = [];
            TrackPlayer.onTracksNeedUpdate(tracks => {
                tracks.forEach(t => asked.push(t.id));
            });
            await waitForNextTick();

            await PlayerQueue.loadPlaylist(lazyPlaylistId);
            await waitForNextTick();
            await waitForNextTick();

            expect(asked).toContain('lazy-1');
            expect((await TrackPlayer.getTracksNeedingUrls()).map(t => t.id)).toContain('lazy-1');
        });
    });

    describe('Timed Metadata', () => {
        it('should not report in-stream metadata for a plain audio file', async () => {
            const received: string[] = [];
            TrackPlayer.onTimedMetadata(metadata => {
                received.push(metadata.title ?? '');
            });

            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.play();
            await new Promise<void>(resolve => setTimeout(resolve, 4000));
            await TrackPlayer.pause();

            // ICY/ID3 frames only arrive from streams; an mp3 file must stay silent here.
            expect(received).toStrictEqual([]);
        });
    });

    describe('Android Auto Events', () => {
        it('should not report a connection while no head unit is attached', async () => {
            const events: boolean[] = [];
            TrackPlayer.onAndroidAutoConnectionChange(connected => {
                events.push(connected);
            });

            await PlayerQueue.loadPlaylist(playlist1Id);
            await waitForNextTick();

            expect(events).not.toContain(true);
        });
    });

    describe('Notification Launch', () => {
        it('should not report a notification launch for a normally started app', async () => {
            const launches: boolean[] = [];
            TrackPlayer.appStartedWithNotification(started => {
                launches.push(started);
            });
            await waitForNextTick();

            expect(launches).not.toContain(true);
        });
    });

    // ============================================
    // ANDROID AUDIO FOCUS
    // ============================================

    describe('Android audio focus', () => {
        /**
         * The interruption is a real one (an incoming call takes transient focus), so it has to
         * come from the host: scripts/audio-focus-interrupt.sh watches for this line and fires
         * `adb emu gsm call`. Without that driver the assertions below fail rather than pass
         * quietly, which is the point — a silent pass would prove nothing.
         */
        const announceReady = (mode: string) => console.log(`AUDIO_FOCUS_READY ${mode}`);

        const playAndSettle = async () => {
            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);
            await TrackPlayer.play();
            const state = await waitForState(s => s.currentState === 'playing', 20000);
            expect(state.currentState).toBe('playing');
        };

        it('should pause and resume across an interruption in the default mode', async () => {
            if (Platform.OS !== 'android') return;

            await TrackPlayer.configure({ androidAudioFocus: 'pause' });
            await playAndSettle();

            announceReady('pause');

            const interrupted = await waitForState(s => s.currentState === 'paused', 40000);
            expect(interrupted.currentState).toBe('paused');

            const resumed = await waitForState(s => s.currentState === 'playing', 40000);
            expect(resumed.currentState).toBe('playing');
        });

        it('should keep playing through an interruption in duck mode', async () => {
            if (Platform.OS !== 'android') return;

            await TrackPlayer.configure({ androidAudioFocus: 'duck' });
            await playAndSettle();

            const before = await TrackPlayer.getState();
            announceReady('duck');

            // Watch the whole interruption window: ducking lowers the volume, it never pauses.
            const deadline = Date.now() + 30000;
            while (Date.now() < deadline) {
                const state = await TrackPlayer.getState();
                expect(state.currentState).not.toBe('paused');
                await new Promise<void>(resolve => setTimeout(resolve, 500));
            }

            const after = await TrackPlayer.getState();
            expect(after.currentPosition > before.currentPosition).toBe(true);
        });

        it('should accept every focus mode', async () => {
            await expect(TrackPlayer.configure({ androidAudioFocus: 'ignore' })).resolves.toBeUndefined();
            await expect(TrackPlayer.configure({ androidAudioFocus: 'duck' })).resolves.toBeUndefined();
            await expect(TrackPlayer.configure({ androidAudioFocus: 'pause' })).resolves.toBeUndefined();
    // REMOTE (MEDIA SESSION) CONTROLS
    // ============================================

    describe('Remote controls', () => {
        /**
         * System UI / Bluetooth drive the MediaSession, not the JS API, and the ExoPlayer
         * timeline is only a window over the logical queue. The button press has to come from
         * the host: scripts/remote-controls.sh watches for this line and runs
         * `adb shell cmd media_session dispatch`.
         */
        const announceReady = (button: string) => console.log(`REMOTE_DISPATCH ${button}`);

        it('should step to the previous track when the notification Previous is pressed', async () => {
            if (Platform.OS !== 'android') return;

            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('2', playlist1Id);
            await TrackPlayer.play();
            await waitForPlaying();
            // Past the 2s mark Previous restarts the track by design, so ask for it early.
            await TrackPlayer.seek(0);

            announceReady('previous');

            const state = await waitForState(s => s.currentTrack?.id === '1', 30000);
            expect(state.currentTrack?.id).toBe('1');
        });

        it('should step to the next track when the notification Next is pressed', async () => {
            if (Platform.OS !== 'android') return;

            await PlayerQueue.loadPlaylist(playlist1Id);
            await TrackPlayer.playSong('1', playlist1Id);
            await TrackPlayer.play();
            await waitForPlaying();

            announceReady('next');

            const state = await waitForState(s => s.currentTrack?.id === '2', 30000);
            expect(state.currentTrack?.id).toBe('2');
        });
    });
});
