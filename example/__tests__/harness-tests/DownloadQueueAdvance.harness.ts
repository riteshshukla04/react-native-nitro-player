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

// Polls until the download leaves `pending`, or the timeout elapses. Looks the task up by its
// download id, since a finished download of the same track can outlive the cleanup.
const waitForLeavingPending = async (
  downloadId: string,
  timeoutMs: number,
): Promise<string | undefined> => {
  const deadline = Date.now() + timeoutMs;
  let state = DownloadManager.getDownloadTask(downloadId)?.state;
  while (state === 'pending' && Date.now() < deadline) {
    await wait(250);
    state = DownloadManager.getDownloadTask(downloadId)?.state;
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
    expect(DownloadManager.getDownloadTask(downloadIdB)?.state).toBe('pending');
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

    const state = await waitForLeavingPending(downloadIdB, 20000);
    console.log(`[queue-advance] after cancel: B is ${state}`);

    // Failing on the network still means the queue moved on
    expect(['downloading', 'completed', 'failed']).toContain(state);
  });

  it('should start the next pending download when the active one is paused', async () => {
    if (!aIsDownloading) {
      console.warn('No download progress within 15 seconds - skipping test');
      return;
    }
    await DownloadManager.pauseDownload(downloadIdA);

    const state = await waitForLeavingPending(downloadIdB, 20000);
    console.log(`[queue-advance] after pause: B is ${state}`);

    expect(['downloading', 'completed', 'failed']).toContain(state);
  });

  it('should keep a resumed download pending while every slot is taken', async () => {
    if (!aIsDownloading) {
      console.warn('No download progress within 15 seconds - skipping test');
      return;
    }
    await DownloadManager.pauseDownload(downloadIdA);
    if ((await waitForLeavingPending(downloadIdB, 20000)) !== 'downloading') {
      console.warn('B did not start downloading - skipping test');
      return;
    }

    await DownloadManager.resumeDownload(downloadIdA);
    await wait(1000);

    const stateA = DownloadManager.getDownloadTask(downloadIdA)?.state;
    const stateB = DownloadManager.getDownloadTask(downloadIdB)?.state;
    console.log(`[queue-advance] after resume: A is ${stateA}, B is ${stateB}`);

    // B still holds the only slot, so A has to wait for it
    if (stateB === 'downloading') {
      expect(stateA).toBe('pending');
    } else {
      console.warn(`B is ${stateB}, not downloading - nothing to check`);
    }
  });
});
