#!/usr/bin/env bash
# Exercise scripts/appcast-upsert.py with fixtures and assert correctness.
# Run from repo root; exits non-zero on any assertion failure.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/appcast-upsert.py"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > meta-1.json <<'JSON'
{"shortVersionString":"0.1.0","version":"1","edSignature":"AAAA","length":1000,
 "pubDate":"Mon, 13 Apr 2026 00:00:00 +0000","minimumSystemVersion":"14.0"}
JSON
cat > meta-2.json <<'JSON'
{"shortVersionString":"0.2.0","version":"42","edSignature":"BBBB","length":2000,
 "pubDate":"Tue, 14 Apr 2026 00:00:00 +0000","minimumSystemVersion":"14.0"}
JSON

echo "TEST 1: bootstrap creates a valid appcast on first run"
python3 "$SCRIPT" appcast.xml meta-1.json \
    "https://example.com/notes/v0.1.0" "https://example.com/zip/v0.1.0"
xmllint --noout appcast.xml
[ "$(grep -c '<item>' appcast.xml)" = "1" ] || { echo "FAIL: expected 1 item"; exit 1; }
grep -q 'sparkle:version="1"' appcast.xml          || { echo "FAIL: missing v1 enclosure attr"; exit 1; }
grep -q 'sparkle:edSignature="AAAA"' appcast.xml   || { echo "FAIL: missing v1 ed sig"; exit 1; }

echo "TEST 2: idempotent rerun does NOT duplicate (upsert by enclosure sparkle:version)"
python3 "$SCRIPT" appcast.xml meta-1.json \
    "https://example.com/notes/v0.1.0" "https://example.com/zip/v0.1.0"
xmllint --noout appcast.xml
[ "$(grep -c '<item>' appcast.xml)" = "1" ] || { echo "FAIL: rerun duplicated to $(grep -c '<item>' appcast.xml) items"; exit 1; }

echo "TEST 2b: same version, CHANGED metadata — must REPLACE, not just dedupe"
cat > meta-1-fixed.json <<'JSON'
{"shortVersionString":"0.1.0","version":"1","edSignature":"CCCC-FIXED","length":9999,
 "pubDate":"Wed, 15 Apr 2026 00:00:00 +0000","minimumSystemVersion":"14.0"}
JSON
python3 "$SCRIPT" appcast.xml meta-1-fixed.json \
    "https://example.com/notes/v0.1.0-fixed" "https://example.com/zip/v0.1.0-fixed"
xmllint --noout appcast.xml
[ "$(grep -c '<item>' appcast.xml)" = "1" ] \
    || { echo "FAIL: replace produced $(grep -c '<item>' appcast.xml) items, expected 1"; exit 1; }
grep -q 'sparkle:edSignature="CCCC-FIXED"' appcast.xml \
    || { echo "FAIL: edSignature not updated to CCCC-FIXED"; cat appcast.xml; exit 1; }
grep -q 'length="9999"'                    appcast.xml \
    || { echo "FAIL: length not updated to 9999"; exit 1; }
grep -q 'url="https://example.com/zip/v0.1.0-fixed"' appcast.xml \
    || { echo "FAIL: enclosure url not updated"; exit 1; }
grep -q '>https://example.com/notes/v0.1.0-fixed<' appcast.xml \
    || { echo "FAIL: releaseNotesLink not updated"; exit 1; }
if grep -q 'edSignature="AAAA"' appcast.xml; then
    echo "FAIL: old edSignature AAAA still present after replace"; exit 1
fi
echo "OK: same-version replace correctly overwrote all fields"

echo "TEST 3: new version is prepended, both items present"
python3 "$SCRIPT" appcast.xml meta-2.json \
    "https://example.com/notes/v0.2.0" "https://example.com/zip/v0.2.0"
xmllint --noout appcast.xml
[ "$(grep -c '<item>' appcast.xml)" = "2" ] || { echo "FAIL: expected 2 items after second version"; exit 1; }
FIRST_VER=$(python3 -c "
import xml.etree.ElementTree as ET
NS={'sparkle':'http://www.andymatuschak.org/xml-namespaces/sparkle'}
t=ET.parse('appcast.xml')
enc=t.getroot().find('channel').find('item').find('enclosure')
print(enc.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}version'))
")
[ "$FIRST_VER" = "42" ] || { echo "FAIL: newest item not at top (got version=$FIRST_VER)"; exit 1; }

echo "TEST 4: shape error — missing <channel> — fails fast with clear message"
echo '<?xml version="1.0"?><rss version="2.0"></rss>' > broken.xml
if python3 "$SCRIPT" broken.xml meta-1.json "x" "y" 2>err.log; then
    echo "FAIL: should have rejected appcast missing <channel>"; exit 1
fi
grep -q "<channel> missing" err.log || { echo "FAIL: error message unclear: $(cat err.log)"; exit 1; }

echo "TEST 5: meta.json missing required key fails"
echo '{"shortVersionString":"0.1.0"}' > bad-meta.json
if python3 "$SCRIPT" appcast.xml bad-meta.json "x" "y" 2>err2.log; then
    echo "FAIL: should reject meta.json with missing keys"; exit 1
fi
grep -q "meta.json missing key" err2.log || { echo "FAIL: missing-key error unclear"; exit 1; }

echo "ALL TESTS PASSED"
