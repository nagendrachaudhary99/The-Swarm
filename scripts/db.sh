#!/usr/bin/env bash
# Run SQL against the project, through the Management API.
#   SUPABASE_ACCESS_TOKEN=sbp_... bash scripts/db.sh "select 1"
#   SUPABASE_ACCESS_TOKEN=sbp_... bash scripts/db.sh -f supabase/005_rooms.sql
set -euo pipefail

# shellcheck source=scripts/_env.sh
. "$(dirname "${BASH_SOURCE[0]}")/_env.sh"
REF="${SUPABASE_PROJECT_REF:-bocxxdktggogogsrhhss}"
: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN}"

if [ "${1:-}" = "-f" ]; then SQL="$(cat "$2")"; else SQL="${1:?pass SQL or -f file}"; fi

umask 077
TMP="$(mktemp "${TMPDIR:-/tmp}/swarm-q.XXXXXXXX")"
trap 'rm -f "$TMP"' EXIT INT TERM

python3 -c 'import json,sys; print(json.dumps({"query": sys.stdin.read()}))' <<< "$SQL" > "$TMP"
curl -sS -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" -d @"$TMP"
