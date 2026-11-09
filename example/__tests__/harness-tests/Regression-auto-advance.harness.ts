import { describe, it, expect, beforeEach, afterEach } from 'react-native-harness';
import { TrackPlayer, PlayerQueue } from 'react-native-nitro-player';
import { sampleTracks1 } from '../../src/data/sampleTracks';

// Regression: when a playlist track finishes and the next starts (AUTO transition),
// onMediaItemTransition used removeAt(indexOfFirst{...}) on upNextQueue with -1
// -> IndexOutOfBoundsException on the main looper, killing the app.
describe('Regression - auto advance to next track', () => {
    let playlistId: string;

    const waitFor = async (cond: () => Promise<boolean>, timeoutMs = 30000) => {
        const deadline = Date.now() + timeoutMs;
        while (Date.now() < deadline) {
            if (await cond()) return true;
            await new Promise<void>(r => setTimeout(r, 250));
        }
        return false;
    };

    beforeEach(async () => {
        await TrackPlayer.setRepeatMode('off');
        playlistId = await PlayerQueue.createPlaylist('Regression auto-advance', '');
        await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);
    });

    afterEach(async () => {
        try {
            await TrackPlayer.pause();
            await PlayerQueue.deletePlaylist(playlistId);
        } catch {}
    });

    it('advances to the next track when the current one finishes without crashing', async () => {
        await PlayerQueue.loadPlaylist(playlistId);
        await TrackPlayer.playSong(sampleTracks1[0].id, playlistId);
        await TrackPlayer.play();
        const playing = await waitFor(async () => (await TrackPlayer.getState()).currentState === 'playing');
        if (!playing) console.log('STATE', JSON.stringify(await TrackPlayer.getState()));
        expect(playing).toBe(true);

        // Jump close to the end so the player auto-advances on its own.
        let total = 0;
        expect(await waitFor(async () => (total = (await TrackPlayer.getState()).totalDuration) > 5)).toBe(true);
        await TrackPlayer.seek(total - 2);

        const advanced = await waitFor(
            async () => (await TrackPlayer.getState()).currentTrack?.id === sampleTracks1[1].id
        );
        expect(advanced).toBe(true);
    });
});
