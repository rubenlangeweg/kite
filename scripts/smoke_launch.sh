#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(pwd)/build/Build/Products/Release/Kite.app"
if [[ ! -d "$APP" ]]; then
  echo "Release app not found at $APP — run scripts/build_release.sh first" >&2
  exit 1
fi

open "$APP"
sleep 3
PID=$(pgrep -x Kite || true)
if [[ -z "$PID" ]]; then
  echo "Kite did not launch" >&2
  exit 1
fi

# Graceful quit via AppleScript; fall back to SIGTERM if blocked by TCC.
osascript -e 'tell application "Kite" to quit' 2>/dev/null || kill -TERM "$PID" 2>/dev/null || true
sleep 2

LEAKED=$(pgrep -P "$PID" -x git 2>/dev/null || true)
if [[ -n "$LEAKED" ]]; then
  echo "Leaked git subprocesses after Kite quit: $LEAKED" >&2
  exit 1
fi
echo "OK — no leaked subprocesses"
