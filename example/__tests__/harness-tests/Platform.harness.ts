import { describe, it, expect } from 'react-native-harness';
import { Platform } from 'react-native';
import {
  Cast,
  AudioDevices,
  AudioRoutePicker,
  AndroidAutoMediaLibrary,
  PlayerQueue,
} from 'react-native-nitro-player';
import { sampleTracks1 } from '../../src/data/sampleTracks';

// AndroidAutoMediaLibrary is Android-only and AudioRoutePicker iOS-only (null on the other platform);
// AudioDevices exists on both, but its device list is Android-only. Each suite checks before it runs.

describe('Cast', () => {
  const wait = (ms = 300) => new Promise<void>(resolve => setTimeout(resolve, ms));

  it('should not be casting without a receiver', async () => {
    await Cast.configure(undefined);
    await wait();

    expect(Cast.isCasting()).toBe(false);
    expect(Cast.getCastDeviceName()).toBe(null);
  });

  it('should report a disconnected state without a receiver', async () => {
    await Cast.configure(undefined);
    await wait();

    // Discovery may or may not find a device; either way nothing is connected.
    expect(['no_devices_available', 'not_connected', 'connecting']).toContain(
      Cast.getCastState()
    );
  });

  it('should register a state listener without firing a connection', async () => {
    const states: string[] = [];
    Cast.onCastStateChange(state => {
      states.push(state);
    });

    await Cast.configure(undefined);
    await wait(1000);

    expect(states).not.toContain('connected');
  });

  it('should ignore ending a session that was never started', async () => {
    await Cast.endCastSession();

    expect(Cast.isCasting()).toBe(false);
  });
});

const OUTPUT_TYPES = [
  'built_in_speaker',
  'built_in_earpiece',
  'wired_headphones',
  'line_out',
  'bluetooth',
  'usb',
  'airplay',
  'car_audio',
  'hdmi',
  'unknown',
];

describe('AudioDevices: current outputs', () => {
  const wait = (ms = 300) => new Promise<void>(resolve => setTimeout(resolve, ms));

  it('should report the output media plays through', () => {
    const outputs = AudioDevices.getCurrentOutputs();

    expect(outputs.length > 0).toBe(true);
    for (const output of outputs) {
      expect(output.id.length > 0).toBe(true);
      expect(output.name.length > 0).toBe(true);
      expect(OUTPUT_TYPES).toContain(output.type);
    }
  });

  it('should report the same outputs on every read', () => {
    const ids = (list: { id: string }[]) => list.map(o => o.id).join(',');

    expect(ids(AudioDevices.getCurrentOutputs())).toBe(
      ids(AudioDevices.getCurrentOutputs())
    );
  });

  it('should stay quiet after registering while the outputs are unchanged', async () => {
    // Android reports every connected device as added on registration; that must not count as a change
    const reasons: string[] = [];
    AudioDevices.onOutputsChange((_outputs, reason) => {
      reasons.push(reason);
    });
    await wait(1000);

    expect(reasons.length).toBe(0);
  });

  it('should have no devices to select on iOS', async () => {
    if (Platform.OS !== 'ios') return;

    expect(AudioDevices.getAudioDevices().length).toBe(0);
    await expect(AudioDevices.setAudioDevice(1)).rejects.toBeDefined();
  });
});

describe('AudioDevices: device list (Android only)', () => {
  it('should list at least the built-in output', () => {
    if (Platform.OS !== 'android') return;

    expect(AudioDevices.getAudioDevices().length > 0).toBe(true);
  });

  it('should keep at most one device active', () => {
    if (Platform.OS !== 'android') return;

    const active = AudioDevices.getAudioDevices().filter(d => d.isActive);
    expect(active.length <= 1).toBe(true);
  });

  it('should reject an unknown device id and leave the selection alone', async () => {
    if (Platform.OS !== 'android') return;

    const before = AudioDevices.getAudioDevices().find(d => d.isActive)?.id;
    await expect(AudioDevices.setAudioDevice(999999)).rejects.toBeDefined();

    expect(AudioDevices.getAudioDevices().find(d => d.isActive)?.id).toBe(before);
  });
});

describe('AndroidAutoMediaLibrary (Android only)', () => {
  it('should accept a media library and then clear it', async () => {
    if (!AndroidAutoMediaLibrary) return;

    const playlistId = await PlayerQueue.createPlaylist('Media Library Test');
    await PlayerQueue.addTracksToPlaylist(playlistId, sampleTracks1);

    const library = JSON.stringify({
      root: { title: 'Harness Root', children: [{ type: 'playlist', id: playlistId }] },
    });

    await AndroidAutoMediaLibrary.setMediaLibrary(library);
    await AndroidAutoMediaLibrary.clearMediaLibrary();

    // The browse tree is not readable from JS; the contract is that neither call throws
    // and the playlist it referenced survives.
    expect(PlayerQueue.getPlaylist(playlistId)?.tracks.length).toBe(sampleTracks1.length);

    await PlayerQueue.deletePlaylist(playlistId);
  });
});

// These present a system sheet the harness cannot dismiss, so they run last and only
// assert that the call itself is safe.
describe('System Pickers', () => {
  it('should open the route picker without throwing', () => {
    if (!AudioRoutePicker) return;

    AudioRoutePicker.showRoutePicker();
  });

  it('should open the cast picker without throwing', () => {
    Cast.showCastPicker();
  });
});
