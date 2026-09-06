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

( cd "$(dirname "$0")/.." && bun run test:harness --harnessRunner android "$@" ) 2>&1 | tee "$LOG" &
HARNESS=$!

seen=0
while kill -0 $HARNESS 2>/dev/null; do
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

wait $HARNESS
