#!/usr/bin/env bash
#
# Superset TEARDOWN script — runs automatically when a workspace is deleted.
#
# Drops the per-workspace development database created during setup so stale
# databases don't pile up on the server. Best-effort: errors are logged but
# never abort deletion (Superset still offers "Delete Anyway" on failure).

set -uo pipefail

log()  { printf '\033[0;34m[teardown]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[teardown] warning:\033[0m %s\n' "$*" >&2; }

cd "${SUPERSET_WORKSPACE_PATH:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"

if [ ! -f backend/.env ]; then
  log "No backend/.env — nothing to tear down."
  exit 0
fi

log "Dropping this workspace's development database…"
npm run sqlz -- db:drop || warn "Could not drop the database (already gone, or DB server unreachable)."

log "Teardown complete."
