#!/usr/bin/env bash
# Switch on whichever OAuth providers you have credentials for.
#
# Replaces set-google-oauth.sh, which only knew about one door. The gate now
# offers Google, GitHub, Discord and Apple, and this turns on whichever of them
# you have actually minted a client for. Providers with no credentials in the
# environment are left completely alone — not disabled, just untouched.
#
#   SUPABASE_ACCESS_TOKEN=sbp_... \
#   GOOGLE_CLIENT_ID=...  GOOGLE_CLIENT_SECRET=... \
#   GITHUB_CLIENT_ID=...  GITHUB_CLIENT_SECRET=... \
#   bash scripts/set-oauth.sh
#
# ─── the part no script can do for you ────────────────────────────────────
#
# Every provider below requires a client created on THAT provider's side,
# against YOUR account. There is no API that mints one on your behalf, which is
# why this has been the blocker rather than anything in the app.
#
# All of them want the same callback registered, and it is Supabase's URL, not
# your app's:
#
#     https://<project-ref>.supabase.co/auth/v1/callback
#
#   Google   console.cloud.google.com → APIs & Services → Credentials
#            → Create credentials → OAuth client ID → Web application
#            Takes about five minutes, including the consent screen.
#
#   GitHub   github.com/settings/developers → New OAuth App
#            The fastest of the four. No review, no consent screen.
#
#   Discord  discord.com/developers/applications → New Application
#            → OAuth2 → add the redirect. Also quick.
#
#   Apple    developer.apple.com → Certificates, Identifiers & Profiles.
#            Needs a PAID developer account and a signed client secret that
#            expires every six months. Leave it last.
#
# The secrets are full credentials for those apps: never commit them, never put
# them in lib/, never hand them to the client.

set -euo pipefail

# shellcheck source=scripts/_env.sh
. "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

REF="${SUPABASE_PROJECT_REF:-bocxxdktggogogsrhhss}"
: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN (https://supabase.com/dashboard/account/tokens)}"

echo "   callback to register with every provider:"
echo "   https://$REF.supabase.co/auth/v1/callback"
echo

# Build a PATCH body out of whichever pairs are actually present. An absent
# provider contributes no keys at all, so re-running this never switches off a
# door somebody enabled in the dashboard by hand.
BODY="$(python3 -c '
import json, os, sys

providers = ["google", "github", "discord", "apple"]
body, on, skipped = {}, [], []

for p in providers:
    cid = os.environ.get(p.upper() + "_CLIENT_ID", "").strip()
    sec = os.environ.get(p.upper() + "_CLIENT_SECRET", "").strip()
    if cid and sec:
        body["external_%s_enabled" % p] = True
        body["external_%s_client_id" % p] = cid
        body["external_%s_secret" % p] = sec
        on.append(p)
    elif cid or sec:
        sys.exit("   x %s: has an id or a secret but not both" % p)
    else:
        skipped.append(p)

if not body:
    sys.exit("   x no provider credentials found in the environment.\n"
             "     Set at least GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET,\n"
             "     or see the header of this script for where to get them.")

print(json.dumps({"body": body, "on": on, "skipped": skipped}))
')"

python3 -c '
import json, sys
d = json.loads(sys.argv[1])
print("   enabling: " + ", ".join(d["on"]))
if d["skipped"]:
    print("   skipped (no credentials, left untouched): " + ", ".join(d["skipped"]))
' "$BODY"

# A predictable path in a shared /tmp is a file anyone on the box can read,
# and this one holds OAuth client secrets. mktemp + umask 077 makes it
# unguessable and unreadable; the trap means it goes even on a failed curl.
umask 077
TMP="$(mktemp "${TMPDIR:-/tmp}/swarm-oauth.XXXXXXXX")"
trap 'rm -f "$TMP"' EXIT INT TERM

python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["body"]))' \
  "$BODY" > "$TMP"

curl -sS -X PATCH "https://api.supabase.com/v1/projects/$REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @"$TMP" \
  | python3 -c '
import json, sys
d = json.load(sys.stdin)
if "message" in d:
    sys.exit("   x " + str(d["message"]))
for p in ("google", "github", "discord", "apple"):
    if d.get("external_%s_enabled" % p):
        cid = d.get("external_%s_client_id" % p) or ""
        print("   ✓ %-8s on   %s" % (p, cid[:30] + ("..." if len(cid) > 30 else "")))
'

