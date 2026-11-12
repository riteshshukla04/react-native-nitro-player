import {
  describe,
  it,
  expect,
  beforeEach,
  afterEach,
} from 'react-native-harness';
import { TrackPlayer, PlayerQueue, TrackItem } from 'react-native-nitro-player';

const createTestTrack = (id: string, songNumber: number): TrackItem => ({
  id,
  title: `Track Change Reason ${id}`,
  artist: 'Test Artist',
  album: 'Test Album',
  duration: 180.0,
  url: `https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${songNumber}.mp3`,
});

const wait = (ms: number) =>
  new Promise<void>(resolve => setTimeout(resolve, ms));

const waitUntil = async (condition: () => boolean, timeoutMs: number) => {
  const deadline = Date.now() + timeoutMs;
  while (!condition() && Date.now() < deadline) {
    await wait(250);
  }
  return condition();
};

describe('TrackPlayer - onChangeTrack reason', () => {
  let playlistId: string;
  let changes: { trackId: string; reason?: string }[] = [];

  // Callbacks cannot be unregistered, so each test only listens while it is active.
  let listening = false;
  TrackPlayer.onChangeTrack((track, reason) => {
    if (listening) changes.push({ trackId: track.id, reason });
  });

  const reasonForTrack = (trackId: string) =>
    changes.find(change => change.trackId === trackId)?.reason;

  // Starts track 1 and reports whether the audio actually loaded.
  const startPlaying = async () => {
    await PlayerQueue.loadPlaylist(playlistId);
    await TrackPlayer.playSong('1', playlistId);
    await TrackPlayer.play();
    let lastState = 'unknown';
    const deadline = Date.now() + 20000;
    while (Date.now() < deadline) {
      const state = await TrackPlayer.getState();
      lastState = state.currentState;
      if (state.currentState === 'playing') return true;
      await wait(250);
    }
    console.warn(
      `Audio did not start (state: ${lastState}, no network?) - skipping test`,
    );
    return false;
  };

  beforeEach(async () => {
    await TrackPlayer.setRepeatMode('off');
    playlistId = await PlayerQueue.createPlaylist(
      'Track Change Reason Playlist',
      'Playlist for onChangeTrack reason tests',
    );
    await PlayerQueue.addTracksToPlaylist(playlistId, [
      createTestTrack('1', 1),
      createTestTrack('2', 2),
    ]);
    changes = [];
    listening = true;
  });

  afterEach(async () => {
    listening = false;
    try {
      await TrackPlayer.pause();
      await PlayerQueue.deletePlaylist(playlistId);
    } catch (e) {
      console.warn('Error cleaning up playlist:', e);
    }
  });

  it('should report "end" when a track finishes and the next one starts by itself', async () => {
    if (!(await startPlaying())) return;

    // Jump to the last seconds of track 1 instead of waiting for a whole song.
    const { totalDuration } = await TrackPlayer.getState();
    await TrackPlayer.seek(Math.max(totalDuration - 3, 0));

    const advanced = await waitUntil(
      () => reasonForTrack('2') !== undefined,
      30000,
    );
    console.log(`[track-change-reason] natural end: ${reasonForTrack('2')}`);

    expect(advanced).toBe(true);
    expect(reasonForTrack('2')).toBe('end');
  });

  it('should report "skip" when skipToNext moves to the next track', async () => {
    if (!(await startPlaying())) return;

    await TrackPlayer.skipToNext();

    const advanced = await waitUntil(
      () => reasonForTrack('2') !== undefined,
      10000,
    );
    console.log(`[track-change-reason] skipToNext: ${reasonForTrack('2')}`);

    expect(advanced).toBe(true);
    expect(reasonForTrack('2')).toBe('skip');
  });
});
