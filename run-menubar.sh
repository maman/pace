#!/usr/bin/env bash
# Canonical local run path for Pace.
# Regenerates the Tuist project (without opening Xcode), builds Debug,
# then restarts any running Pace instance and launches the fresh build.
set -euo pipefail

cd "$(dirname "$0")"

SCHEME="Pace"
CONFIG="Debug"
DERIVED_DATA="build"

export TUIST_SKIP_UPDATE_CHECK=1

echo "==> Generating Tuist project"
tuist generate --no-open

echo "==> Building ${SCHEME} (${CONFIG})"
tuist xcodebuild build \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -destination 'platform=macOS' \
    | tail -n 40

APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIG}/${SCHEME}.app"
if [ ! -d "${APP_PATH}" ]; then
    echo "Build product missing at ${APP_PATH}" >&2
    exit 1
fi

echo "==> Stopping any existing Pace instance"
"$(dirname "$0")/stop-menubar.sh" || true

echo "==> Launching ${APP_PATH}"
open -a "${APP_PATH}"
