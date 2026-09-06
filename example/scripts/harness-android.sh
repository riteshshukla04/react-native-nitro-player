#!/usr/bin/env bash
# Runs the Android harness and services the interruptions the tests ask for. Some behaviour
# can only be driven from the host: an audio-focus loss needs another app to take focus, and
# the notification buttons go through the media session, not the JS API. Tests announce what
# they need on stdout and this fires it.
#
#   AUDIO_FOCUS_READY <mode>   -> incoming call (transient focus loss). Emulator only.
#   REMOTE_DISPATCH <button>   -> media session button (previous/next/play/pause)
set -uo pipefail

SERIAL="${ANDROID_SERIAL:-$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')}"
[ -n "$SERIAL" ] || { echo "no device attached"; exit 1; }

# Plain mktemp: BSD and GNU disagree about -t without an XXXXXX template.
LOG=$(mktemp)
[ -n "$LOG" ] || { echo "mktemp failed"; exit 1; }
CALLER=15551234567

# Redirect rather than pipe to tee, so the status does not depend on pipefail staying set:
# `wait` on a `... | tee` pipeline reports tee's status without it. tail -f keeps output live.
run_harness() {
  : > "$LOG"
  ( cd "$(dirname "$0")/.." && bun run test:harness --harnessRunner android "$@" ) > "$LOG" 2>&1 &
  local harness=$!
  tail -f "$LOG" &
  local tailer=$!

  local seen=0 count line
  while kill -0 "$harness" 2>/dev/null; do
    count=$(grep -cE "AUDIO_FOCUS_READY|REMOTE_DISPATCH" "$LOG" 2>/dev/null || echo 0)
    if [ "$count" -gt "$seen" ]; then
      seen=$count
      line=$(grep -E "AUDIO_FOCUS_READY|REMOTE_DISPATCH" "$LOG" | tail -1)
      case "$line" in
        *AUDIO_FOCUS_READY*)
          # `cmd notification post` is useless here: it posts sound=null and requests no focus.
          adb -s "$SERIAL" emu gsm call "$CALLER" >/dev/null 2>&1
          sleep 6
          adb -s "$SERIAL" emu gsm cancel "$CALLER" >/dev/null 2>&1
          ;;
        *REMOTE_DISPATCH*)
          adb -s "$SERIAL" shell cmd media_session dispatch "$(echo "$line" | awk '{print $NF}')" >/dev/null 2>&1
          ;;
      esac
    fi
    sleep 1
  done

  wait "$harness"
  local status=$?
  kill "$tailer" 2>/dev/null
  return $status
}

# The harness client connects to the bridge once, with no retry: a lost connect after an app
# restart hangs that suite until bridgeTimeout. Retry the run rather than the flake.
for attempt in 1 2; do
  if run_harness "$@"; then exit 0; fi
  echo "harness attempt $attempt failed, retrying"
  adb -s "$SERIAL" shell am force-stop com.example >/dev/null 2>&1
  sleep 10
done
exit 1
