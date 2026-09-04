#!/usr/bin/env bash
# Turn on Google sign-in for the project.
#
# Why this door exists: a free Supabase project cannot put a six-digit code in
# an email — template edits are refused unless custom SMTP is configured — and
# the default mailer only reaches your own team, twice an hour. OAuth sends no
# mail at all, so none of that applies to it.
#
# Before running, create the client in Google Cloud (see README-auth notes):
#   APIs & Services → Credentials → Create credentials → OAuth client ID
#   Type: Web application
#   Authorised redirect URI (exactly this, it is Supabase's, not yours):
#     https://<ref>.supabase.co/auth/v1/callback
#
# Usage:
#   SUPABASE_ACCESS_TOKEN=sbp_... \
#   GOOGLE_CLIENT_ID=....apps.googleusercontent.com \
#   GOOGLE_CLIENT_SECRET=GOCSPX-... \
#   bash scripts/set-google-oauth.sh

set -euo pipefail

REF="${SUPABASE_PROJECT_REF:-bocxxdktggogogsrhhss}"
: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN}"
: "${GOOGLE_CLIENT_ID:?set GOOGLE_CLIENT_ID}"
: "${GOOGLE_CLIENT_SECRET:?set GOOGLE_CLIENT_SECRET}"

python3 -c 'import json,os
print(json.dumps({
  "external_google_enabled": True,
  "external_google_client_id": os.environ["GOOGLE_CLIENT_ID"],
  "external_google_secret": os.environ["GOOGLE_CLIENT_SECRET"],
}))' > /tmp/swarm-google.json

echo "→ enabling Google on $REF"
curl -sS -X PATCH "https://api.supabase.com/v1/projects/$REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/swarm-google.json \
  | python3 -c 'import json,sys
d = json.load(sys.stdin)
if "message" in d: sys.exit("✗ " + str(d["message"]))
print("✓ external_google_enabled", d.get("external_google_enabled"))
print("✓ client id              ", (d.get("external_google_client_id") or "")[:28] + "…")'

rm -f /tmp/swarm-google.json
echo "  callback to register in Google Cloud: https://$REF.supabase.co/auth/v1/callback"
