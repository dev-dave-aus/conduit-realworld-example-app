#!/usr/bin/env bash
#
# Superset SETUP script — runs automatically when a workspace is created.
#
#   1. Installs npm dependencies for the backend + frontend workspaces.
#   2. Provisions backend/.env (copied from the root repo if available,
#      otherwise generated from backend/.env.example).
#   3. Gives this workspace its own database so parallel workspaces don't
#      collide, then creates it and runs migrations + seeders.
#   4. Assigns this workspace its own backend/frontend ports so parallel
#      worktrees can run their dev servers at the same time.
#
# Superset may provide these environment variables (each optional — the script
# falls back when one is absent):
#   SUPERSET_ROOT_PATH       path to the root repository
#   SUPERSET_WORKSPACE_PATH  path to this workspace's worktree
#
# Note: Superset does NOT export a workspace *name*. Each workspace lives in its
# own git worktree, so we derive a stable per-workspace database identifier from
# the worktree directory instead (see below).

set -euo pipefail

log()  { printf '\033[0;34m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[setup] warning:\033[0m %s\n' "$*" >&2; }

# Run from the workspace root regardless of where this script was invoked.
cd "${SUPERSET_WORKSPACE_PATH:-$(git rev-parse --show-toplevel)}"

# ---------------------------------------------------------------------------
# 1. Dependencies (npm workspaces installs backend + frontend together)
# ---------------------------------------------------------------------------
log "Installing npm dependencies…"
npm install

# ---------------------------------------------------------------------------
# 2. Backend environment file
# ---------------------------------------------------------------------------
ENV_FILE="backend/.env"
ROOT_ENV="${SUPERSET_ROOT_PATH:-}/backend/.env"

if [ -f "$ENV_FILE" ]; then
  log "Reusing existing $ENV_FILE."
elif [ -n "${SUPERSET_ROOT_PATH:-}" ] && [ -f "$ROOT_ENV" ]; then
  log "Copying backend/.env from the root repository."
  cp "$ROOT_ENV" "$ENV_FILE"
else
  warn "No root backend/.env found — generating one from backend/.env.example."
  cp backend/.env.example "$ENV_FILE"
fi

# This project only installs the postgres driver (pg / pg-hstore), and the
# server we start below is Homebrew Postgres, whose default superuser is the
# current OS user with local trust auth (no password). The upstream example and
# repo .env still ship with mysql + placeholder creds (root / null), which can't
# work here — sequelize-cli would just demand mysql2 and fail. So regardless of
# where the .env above came from (generated, copied, or pre-existing), if it
# isn't already postgres, rewrite the connection settings to match the local
# server. A .env that is already postgres is left untouched, preserving any real
# credentials the user configured.
if grep -E '^[A-Z]+_DB_DIALECT=' "$ENV_FILE" | grep -qvE '=postgres$'; then
  PG_USER="$(whoami)"
  sed -i.bak -E \
    -e 's/^([A-Z]+_DB_DIALECT)=.*/\1=postgres/' \
    -e "s/^([A-Z]+_DB_USERNAME)=.*/\1=${PG_USER}/" \
    -e 's/^([A-Z]+_DB_PASSWORD)=.*/\1=/' \
    "$ENV_FILE"
  rm -f "$ENV_FILE.bak"
  warn "Set $ENV_FILE to local Postgres defaults (dialect=postgres, user=${PG_USER}, no password)."
  warn "Edit it if your database uses different credentials, then re-run setup."
fi

# Derive a safe, per-workspace database identifier. Superset doesn't reliably
# export a workspace name, but we've already cd'd into this workspace's own
# worktree above, so the directory basename is a stable, unique per-workspace
# identifier. (SUPERSET_WORKSPACE_NAME is honored if it ever is set.)
# Lowercase and collapse non-alphanumerics to single underscores.
WS="${SUPERSET_WORKSPACE_NAME:-$(basename "$PWD")}"
SLUG="$(printf '%s' "$WS" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_' '_' | sed -E 's/_+/_/g; s/^_//; s/_$//')"
[ -z "$SLUG" ] && SLUG="default"

DEV_DB="conduit_dev_${SLUG}"
TEST_DB="conduit_test_${SLUG}"

log "Using per-workspace databases: dev=$DEV_DB test=$TEST_DB"
sed -i.bak -E "s/^DEV_DB_NAME=.*/DEV_DB_NAME=${DEV_DB}/"   "$ENV_FILE"
sed -i.bak -E "s/^TEST_DB_NAME=.*/TEST_DB_NAME=${TEST_DB}/" "$ENV_FILE"
rm -f "$ENV_FILE.bak"

# ---------------------------------------------------------------------------
# 2b. Per-workspace HTTP ports
#
# The backend (Express, $PORT) and the frontend (Vite dev server,
# $FRONTEND_PORT) default to 3001/3000. Workspaces run in parallel worktrees,
# so fixed ports would collide. Give each workspace its own 10-port block,
# skipping any port already declared by a sibling worktree's backend/.env or
# currently listening, and persist the choice so it stays stable across
# re-runs. (frontend/vite.config.js reads these two values back.)
# ---------------------------------------------------------------------------

# Ports declared by OTHER worktrees of this repo (from their backend/.env).
other_worktree_ports() {
  local self="$PWD" wt env_path
  git worktree list --porcelain 2>/dev/null \
    | sed -n 's/^worktree //p' \
    | while IFS= read -r wt; do
        [ "$wt" = "$self" ] && continue
        env_path="$wt/backend/.env"
        [ -f "$env_path" ] || continue
        grep -E '^(PORT|FRONTEND_PORT)=' "$env_path" | sed -E 's/^[A-Z_]+=//'
      done
}

TAKEN_PORTS=" $(other_worktree_ports | tr '\n' ' ' || true) "

# Is $1 claimed by another worktree?
port_claimed() { case "$TAKEN_PORTS" in *" $1 "*) return 0 ;; esac; return 1; }

# Is something currently listening on 127.0.0.1:$1? (mirrors postgres.sh probe)
port_in_use() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
  fi
}

read_env_value() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- ; }

# Replace "$1=…" in place, or append it if the key isn't present yet.
set_env_value() {
  if grep -qE "^$1=" "$ENV_FILE"; then
    sed -i.bak -E "s|^$1=.*|$1=$2|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    # The upstream .env.example has no trailing newline; add one before
    # appending so we don't glue the new key onto the last line.
    { [ -s "$ENV_FILE" ] && [ -n "$(tail -c1 "$ENV_FILE")" ] && printf '\n' >> "$ENV_FILE"; } || true
    printf '%s=%s\n' "$1" "$2" >> "$ENV_FILE"
  fi
}

CUR_BE_PORT="$(read_env_value PORT || true)"
CUR_FE_PORT="$(read_env_value FRONTEND_PORT || true)"

if [ -n "$CUR_BE_PORT" ] && [ -n "$CUR_FE_PORT" ] \
   && ! port_claimed "$CUR_BE_PORT" && ! port_claimed "$CUR_FE_PORT"; then
  # This workspace already has a non-conflicting assignment — keep it stable.
  FRONTEND_PORT="$CUR_FE_PORT"
  BACKEND_PORT="$CUR_BE_PORT"
  log "Keeping this workspace's ports: frontend=$FRONTEND_PORT backend=$BACKEND_PORT"
else
  FRONTEND_PORT=""
  BACKEND_PORT=""
  block=0
  while [ "$block" -le 100 ]; do
    fe=$((3000 + block * 10))
    be=$((3001 + block * 10))
    if ! port_claimed "$fe" && ! port_claimed "$be" \
       && ! port_in_use "$fe" && ! port_in_use "$be"; then
      FRONTEND_PORT="$fe"
      BACKEND_PORT="$be"
      break
    fi
    block=$((block + 1))
  done
  if [ -z "$FRONTEND_PORT" ]; then
    warn "Could not find a free port block; falling back to 3000/3001."
    FRONTEND_PORT=3000
    BACKEND_PORT=3001
  fi
  log "Assigned this workspace ports: frontend=$FRONTEND_PORT backend=$BACKEND_PORT"
fi

set_env_value PORT "$BACKEND_PORT"
set_env_value FRONTEND_PORT "$FRONTEND_PORT"

# ---------------------------------------------------------------------------
# 3. PostgreSQL server — install (via Homebrew) and start if it isn't already.
#    Shared across workspaces. Non-fatal: if it can't be started here, the DB
#    steps below will warn and setup still completes.
# ---------------------------------------------------------------------------
# shellcheck source=.superset/postgres.sh
. .superset/postgres.sh

log "Ensuring a PostgreSQL server is running on ${PG_HOST}:${PG_PORT}…"
if pg_ensure_installed_and_running; then
  log "PostgreSQL is up."
else
  warn "Could not start PostgreSQL automatically (is Homebrew installed?)."
  warn "Install/start a server on ${PG_HOST}:${PG_PORT}, then re-run setup."
fi

# ---------------------------------------------------------------------------
# 4. Database — create, migrate, seed.
#    Non-fatal: a missing/misconfigured DB server shouldn't block workspace
#    creation. Fix backend/.env and re-run the commands below if it fails.
# ---------------------------------------------------------------------------
provision_db() {
  log "Creating database $DEV_DB (if it doesn't already exist)…"
  npm run sqlz -- db:create || warn "db:create reported an error (it may already exist)."
  log "Running migrations…"
  npm run sqlz -- db:migrate
  log "Seeding demo data…"
  npm run sqlz -- db:seed:all
}

if provision_db; then
  log "Database ready."
else
  warn "Database setup did not finish. Check backend/.env, then run:"
  warn "  npm run sqlz -- db:create && npm run sqlz -- db:migrate && npm run sqlz -- db:seed:all"
fi

log "Setup complete — press Run to start the dev servers."
