import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { PlayerQueue, TrackPlayer } from 'react-native-nitro-player';
import type { TrackItem } from 'react-native-nitro-player';

const N = 500;
const REPS = 20;
const STORM_MS = 10000;
const URL = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';

function makeTracks(): TrackItem[] {
  const out: TrackItem[] = [];
  for (let i = 0; i < N; i++) {
    out.push({
      id: `bench-${i}`,
      title: `Bench Track ${i}`,
      artist: 'Bench',
      album: 'Bench Album',
      duration: 180,
      url: URL,
      artwork: undefined,
      extraPayload: undefined,
    });
  }
  return out;
}

const now = () => Date.now();

export default function BenchScreen() {
  const [lines, setLines] = useState<string[]>([]);
  const [running, setRunning] = useState(false);
  const push = useCallback((l: string) => {
    console.log(`[BENCH] ${l}`);
    setLines((p) => [...p, l]);
  }, []);
  const stateEvents = useRef(0);
  const trackEvents = useRef(0);
  const progressEvents = useRef(0);

  const run = useCallback(async () => {
    setLines([]);
    setRunning(true);
    try {
      const tracks = makeTracks();

      const pid = await PlayerQueue.createPlaylist(`bench-${now()}`);

      let t = now();
      await PlayerQueue.addTracksToPlaylist(pid, tracks);
      push(`addTracks(${N})           ${now() - t} ms`);

      t = now();
      await PlayerQueue.loadPlaylist(pid);
      push(`loadPlaylist(${N})        ${now() - t} ms`);

      // getActualQueue round-trips
      t = now();
      let totalTracks = 0;
      for (let i = 0; i < REPS; i++) {
        const q = await TrackPlayer.getActualQueue();
        totalTracks += q.length;
      }
      push(
        `getActualQueue x${REPS}      ${now() - t} ms  (${totalTracks} items marshalled)`,
      );

      // skipToIndex
      t = now();
      for (let i = 0; i < REPS; i++) {
        await TrackPlayer.skipToIndex((i * 17) % N);
      }
      push(`skipToIndex x${REPS}        ${now() - t} ms`);

      // playNext (each triggers a native upcoming-queue rebuild)
      await TrackPlayer.skipToIndex(0);
      t = now();
      for (let i = 0; i < REPS; i++) {
        await TrackPlayer.playNext(`bench-${300 + i}`);
      }
      push(`playNext x${REPS}           ${now() - t} ms`);
      await TrackPlayer.clearPlayNext();

      // addToUpNext
      t = now();
      for (let i = 0; i < REPS; i++) {
        await TrackPlayer.addToUpNext(`bench-${400 + i}`);
      }
      push(`addToUpNext x${REPS}        ${now() - t} ms`);
      await TrackPlayer.clearUpNext();

      // Event storm — what a mounted useActualQueue + useNowPlaying costs
      stateEvents.current = 0;
      trackEvents.current = 0;
      progressEvents.current = 0;
      let stormTracks = 0;
      let stormFetches = 0;
      const off = { stop: false };
      TrackPlayer.onPlaybackStateChange(() => {
        stateEvents.current++;
        if (off.stop) return;
        stormFetches++;
        TrackPlayer.getActualQueue().then(
          (q) => {
            stormTracks += q.length;
          },
          () => {},
        );
      });
      TrackPlayer.onChangeTrack(() => {
        trackEvents.current++;
      });
      TrackPlayer.onPlaybackProgressChange(() => {
        progressEvents.current++;
      });

      await TrackPlayer.skipToIndex(0);
      await TrackPlayer.play();
      await new Promise((r) => setTimeout(r, STORM_MS));
      await TrackPlayer.pause();
      off.stop = true;
      await new Promise((r) => setTimeout(r, 500));

      push(`--- ${STORM_MS / 1000}s playback storm ---`);
      push(`onPlaybackStateChange     ${stateEvents.current} events`);
      push(`onChangeTrack             ${trackEvents.current} events`);
      push(`onPlaybackProgressChange  ${progressEvents.current} events`);
      push(`queue refetches           ${stormFetches}`);
      push(`tracks marshalled to JS   ${stormTracks}`);

      await PlayerQueue.deletePlaylist(pid);
    } catch (e) {
      push(`ERROR ${String(e)}`);
    }
    setRunning(false);
  }, [push]);

  const started = useRef(false);
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    const t = setTimeout(() => {
      run();
    }, 3000);
    return () => clearTimeout(t);
  }, [run]);

  return (
    <View style={styles.container}>
      <TouchableOpacity
        onPress={run}
        disabled={running}
        style={[styles.button, running && styles.buttonDisabled]}>
        <Text style={styles.buttonLabel}>
          {running ? 'Running…' : 'Run benchmark'}
        </Text>
      </TouchableOpacity>
      <ScrollView style={styles.output}>
        {lines.map((l, i) => (
          <Text key={i} style={styles.line}>
            {l}
          </Text>
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    paddingTop: 60,
    paddingHorizontal: 12,
    backgroundColor: '#fff',
  },
  button: { padding: 14, backgroundColor: '#222', borderRadius: 8 },
  buttonDisabled: { backgroundColor: '#999' },
  buttonLabel: { color: '#fff', textAlign: 'center', fontWeight: '600' },
  output: { marginTop: 16 },
  line: { fontFamily: 'Menlo', fontSize: 12, marginBottom: 3 },
});
