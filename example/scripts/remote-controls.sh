#!/usr/bin/env bash
# Runs the Android harness and presses the notification's Previous/Next through the media
# session when a test asks for it. The remote path goes MediaSession -> player, which is the
# one the JS API never exercises.
set -uo pipefail

SERIAL="${ANDROID_SERIAL:-$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')}"
[ -n "$SERIAL" ] || { echo "no device attached"; exit 1; }

LOG=$(mktemp -t remote-controls-harness)

( cd "$(dirname "$0")/.." && bun run test:harness --harnessRunner android TrackPlayer.harness ) 2>&1 | tee "$LOG" &
HARNESS=$!

seen=0
while kill -0 $HARNESS 2>/dev/null; do
  count=$(grep -c "REMOTE_DISPATCH" "$LOG" 2>/dev/null || echo 0)
  if [ "$count" -gt "$seen" ]; then
    button=$(grep "REMOTE_DISPATCH" "$LOG" | tail -1 | awk '{print $NF}')
    seen=$count
    adb -s "$SERIAL" shell cmd media_session dispatch "$button" >/dev/null 2>&1
  fi
  sleep 1
done

wait $HARNESS
