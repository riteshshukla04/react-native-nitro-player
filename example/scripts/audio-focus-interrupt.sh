#!/usr/bin/env bash
# Runs the Android harness and fires a real audio-focus interruption when the audio-focus
# tests ask for one. `cmd notification post` cannot be used: it posts sound=null and requests
# no focus at all. An incoming call does take transient focus, which is what pauses playback.
# Emulator only — `emu gsm call` needs a qemu console.
set -uo pipefail

SERIAL="${ANDROID_SERIAL:-$(adb devices | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ {print $1; exit}')}"
[ -n "$SERIAL" ] || { echo "no emulator attached (emulator required for gsm call)"; exit 1; }

LOG=$(mktemp -t audio-focus-harness)
CALLER=15551234567

interrupt() {
  adb -s "$SERIAL" emu gsm call "$CALLER" >/dev/null
  sleep 6
  adb -s "$SERIAL" emu gsm cancel "$CALLER" >/dev/null
}

( cd "$(dirname "$0")/.." && ../node_modules/.bin/harness -c jest.harness.config.mjs --harnessRunner android TrackPlayer.harness ) 2>&1 | tee "$LOG" &
HARNESS=$!

seen=0
while kill -0 $HARNESS 2>/dev/null; do
  count=$(grep -c "AUDIO_FOCUS_READY" "$LOG" 2>/dev/null || echo 0)
  if [ "$count" -gt "$seen" ]; then
    seen=$count
    interrupt
  fi
  sleep 1
done

wait $HARNESS
