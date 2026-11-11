import {
  describe,
  it,
  expect,
  beforeEach,
  afterEach,
} from 'react-native-harness';
import { DownloadManager, TrackItem } from 'react-native-nitro-player';

const createTestTrack = (id: string, songNumber: number): TrackItem => ({
  id,
  title: `Queue Advance Track ${id}`,
  artist: 'Test Artist',
  album: 'Test Album',
  duration: 180.0,
  url: `https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${songNumber}.mp3`,
});

const wait = (ms: number) =>
  new Promise<void>(resolve => setTimeout(resolve, ms));

// Track ids that have reported download progress, so a test can tell that a
// download is really running before it queues another one behind it.
const trackIdsWithProgress = new Set<string>();
DownloadManager.onDownloadProgress(progress => {
  trackIdsWithProgress.add(progress.trackId);
});

// False when no progress arrives in time (no network, or an unsigned simulator
// build, where background URLSession tasks fail before transferring a byte).
const waitForProgress = async (trackId: string, timeoutMs: number) => {
  const deadline = Date.now() + timeoutMs;
  while (!trackIdsWithProgress.has(trackId) && Date.now() < deadline) {
    await wait(100);
  }
  return trackIdsWithProgress.has(trackId);
};

// Polls until the download leaves `pending`, or the timeout elapses.
const waitForLeavingPending = async (
  trackId: string,
  timeoutMs: number,
): Promise<string | null> => {
  const deadline = Date.now() + timeoutMs;
  let state = DownloadManager.getDownloadState(trackId);
  while (state === 'pending' && Date.now() < deadline) {
    await wait(250);
    state = DownloadManager.getDownloadState(trackId);
  }
  return state;
};

describe('DownloadManager - queue advances when a slot is freed', () => {
  let trackA: TrackItem;
  let trackB: TrackItem;
  let downloadIdA: string;
  let downloadIdB: string;
  let aIsDownloading: boolean;

  beforeEach(async () => {
    DownloadManager.configure({
      storageLocation: 'private',
      maxConcurrentDownloads: 1,
      backgroundDownloadsEnabled: true,
      downloadArtwork: false,
      wifiOnlyDownloads: false,
    });

    await DownloadManager.cancelAllDownloads();
    await DownloadManager.deleteAllDownloads();

    trackA = createTestTrack('queue-advance-a', 4);
    trackB = createTestTrack('queue-advance-b', 8);

    // With a single slot, A takes it and B has to wait in the queue.
    trackIdsWithProgress.clear();
    downloadIdA = await DownloadManager.downloadTrack(trackA);
    aIsDownloading = await waitForProgress(trackA.id, 15000);
    if (!aIsDownloading) return;
    downloadIdB = await DownloadManager.downloadTrack(trackB);
    expect(DownloadManager.getDownloadState(trackB.id)).toBe('pending');
  });

  afterEach(async () => {
    try {
      await DownloadManager.cancelAllDownloads();
      await DownloadManager.deleteAllDownloads();
    } catch (e) {
      console.warn('Error cleaning up downloads:', e);
    }
  });

  it('should start the next pending download when the active one is cancelled', async () => {
    if (!aIsDownloading) {
      console.warn('No download progress within 15 seconds - skipping test');
      return;
    }
    await DownloadManager.cancelDownload(downloadIdA);

    const state = await waitForLeavingPending(trackB.id, 20000);
    console.log(`[queue-advance] after cancel: B is ${state}`);

    expect(downloadIdB).not.toBe(downloadIdA);
    expect(['downloading', 'completed']).toContain(state);
  });

  it('should start the next pending download when the active one is paused', async () => {
    if (!aIsDownloading) {
      console.warn('No download progress within 15 seconds - skipping test');
      return;
    }
    await DownloadManager.pauseDownload(downloadIdA);

    const state = await waitForLeavingPending(trackB.id, 20000);
    console.log(`[queue-advance] after pause: B is ${state}`);

    expect(['downloading', 'completed']).toContain(state);
  });
});
