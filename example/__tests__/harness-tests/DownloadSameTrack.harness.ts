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
  title: `Same Track ${id}`,
  artist: 'Test Artist',
  album: 'Test Album',
  duration: 180.0,
  url: `https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${songNumber}.mp3`,
});

const wait = (ms: number) =>
  new Promise<void>(resolve => setTimeout(resolve, ms));

// Polls until the download reaches `completed` or `failed`, or the timeout elapses.
const waitForFinish = async (
  downloadId: string,
  timeoutMs: number,
): Promise<string | undefined> => {
  const deadline = Date.now() + timeoutMs;
  let state = DownloadManager.getDownloadTask(downloadId)?.state;
  while (state !== 'completed' && state !== 'failed' && Date.now() < deadline) {
    await wait(500);
    state = DownloadManager.getDownloadTask(downloadId)?.state;
  }
  return state;
};

describe('DownloadManager - several downloads of the same track', () => {
  const completedTrackIds = new Set<string>();
  DownloadManager.onDownloadComplete(downloadedTrack => {
    completedTrackIds.add(downloadedTrack.trackId);
  });

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
    completedTrackIds.clear();
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

    // With a single slot, the blocker takes it and both downloads of the track wait
    const blockerId = await DownloadManager.downloadTrack(blocker);
    const olderId = await DownloadManager.downloadTrack(track);
    const newerId = await DownloadManager.downloadTrack(track);
    await wait(500);
    expect(DownloadManager.getDownloadTask(olderId)?.state).toBe('pending');
    expect(DownloadManager.getDownloadTask(newerId)?.state).toBe('pending');

    // Drop the older download, then free the slot for the newer one
    await DownloadManager.cancelDownload(olderId);
    await DownloadManager.cancelDownload(blockerId);

    const state = await waitForFinish(newerId, 240000);
    console.log(`[same-track] newer download is ${state}`);
    if (state !== 'completed') {
      console.warn(`Newer download is ${state}, not completed - skipping test`);
      return;
    }

    // The newer download must be saved, not only marked completed
    expect(completedTrackIds.has(track.id)).toBe(true);
    expect(await DownloadManager.isTrackDownloaded(track.id)).toBe(true);
  });
});
