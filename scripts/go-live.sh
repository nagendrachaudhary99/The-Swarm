#!/usr/bin/env bash
# Everything the project needs before two people can sign up and whisper.
#
# The pieces were already here as separate scripts; what was missing was the
# order and the one setting nobody thinks of until signup silently fails on a
# free project: email confirmation.
#
#   SUPABASE_ACCESS_TOKEN=sbp_... bash scripts/go-live.sh
#
# Optional, and only if you have made the client in Google Cloud:
#   GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=... bash scripts/go-live.sh
#
# The token is a personal access token from
# https://supabase.com/dashboard/account/tokens — a full-account credential.
# Never commit it, never put it in lib/, never hand it to the client.
#
# Safe to run twice. Every migration is written with `if not exists` and
# `create or replace`, and the auth settings are idempotent PATCHes.

set -euo pipefail

REF="${SUPABASE_PROJECT_REF:-bocxxdktggogogsrhhss}"
APP="${APP_ORIGIN:-https://the-swarm-chi.vercel.app}"
: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN (https://supabase.com/dashboard/account/tokens)}"

cd "$(dirname "$0")/.."

api() {
  curl -sS -X "$1" "https://api.supabase.com/v1/projects/$REF$2" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    ${3:+-d "$3"}
}

echo "→ project $REF"
echo

# ---------------------------------------------------------------- 1. schema
# In order. Each one assumes the last has run: 002 turns every user column to
# text, 004 closes leaks 003 opened, 006 replaces the sweep 005 defined.
echo "── applying migrations ──────────────────────────────"
for f in supabase/schema.sql \
         supabase/002_clerk_identity.sql \
         supabase/003_safety.sql \
         supabase/004_close_id_leaks.sql \
         supabase/005_rooms.sql \
         supabase/006_hunts.sql; do
  printf '   %-32s ' "$(basename "$f")"
  out="$(bash scripts/db.sh -f "$f" 2>&1)" || { echo "FAILED"; echo "$out"; exit 1; }
  if printf '%s' "$out" | grep -q '"message"'; then
    echo "FAILED"; printf '%s\n' "$out"; exit 1
  fi
  echo "ok"
done
echo

# ------------------------------------------------------------------ 2. mail
# The setting that decides whether your friend can get in tonight.
#
# With confirmation ON, signup creates a user with NO session and waits for an
# email — and a free project's default mailer only reaches your own team, twice
# an hour. Everyone else gets a spinner and then nothing, which reads as "the
# app is broken" rather than "check your inbox".
#
# OFF means signup returns a session immediately. The gate is still the campus
# domain (SwarmApi.isCampusEmail), which is the membership test that actually
# matters here — a confirmed mailbox was never the thing being checked.
echo "── auth: no mail in the signup path ─────────────────"
api PATCH /config/auth '{"mailer_autoconfirm": true}' \
  | python3 -c 'import json,sys
d = json.load(sys.stdin)
if "message" in d: sys.exit("   ✗ " + str(d["message"]))
print("   ✓ email confirmation off — signup returns a session immediately")'
echo

# ------------------------------------------------------------------ 3. urls
echo "── auth: redirect URLs ──────────────────────────────"
bash scripts/set-auth-urls.sh
echo

# --------------------------------------------------------------- 4. google
if [ -n "${GOOGLE_CLIENT_ID:-}" ] && [ -n "${GOOGLE_CLIENT_SECRET:-}" ]; then
  echo "── auth: google ─────────────────────────────────────"
  bash scripts/set-google-oauth.sh
  echo
else
  echo "── auth: google ─────────────────────────────────────"
  echo "   skipped — no GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET."
  echo "   Email + password works without it. The Google button will not."
  echo
fi

# ---------------------------------------------------------------- 5. verify
# Ask the database to prove the parts that matter are actually there, rather
# than trusting that six HTTP 200s meant what they looked like.
echo "── verifying ────────────────────────────────────────"
bash scripts/db.sh "
select
  (select count(*) from pg_proc  where proname in
     ('hunt_start','hunt_ping','hunt_drop','hunted_state','freeze_signal',
      'spore_drop','spores_near','sweep','post_whisper','beacon_set')) as rpcs,
  (select count(*) from pg_tables where schemaname='public'
     and tablename in ('whispers','beacons','hunts','hunt_alerts','spores')) as tables,
  (select count(*) from pg_publication_tables
     where pubname='supabase_realtime' and tablename='hunt_alerts') as realtime,
  (select count(*) from pg_policies where schemaname='public'
     and tablename='hunts') as hunt_policies
" | python3 -c '
import json, sys

d = json.load(sys.stdin)
if isinstance(d, dict) and "message" in d:
    sys.exit("   x " + str(d["message"]))
r = d[0] if isinstance(d, list) else d

ok = True

def check(label, got, want, exact=False, why=""):
    global ok
    good = (got == want) if exact else (got >= want)
    if not good:
        ok = False
    mark = "✓" if good else "x"
    tail = "" if good else "  (expected %s) %s" % (want, why)
    print("   %s %s: %s%s" % (mark, label, got, tail))

check("hunt + core RPCs", r["rpcs"], 10)
check("tables", r["tables"], 5)
check("hunt_alerts in realtime publication", r["realtime"], 1,
      why="- the socket cannot deliver without this")

# Zero is CORRECT here, and is the reason for the check: `hunts` holds both
# the hunter and the quarry, so there is no column subset a client may read.
check("hunts RLS policies (must be 0)", r["hunt_policies"], 0, exact=True,
      why="- both ids live in that table")

sys.exit(0 if ok else "   x verification failed")'

echo
echo "────────────────────────────────────────────────────────"
echo "Ready. Sign up at $APP with any email and a password."
echo
echo "Two phones, two accounts, stand apart, PING. The band is"
echo "the distance; inside ten metres it says MIRAGE and stops."
