# Load credentials from .env.local, quietly.
#
# Sourced by the other scripts, never run on its own. A secret typed at a
# prompt or passed on a command line ends up in shell history and scrollback;
# one read from a gitignored file does not. Nothing here echoes what it loads.
# shellcheck shell=bash

set +x   # tracing would put every value below into the log

_swarm_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$_swarm_root/.env.local" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$_swarm_root/.env.local"
  set +a
fi
