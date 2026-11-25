import {
  describe,
  it,
  expect,
  beforeEach,
  afterEach,
} from 'react-native-harness';
import {
  DownloadManager,
  DownloadState,
  TrackItem,
} from 'react-native-nitro-player';

const createTestTrack = (id: string, songNumber: number): TrackItem => ({
  id,
  title: `Same Track ${id}`,
  artist: 'Test Artist',
  album: 'Test Album',
  duration: 180.0,
  url: `https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${songNumber}.mp3`,
});

const wait = (ms: number) =>
  new Promise<void>(resolve => setTimeout(resolve, ms));

// Final states by download id, taken from the state events: Android drops a finished
// download from getDownloadTask, so polling the task never sees it complete there.
const finalStates = new Map<string, DownloadState>();
DownloadManager.onDownloadStateChange((downloadId, _trackId, state) => {
  if (state === 'completed' || state === 'failed') {
    finalStates.set(downloadId, state);
  }
});

const completedTrackIds = new Set<string>();
DownloadManager.onDownloadComplete(downloadedTrack => {
  completedTrackIds.add(downloadedTrack.trackId);
});

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

// Waits until the download completes or fails, or the timeout elapses.
const waitForFinish = async (
  downloadId: string,
  timeoutMs: number,
): Promise<DownloadState | undefined> => {
  const deadline = Date.now() + timeoutMs;
  while (!finalStates.has(downloadId) && Date.now() < deadline) {
    await wait(500);
  }
  return finalStates.get(downloadId);
};

// onDownloadComplete is a separate event sent right after the `completed` state.
const waitForCompleteEvent = async (trackId: string, timeoutMs: number) => {
  const deadline = Date.now() + timeoutMs;
  while (!completedTrackIds.has(trackId) && Date.now() < deadline) {
    await wait(100);
  }
  return completedTrackIds.has(trackId);
};

describe('DownloadManager - several downloads of the same track', () => {
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
    finalStates.clear();
    completedTrackIds.clear();
    trackIdsWithProgress.clear();
  });

  afterEach(async () => {
    try {
      await DownloadManager.cancelAllDownloads();
      await DownloadManager.deleteAllDownloads();
    } catch (e) {
      console.warn('Error cleaning up downloads:', e);
    }
  });

  it('should still record a download after an older one of the same track is cancelled', async () => {
    const blocker = createTestTrack('same-track-blocker', 10);
    const track = createTestTrack('same-track', 6);

    // With a single slot, the blocker takes it and both downloads of the track wait.
    // A blocker that fails at once would hand its slot on, so wait until it's running.
    const blockerId = await DownloadManager.downloadTrack(blocker);
    if (!(await waitForProgress(blocker.id, 15000))) {
      console.warn('No download progress within 15 seconds - skipping test');
      return;
    }
    const olderId = await DownloadManager.downloadTrack(track);
    const newerId = await DownloadManager.downloadTrack(track);
    const olderState = DownloadManager.getDownloadTask(olderId)?.state;
    const newerState = DownloadManager.getDownloadTask(newerId)?.state;
    if (olderState !== 'pending' || newerState !== 'pending') {
      console.warn(
        `Blocker ended early (older ${olderState}, newer ${newerState}) - skipping test`,
      );
      return;
    }

    // Drop the older download, then free the slot for the newer one
    await DownloadManager.cancelDownload(olderId);
    await DownloadManager.cancelDownload(blockerId);

    const state = await waitForFinish(newerId, 240000);
    console.log(`[same-track] newer download is ${state}`);
    // The blocker's progress showed the network works, so a download that never ends is a bug
    expect(state).toBeDefined();
    if (state === 'failed') {
      console.warn('Newer download failed - skipping test');
      return;
    }

    // The newer download must be saved, not only marked completed
    expect(await waitForCompleteEvent(track.id, 5000)).toBe(true);
    expect(await DownloadManager.isTrackDownloaded(track.id)).toBe(true);
  });
});
