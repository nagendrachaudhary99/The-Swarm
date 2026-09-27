#!/usr/bin/env bash
# Set a password for an existing account, without sending any mail.
#
# Why this exists: password recovery is the one thing left in this project that
# needs an email server, and a free Supabase project does not have one — the
# recovery endpoint answers 500 "Error sending recovery email" and no amount of
# retrying changes that. Until custom SMTP is configured, an account whose
# password is forgotten is simply lost, which during a pilot means a person is
# locked out of their own whispers for no good reason.
#
# This writes a bcrypt hash straight into auth.users, which is exactly what
# GoTrue would have written itself at the end of a recovery flow.
#
# Usage — put BOTH values in .env.local rather than on the command line, so the
# password never lands in shell history:
#
#     RESET_EMAIL=you@yourcollege.edu
#     RESET_PASSWORD=whatever-you-want-it-to-be
#
# then:  bash scripts/set-password.sh
#
# Delete those two lines again afterwards. This is an admin tool for a pilot,
# not part of the product: there is deliberately no way to reach it from the
# app, because an app that can set anyone's password is not an app with a
# password on it.

set -euo pipefail

# shellcheck source=scripts/_env.sh
. "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN in .env.local}"
: "${RESET_EMAIL:?set RESET_EMAIL in .env.local}"
: "${RESET_PASSWORD:?set RESET_PASSWORD in .env.local}"

if [ "${#RESET_PASSWORD}" -lt 8 ]; then
  echo "x RESET_PASSWORD must be at least 8 characters" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

# Single-quote escaping for the SQL literal: a password containing an
# apostrophe is a perfectly ordinary password and must not become a syntax
# error, let alone an injection.
esc() { printf '%s' "$1" | sed "s/'/''/g"; }
E="$(esc "$RESET_EMAIL")"
P="$(esc "$RESET_PASSWORD")"

echo "→ setting password for $RESET_EMAIL"

bash scripts/db.sh "
update auth.users
   set encrypted_password = extensions.crypt('$P', extensions.gen_salt('bf')),
       -- An account created while confirmations were on may never have been
       -- confirmed, and cannot be: the mail cannot be sent. Setting a password
       -- by hand here is a stronger proof than a clicked link would have been.
       email_confirmed_at = coalesce(email_confirmed_at, now()),
       updated_at = now()
 where email = lower('$E');

select email, email_confirmed_at is not null as confirmed
  from auth.users where email = lower('$E');
" | python3 -c '
import json, sys
rows = json.load(sys.stdin)
if isinstance(rows, dict) and "message" in rows:
    sys.exit("   x " + str(rows["message"]))
if not rows:
    sys.exit("   x no account with that address. Check the spelling, or just\n"
             "     sign up with it in the app — signing up needs no email.")
for r in rows:
    print("   ✓ %s  confirmed=%s" % (r["email"], r["confirmed"]))
print("   Sign in with the new password. Remove RESET_* from .env.local now.")
'
