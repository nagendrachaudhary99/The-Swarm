#!/usr/bin/env bash
# Run SQL against the project, through the Management API.
#   SUPABASE_ACCESS_TOKEN=sbp_... bash scripts/db.sh "select 1"
#   SUPABASE_ACCESS_TOKEN=sbp_... bash scripts/db.sh -f supabase/005_rooms.sql
set -euo pipefail
REF="${SUPABASE_PROJECT_REF:-bocxxdktggogogsrhhss}"
: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN}"

if [ "${1:-}" = "-f" ]; then SQL="$(cat "$2")"; else SQL="${1:?pass SQL or -f file}"; fi

python3 -c 'import json,sys; print(json.dumps({"query": sys.stdin.read()}))' <<< "$SQL" > /tmp/swarm-q.json
curl -sS -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" -d @/tmp/swarm-q.json
rm -f /tmp/swarm-q.json
