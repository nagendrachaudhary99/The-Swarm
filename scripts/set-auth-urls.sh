#!/usr/bin/env bash
# Point Supabase at the app instead of at a dead port.
#
# A project ships with Site URL = http://localhost:3000 and an empty redirect
# allow list. Every link Supabase mails lands there, so you click it, the token
# is spent, and you arrive at nothing. The app names its own redirect (see
# SwarmApi._redirectTo) but Supabase silently ignores any origin that is not on
# this list, and falls back to the Site URL — which is the dead port again.
#
# Usage:
#   SUPABASE_ACCESS_TOKEN=sbp_... bash scripts/set-auth-urls.sh

set -euo pipefail

umask 077
TMP="$(mktemp "${TMPDIR:-/tmp}/swarm-urls.XXXXXXXX")"
trap 'rm -f "$TMP"' EXIT INT TERM

# shellcheck source=scripts/_env.sh
. "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

REF="${SUPABASE_PROJECT_REF:-bocxxdktggogogsrhhss}"
APP="${APP_ORIGIN:-https://the-swarm-chi.vercel.app}"
: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN (https://supabase.com/dashboard/account/tokens)}"

# Preview deployments get a fresh hostname every push, so the wildcard matters
# as much as the production one. `closer://` is the mobile deep link.
python3 -c 'import json,sys
app = sys.argv[1]
print(json.dumps({
  "site_url": app,
  "uri_allow_list": ",".join([
    app, app + "/**",
    "https://*-nagendra-chaudharys-projects.vercel.app/**",
    "http://localhost:*/**",
    "closer://auth-callback",
  ]),
}))' "$APP" > "$TMP"

echo "→ pointing $REF at $APP"
curl -sS -X PATCH "https://api.supabase.com/v1/projects/$REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @"$TMP" \
  | python3 -c 'import json,sys
d = json.load(sys.stdin)
if "message" in d: sys.exit("✗ " + str(d["message"]))
print("✓ site_url       ", d.get("site_url"))
print("✓ uri_allow_list ", d.get("uri_allow_list"))'
