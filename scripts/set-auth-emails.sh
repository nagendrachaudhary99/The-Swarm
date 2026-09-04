#!/usr/bin/env bash
# Make the login mail carry a six-digit CODE instead of a link.
#
# Supabase ships both auth templates with only {{ .ConfirmationURL }} in them,
# so the mail is a link — clicking it spends the token and lands on the Site
# URL, and there is no code to type into the gate. A template that contains
# {{ .Token }} makes the server put the digits in the mail as well.
#
# Two templates matter, because Supabase picks between them by whether the
# address is new:
#   confirmation → first ever login for that address
#   magic link   → every login after that
# Editing only one is why "it works for me but not for them".
#
# Usage:
#   SUPABASE_ACCESS_TOKEN=sbp_... bash scripts/set-auth-emails.sh
#
# The token is a personal access token from https://supabase.com/dashboard/account/tokens
# It is a full-account credential: never commit it, never put it in lib/.

set -euo pipefail

REF="${SUPABASE_PROJECT_REF:-bocxxdktggogogsrhhss}"
: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN (https://supabase.com/dashboard/account/tokens)}"

read -r -d '' BODY <<'HTML' || true
<div style="background:#05080e;color:#cfe6ea;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;padding:40px 28px;text-align:center">
  <div style="font-size:11px;letter-spacing:4px;color:#5b7480">THE SWARM</div>
  <p style="font-family:Georgia,serif;font-size:15px;color:#8fa6ae;margin:22px 0 26px">
    Type this into the gate. It lasts one hour.
  </p>
  <div style="font-size:34px;letter-spacing:10px;color:#a0e1eb;font-weight:700">{{ .Token }}</div>
  <p style="font-size:11px;color:#5b7480;margin-top:30px">
    If you did not ask for this, nothing has happened — ignore it.
  </p>
</div>
HTML

payload() { python3 -c 'import json,sys;print(json.dumps({
  "mailer_subjects_confirmation": "Your Swarm code",
  "mailer_templates_confirmation_content": sys.argv[1],
  "mailer_subjects_magic_link": "Your Swarm code",
  "mailer_templates_magic_link_content": sys.argv[1],
}))' "$BODY"; }

echo "→ patching auth email templates on $REF"
curl -sS -X PATCH "https://api.supabase.com/v1/projects/$REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(payload)" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
if "message" in d: sys.exit("✗ " + str(d["message"]))
print("✓ both templates now carry {{ .Token }} — the next mail is a code")'
