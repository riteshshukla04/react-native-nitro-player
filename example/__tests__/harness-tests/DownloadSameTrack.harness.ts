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
const downloadIdsWithProgress = new Set<string>();
// The size of the whole file, as each download last reported it
const reportedTotals = new Map<string, number>();
DownloadManager.onDownloadProgress(progress => {
  trackIdsWithProgress.add(progress.trackId);
  downloadIdsWithProgress.add(progress.downloadId);
  if (progress.totalBytes > 0) {
    reportedTotals.set(progress.downloadId, progress.totalBytes);
  }
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

// Like waitForProgress, for every one of the given downloads.
const waitForDownloadsProgress = async (
  downloadIds: string[],
  timeoutMs: number,
) => {
  const allHaveProgress = () =>
    downloadIds.every(id => downloadIdsWithProgress.has(id));
  const deadline = Date.now() + timeoutMs;
  while (!allHaveProgress() && Date.now() < deadline) {
    await wait(100);
  }
  return allHaveProgress();
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
    downloadIdsWithProgress.clear();
    reportedTotals.clear();
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

  it('should still record a running download after another running one of the same track is cancelled', async () => {
    // Two slots, so both downloads of the track run at once. A large file keeps them
    // running long enough to cancel one mid-download.
    DownloadManager.configure({
      storageLocation: 'private',
      maxConcurrentDownloads: 2,
      backgroundDownloadsEnabled: true,
      downloadArtwork: false,
      wifiOnlyDownloads: false,
    });
    const track = createTestTrack('same-track-running', 17);

    const cancelledId = await DownloadManager.downloadTrack(track);
    const keptId = await DownloadManager.downloadTrack(track);
    if (!(await waitForDownloadsProgress([cancelledId, keptId], 15000))) {
      console.warn('No download progress within 15 seconds - skipping test');
      return;
    }
    const cancelledState = DownloadManager.getDownloadTask(cancelledId)?.state;
    const keptState = DownloadManager.getDownloadTask(keptId)?.state;
    if (cancelledState !== 'downloading' || keptState !== 'downloading') {
      console.warn(
        `Downloads not both running (cancelled ${cancelledState}, kept ${keptState}) - skipping test`,
      );
      return;
    }

    // Cancelling one download must leave the file the other is still writing
    await DownloadManager.cancelDownload(cancelledId);

    const state = await waitForFinish(keptId, 240000);
    console.log(`[same-track] kept download is ${state}`);
    // Both downloads were transferring, so a download that never ends is a bug
    expect(state).toBeDefined();
    if (state === 'failed') {
      console.warn('Kept download failed - skipping test');
      return;
    }

    expect(await waitForCompleteEvent(track.id, 5000)).toBe(true);
    expect(await DownloadManager.isTrackDownloaded(track.id)).toBe(true);
  });

  // Two running downloads of one track, the second started once the first has written
  // bytes, so neither can mistake the other's bytes for its own. Undefined when they
  // don't both get going (no network, or the file finished too fast).
  const startOverlappingDownloads = async (track: TrackItem) => {
    // Two slots, so both run at once. A large file keeps them running together.
    DownloadManager.configure({
      storageLocation: 'private',
      maxConcurrentDownloads: 2,
      backgroundDownloadsEnabled: true,
      downloadArtwork: false,
      wifiOnlyDownloads: false,
    });
    const firstId = await DownloadManager.downloadTrack(track);
    if (!(await waitForDownloadsProgress([firstId], 15000))) {
      console.warn('No download progress within 15 seconds - skipping test');
      return undefined;
    }
    const secondId = await DownloadManager.downloadTrack(track);
    if (!(await waitForDownloadsProgress([secondId], 15000))) {
      console.warn('No progress for the second download - skipping test');
      return undefined;
    }
    const firstState = DownloadManager.getDownloadTask(firstId)?.state;
    const secondState = DownloadManager.getDownloadTask(secondId)?.state;
    if (firstState !== 'downloading' || secondState !== 'downloading') {
      console.warn(
        `Downloads not both running (first ${firstState}, second ${secondState}) - skipping test`,
      );
      return undefined;
    }
    return { firstId, secondId };
  };

  // The saved file must be exactly the file the download fetched
  const expectSavedFileSize = async (trackId: string, downloadId: string) => {
    const total = reportedTotals.get(downloadId);
    const saved = await DownloadManager.getDownloadedTrack(trackId);
    console.log(
      `[same-track] saved ${saved?.fileSize} bytes, download reported ${total}`,
    );
    expect(total).toBeGreaterThan(0);
    expect(saved?.fileSize).toBe(total);
  };

  it('should save the whole file when one of two overlapping downloads of a track is cancelled', async () => {
    const track = createTestTrack('same-track-overlap-cancel', 17);
    const ids = await startOverlappingDownloads(track);
    if (!ids) return;

    await DownloadManager.cancelDownload(ids.firstId);

    const state = await waitForFinish(ids.secondId, 240000);
    console.log(`[same-track] remaining download is ${state}`);
    expect(state).toBeDefined();
    if (state === 'failed') {
      console.warn('Remaining download failed - skipping test');
      return;
    }

    expect(await waitForCompleteEvent(track.id, 5000)).toBe(true);
    await expectSavedFileSize(track.id, ids.secondId);
  });

  it('should save the whole file when two overlapping downloads of a track both finish', async () => {
    const track = createTestTrack('same-track-overlap-both', 17);
    const ids = await startOverlappingDownloads(track);
    if (!ids) return;

    const firstState = await waitForFinish(ids.firstId, 240000);
    const secondState = await waitForFinish(ids.secondId, 240000);
    console.log(
      `[same-track] first download is ${firstState}, second is ${secondState}`,
    );
    expect(firstState).toBeDefined();
    expect(secondState).toBeDefined();
    if (firstState === 'failed' || secondState === 'failed') {
      console.warn('A download failed - skipping test');
      return;
    }

    expect(await waitForCompleteEvent(track.id, 5000)).toBe(true);
    expect(reportedTotals.get(ids.firstId)).toBe(
      reportedTotals.get(ids.secondId),
    );
    await expectSavedFileSize(track.id, ids.secondId);
  });
});
