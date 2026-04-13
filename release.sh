#!/usr/bin/env bash
# Build, sign, notarize, staple, and sign-for-update a Release build of Pace.
# Produces dist/Pace-<version>.zip (ready for GitHub Releases) + dist/appcast-meta.json
# (consumed by the release workflow to assemble the appcast item).
#
# Prereqs:
#   - "Developer ID Application: ... (DKL5CLP48A)" cert in your login keychain
#   - notarytool credentials stored under "$NOTARY_PROFILE" (default: AC_NOTARY).
#     Bypass by exporting SKIP_NOTARIZATION=1 for local dry-runs.
#   - EdDSA private key in login keychain (generic password, account=ed25519,
#     service="https://sparkle-project.org") so sign_update can sign the zip.
#
# Override via env: NOTARY_PROFILE=other SKIP_NOTARIZATION=1 SPARKLE_BIN=/abs/path ./release.sh
set -euo pipefail

cd "$(dirname "$0")"

SCHEME="Pace"
CONFIG="Release"
BUNDLE_ID="me.mahardi.pace"
TEAM_ID="DKL5CLP48A"
DERIVED_DATA="build"
# Tuist 4 pre-resolves SPM packages into Tuist/.build/ at `tuist install` time.
# xcodebuild doesn't re-resolve during archive; it references Tuist's resolved
# artifacts. Sparkle's sign_update binary therefore lives under Tuist/.build/,
# NOT under build/SourcePackages/ (that dir is only populated when SPM is
# driven directly by xcodebuild, which Tuist bypasses).
SPM_DIR="Tuist/.build/artifacts"
DIST_DIR="dist"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
SPARKLE_BIN="${SPARKLE_BIN:-}"

APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIG}/${SCHEME}.app"
NOTARIZE_ZIP="${DIST_DIR}/${SCHEME}-notarize.zip"
# DIST_ZIP is set after MARKETING_VERSION is resolved from git.

step() { printf "\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31mERROR:\033[0m %s\n" "$1" >&2; exit 1; }
# Pretty output via xcbeautify if available, otherwise raw pass-through.
xcb() { if command -v xcbeautify >/dev/null 2>&1; then xcbeautify; else cat; fi; }

step "Preflight checks"

command -v tuist >/dev/null || fail "tuist not found in PATH (install via mise)"
command -v xcrun >/dev/null || fail "xcrun not found"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application.*${TEAM_ID}"; then
    fail "Developer ID Application cert for team ${TEAM_ID} not found in keychain"
fi

if [ "${SKIP_NOTARIZATION}" != "1" ]; then
    if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
        fail "notarytool profile '${NOTARY_PROFILE}' not configured. Run:
    xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" --apple-id <id> --team-id ${TEAM_ID} --password <app-specific-password>
Or set SKIP_NOTARIZATION=1 for a local dry-run."
    fi
fi

step "Resolving version from git"
if RAW_TAG=$(git describe --tags --abbrev=0 2>/dev/null); then
    MARKETING_VERSION="${RAW_TAG#v}"
else
    MARKETING_VERSION="0.0.0"
    echo "  no git tag found; using ${MARKETING_VERSION}"
fi
BUILD_NUMBER=$(git rev-list --count HEAD)
echo "  marketing: ${MARKETING_VERSION}"
echo "  build:     ${BUILD_NUMBER}"

step "Cleaning previous artifacts"
rm -rf "${DERIVED_DATA}/Build/Products/${CONFIG}" "${DERIVED_DATA}/Pace.xcarchive" "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

step "Resolving packages"
TUIST_SKIP_UPDATE_CHECK=1 tuist install

step "Generating Tuist project"
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

ARCHIVE_PATH="${DERIVED_DATA}/Pace.xcarchive"
EXPORT_PATH="${DERIVED_DATA}/Build/Products/${CONFIG}"
EXPORT_PLIST="${DERIVED_DATA}/ExportOptions.plist"

step "Archiving ${SCHEME} ${MARKETING_VERSION} (${BUILD_NUMBER}) — ${CONFIG}"
mkdir -p "${DERIVED_DATA}"
cat > "${EXPORT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>manual</string>
  <key>destination</key><string>export</string>
</dict></plist>
PLIST

TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild archive \
    -scheme "${SCHEME}" -configuration "${CONFIG}" \
    -destination 'generic/platform=macOS' \
    -archivePath "${ARCHIVE_PATH}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -clonedSourcePackagesDirPath "${SPM_DIR}" \
    "MARKETING_VERSION=${MARKETING_VERSION}" \
    "CURRENT_PROJECT_VERSION=${BUILD_NUMBER}" \
    | xcb

step "Exporting archive"
xcrun xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_PLIST}" \
    | xcb

[ -d "${APP_PATH}" ] || fail "export product missing at ${APP_PATH}"

# Prove Sparkle was actually embedded — catches dropped dependencies or SPM
# resolution failures before wasting time on codesign + notary.
[ -d "${APP_PATH}/Contents/Frameworks/Sparkle.framework" ] \
    || fail "Sparkle.framework not embedded in ${APP_PATH}/Contents/Frameworks. Did Project.swift drop the .external(name: \"Sparkle\") dependency, or did SPM resolution fail?"
[ -L "${APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/Current" ] \
    || fail "Sparkle.framework/Versions/Current symlink missing — framework appears malformed"

step "Verifying Info.plist Sparkle keys"
/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "${APP_PATH}/Contents/Info.plist" >/dev/null \
    || fail "SUFeedURL missing from Info.plist"

PUBKEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "")
if [ -z "${PUBKEY}" ]; then
    fail "SUPublicEDKey missing or empty in Info.plist"
fi
if [ "${PUBKEY}" = "<PUBLIC_KEY_PLACEHOLDER>" ] || [[ "${PUBKEY}" == *"PLACEHOLDER"* ]]; then
    fail "SUPublicEDKey is still the placeholder (${PUBKEY}). Run generate_keys (manual step 2) and paste the real base64 key into Project.swift."
fi
if [ "${#PUBKEY}" -lt 40 ]; then
    fail "SUPublicEDKey looks malformed (${#PUBKEY} chars; expected ~44 for a base64-encoded 32-byte EdDSA public key). Value was: ${PUBKEY}"
fi
if ! [[ "${PUBKEY}" =~ ^[A-Za-z0-9+/=]+$ ]]; then
    fail "SUPublicEDKey contains non-base64 characters. Value was: ${PUBKEY}"
fi
echo "  SUPublicEDKey looks valid (${#PUBKEY} base64 chars)"

step "Verifying app + embedded Sparkle signatures (recursive)"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 | tail -n 3

SPARKLE_CURRENT="${APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/Current"
if [ -d "${SPARKLE_CURRENT}" ]; then
    echo "  Sparkle layout:"
    find -L "${SPARKLE_CURRENT}" -maxdepth 3 \
         \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" \) \
         -print 2>/dev/null | sed 's|^|    |'
fi

CODESIGN_INFO=$(codesign -dvv "${APP_PATH}" 2>&1)
echo "${CODESIGN_INFO}" | grep -qE 'Authority=Developer ID Application' || fail "app not Developer ID signed"
echo "${CODESIGN_INFO}" | grep -q  'Timestamp='                         || fail "missing secure timestamp"
echo "${CODESIGN_INFO}" | grep -q  'Runtime Version='                   || fail "Hardened Runtime not enabled"

step "Packaging for notarization"
ditto -c -k --keepParent "${APP_PATH}" "${NOTARIZE_ZIP}"

if [ "${SKIP_NOTARIZATION}" != "1" ]; then
    step "Submitting to Apple Notary Service (this can take a few minutes)"
    xcrun notarytool submit "${NOTARIZE_ZIP}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait

    step "Stapling notarization ticket"
    xcrun stapler staple "${APP_PATH}"
    xcrun stapler validate "${APP_PATH}"

    step "Verifying Gatekeeper acceptance"
    spctl --assess --type install --verbose=2 "${APP_PATH}" 2>&1 | tail -n 2
else
    step "SKIPPING notarization/staple (SKIP_NOTARIZATION=1)"
fi

step "Building distribution zip"
rm -f "${NOTARIZE_ZIP}"
DIST_ZIP="${DIST_DIR}/${SCHEME}-${MARKETING_VERSION}.zip"
ditto -c -k --keepParent "${APP_PATH}" "${DIST_ZIP}"

step "Locating Sparkle sign_update binary"
if [ -n "${SPARKLE_BIN}" ]; then
    [ -x "${SPARKLE_BIN}" ] || fail "SPARKLE_BIN=${SPARKLE_BIN} is not executable"
    echo "  sign_update (env override): ${SPARKLE_BIN}"
else
    # Exclude old_dsa_scripts/ — Sparkle ships a legacy DSA-signing copy there
    # alongside the modern EdDSA binary. We only want the modern one.
    SPARKLE_HITS=$(find "${SPM_DIR}" -type f -name sign_update -perm -u+x \
                    -not -path '*/old_dsa_scripts/*' 2>/dev/null || true)
    HIT_COUNT=$(printf '%s\n' "${SPARKLE_HITS}" | grep -c . || true)
    if [ "${HIT_COUNT}" -eq 0 ]; then
        fail "sign_update not found anywhere under ${SPM_DIR}. Did 'tuist install' run? Try: find ${SPM_DIR} -name sign_update"
    elif [ "${HIT_COUNT}" -gt 1 ]; then
        fail "Multiple sign_update binaries found under ${SPM_DIR} — ambiguous. Set SPARKLE_BIN env to disambiguate. Found:
${SPARKLE_HITS}"
    fi
    SPARKLE_BIN="${SPARKLE_HITS}"
    echo "  sign_update: ${SPARKLE_BIN}"
fi

step "Signing update with EdDSA"
SIG_OUTPUT=$("${SPARKLE_BIN}" "${DIST_ZIP}")
ED_SIG=$(echo "${SIG_OUTPUT}"  | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')
ZIP_LEN=$(echo "${SIG_OUTPUT}" | sed -nE 's/.*length="([0-9]+)".*/\1/p')
[ -n "${ED_SIG}" ] && [ -n "${ZIP_LEN}" ] || fail "sign_update produced empty signature. Raw output: ${SIG_OUTPUT}"

PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
MIN_MACOS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "${APP_PATH}/Contents/Info.plist")

step "Emitting appcast metadata (release URL + notes filled in by workflow)"
cat > "${DIST_DIR}/appcast-meta.json" <<JSON
{
  "shortVersionString": "${MARKETING_VERSION}",
  "version": "${BUILD_NUMBER}",
  "edSignature": "${ED_SIG}",
  "length": ${ZIP_LEN},
  "pubDate": "${PUB_DATE}",
  "minimumSystemVersion": "${MIN_MACOS}"
}
JSON

printf "\n\033[1;32mDone.\033[0m  %s %s (build %s)\n" "${SCHEME}" "${MARKETING_VERSION}" "${BUILD_NUMBER}"
printf "  app:  %s\n" "${APP_PATH}"
printf "  zip:  %s (%s)\n" "${DIST_ZIP}" "$(du -h "${DIST_ZIP}" | cut -f1)"
printf "  meta: %s\n" "${DIST_DIR}/appcast-meta.json"
