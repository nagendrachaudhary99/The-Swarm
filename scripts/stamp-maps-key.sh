#!/usr/bin/env bash
# Put the Maps key into a BUILT bundle, not into the repo.
#
# web/index.html carries the placeholder __GOOGLE_MAPS_KEY__ and stays that way
# in git. This stamps the real key into build output after the fact, so the key
# never lands in a commit — which matters because this repo is public and
# Google's scanners do read public repos.
#
#   GOOGLE_MAPS_KEY=AIza... bash scripts/stamp-maps-key.sh build/web
set -euo pipefail
DIR="${1:-build/web}"
: "${GOOGLE_MAPS_KEY:?set GOOGLE_MAPS_KEY}"

[ -f "$DIR/index.html" ] || { echo "no $DIR/index.html — build first"; exit 1; }
# macOS sed and GNU sed disagree about -i; write through a temp file instead.
sed "s|__GOOGLE_MAPS_KEY__|$GOOGLE_MAPS_KEY|g" "$DIR/index.html" > "$DIR/index.html.tmp"
mv "$DIR/index.html.tmp" "$DIR/index.html"
echo "✓ stamped the Maps key into $DIR/index.html"
