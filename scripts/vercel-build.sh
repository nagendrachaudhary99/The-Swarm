#!/usr/bin/env bash
set -euo pipefail

# Vercel's build image has Node, Python and Go — but not Flutter. So we fetch a
# shallow stable clone into the build sandbox. It is cached between builds when
# the sandbox is reused, and costs about two minutes when it is not.
if [ ! -d "$HOME/flutter" ]; then
  echo "→ fetching Flutter (stable, shallow)"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"

flutter --version
flutter config --enable-web
flutter pub get

# --pwa-strategy=none: the service worker serves a stale bundle for one extra
# reload after every deploy, which looks exactly like "my fix didn't ship".
flutter build web --release --pwa-strategy=none \
  --dart-define=GOOGLE_MAPS_KEY="${GOOGLE_MAPS_KEY:-}"

# The key goes into the built bundle, never into the repo. Config.hasMaps is
# what the Dart side checks; this is what the browser needs to load the JS API.
# With no key set, both stay empty and the app draws its own map.
if [ -n "${GOOGLE_MAPS_KEY:-}" ]; then
  bash ./scripts/stamp-maps-key.sh build/web
else
  echo "→ no GOOGLE_MAPS_KEY set; shipping the drawn map"
fi

# The design prototype rides along as a plain file, so there is one link that
# shows the current thinking without needing the whole app to be finished.
cp prototype/closer.html build/web/prototype.html

echo "→ built $(du -sh build/web | cut -f1) into build/web"
