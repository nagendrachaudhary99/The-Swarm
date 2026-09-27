#!/usr/bin/env bash
# Configure the auth emails used by the current Swarm authentication flow.
#
# The app now uses:
#   1. OAuth 2.0 (Google)
#   2. Email + password signup/sign-in
#   3. Password recovery
#
# Magic-link / email-OTP login is no longer used, so this script does NOT
# configure the magic-link template.
#
# Two email templates matter:
#
#   confirmation
#     Sent after email/password signup when email confirmation is enabled.
#
#   recovery
#     Sent when the user taps "Forgot password?" and the app calls
#     resetPasswordForEmail().
#
# Both use {{ .ConfirmationURL }} so Supabase can verify the action and then
# return the user to the redirect URL supplied by the Flutter app.
#
# Usage:
#   SUPABASE_ACCESS_TOKEN=sbp_... bash scripts/set-auth-emails.sh
#
# Optional:
#   SUPABASE_PROJECT_REF=your-project-ref \
#   SUPABASE_ACCESS_TOKEN=sbp_... \
#   bash scripts/set-auth-emails.sh
#
# The access token is a Supabase personal access token:
#   https://supabase.com/dashboard/account/tokens
#
# It is a full-account credential:
#   - never commit it
#   - never put it in lib/
#   - never expose it to the Flutter client

set -euo pipefail

# shellcheck source=scripts/_env.sh
. "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

REF="${SUPABASE_PROJECT_REF:-bocxxdktggogogsrhhss}"
: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN (https://supabase.com/dashboard/account/tokens)}"

read -r -d '' CONFIRMATION_BODY <<'HTML' || true
<div style="background:#05080e;color:#cfe6ea;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;padding:40px 28px;text-align:center">
  <div style="font-size:11px;letter-spacing:4px;color:#5b7480">THE SWARM</div>

  <p style="font-family:Georgia,serif;font-size:15px;color:#8fa6ae;margin:22px 0 26px">
    Confirm your college email to finish creating your account.
  </p>

  <a
    href="{{ .ConfirmationURL }}"
    style="display:inline-block;padding:14px 22px;border:1px solid #4f8590;border-radius:10px;color:#a0e1eb;text-decoration:none;font-size:12px;letter-spacing:2px;font-weight:700"
  >
    CONFIRM EMAIL
  </a>

  <p style="font-size:11px;color:#5b7480;margin-top:30px;line-height:1.6">
    If you did not create a Swarm account, you can ignore this email.
  </p>
</div>
HTML

read -r -d '' RECOVERY_BODY <<'HTML' || true
<div style="background:#05080e;color:#cfe6ea;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;padding:40px 28px;text-align:center">
  <div style="font-size:11px;letter-spacing:4px;color:#5b7480">THE SWARM</div>

  <p style="font-family:Georgia,serif;font-size:15px;color:#8fa6ae;margin:22px 0 26px">
    Reset the password for your Swarm account.
  </p>

  <a
    href="{{ .ConfirmationURL }}"
    style="display:inline-block;padding:14px 22px;border:1px solid #4f8590;border-radius:10px;color:#a0e1eb;text-decoration:none;font-size:12px;letter-spacing:2px;font-weight:700"
  >
    RESET PASSWORD
  </a>

  <p style="font-size:11px;color:#5b7480;margin-top:30px;line-height:1.6">
    If you did not request a password reset, you can ignore this email.
  </p>
</div>
HTML

payload() {
  python3 -c 'import json,sys
print(json.dumps({
  "mailer_subjects_confirmation": "Confirm your Swarm account",
  "mailer_templates_confirmation_content": sys.argv[1],
  "mailer_subjects_recovery": "Reset your Swarm password",
  "mailer_templates_recovery_content": sys.argv[2],
}))' "$CONFIRMATION_BODY" "$RECOVERY_BODY"
}

echo "→ patching password-auth email templates on $REF"

response="$(
  curl -sS -X PATCH "https://api.supabase.com/v1/projects/$REF/config/auth" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(payload)"
)"

printf '%s' "$response" | python3 -c 'import json,sys
d=json.load(sys.stdin)

if "message" in d:
    sys.exit("✗ " + str(d["message"]))

print("✓ confirmation template configured for email/password signup")
print("✓ recovery template configured for password reset")
print("✓ magic-link / email-OTP template left unused and untouched")
'
