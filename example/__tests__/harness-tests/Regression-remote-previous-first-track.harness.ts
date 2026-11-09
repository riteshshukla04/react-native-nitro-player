import { describe, it, expect, beforeEach, afterEach } from 'react-native-harness';
import { TrackPlayer, PlayerQueue } from 'react-native-nitro-player';
import { Platform } from 'react-native';
import { sampleTracks1 } from '../../src/data/sampleTracks';

/**
 * Regression: pressing Previous on the media notification / a Bluetooth headset while the FIRST
 * track of the queue plays crashed the app (ArrayIndexOutOfBoundsException, index=-1) because the
 * session player's seekToPrevious looked up the item before the current one.
 */
describe('Regression - remote Previous on the first track', () => {
    let playlistId: string;

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

    beforeEach(async () => {
        for (const p of PlayerQueue.getAllPlaylists()) {
            await PlayerQueue.deletePlaylist(p.id);
        }
        await TrackPlayer.setRepeatMode('off');
        playlistId = await PlayerQueue.createPlaylist('Regression Playlist', 'remote previous');
        await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
    });

    afterEach(async () => {
        try {
            await PlayerQueue.deletePlaylist(playlistId);
        } catch (e) {
            console.warn('Error deleting playlist:', e);
        }
    });

    it('should survive notification Previous on the first track and stay on it', async () => {
        if (Platform.OS !== 'android') return;

        await PlayerQueue.loadPlaylist(playlistId);
        await TrackPlayer.playSong('1', playlistId);
        await TrackPlayer.play();
        await waitForState(s => s.currentState === 'playing');
        await TrackPlayer.seek(0);

        // Serviced by harness-run.sh via `cmd media_session dispatch`
        console.log('REMOTE_DISPATCH previous');

        // If the process crashes the bridge drops and this never resolves successfully.
        await new Promise<void>(resolve => setTimeout(resolve, 3000));
        const state = await waitForState(s => s.currentTrack?.id === '1' && s.currentState === 'playing', 20000);
        expect(state.currentTrack?.id).toBe('1');
        expect(state.currentState).toBe('playing');
    });
});
