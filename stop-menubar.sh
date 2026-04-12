#!/usr/bin/env bash
# Stop any running Pace instance.
set -euo pipefail

BUNDLE_ID="me.mahardi.pace"

if pgrep -x "Pace" >/dev/null 2>&1; then
    osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null || true
    sleep 0.3
fi

if pgrep -x "Pace" >/dev/null 2>&1; then
    pkill -x "Pace" || true
fi
