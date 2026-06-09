#!/usr/bin/env bash
#
# Superset SETUP script — runs automatically when a workspace is created.
#
#   1. Installs npm dependencies for the backend + frontend workspaces.
#   2. Provisions backend/.env (copied from the root repo if available,
#      otherwise generated from backend/.env.example).
#   3. Gives this workspace its own database so parallel workspaces don't
#      collide, then creates it and runs migrations + seeders.
#
# Superset provides these environment variables:
#   SUPERSET_ROOT_PATH       path to the root repository
#   SUPERSET_WORKSPACE_NAME  name of the current workspace
#   SUPERSET_WORKSPACE_PATH  path to this workspace's worktree

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
  # The example ships with mysql + placeholder creds (root / null). This project
  # installs the postgres driver (pg / pg-hstore), and the server we start below
  # is Homebrew Postgres, whose default superuser is the current OS user with
  # local trust auth (no password). Default the .env to match so db:create works.
  PG_USER="$(whoami)"
  sed -i.bak -E \
    -e 's/^([A-Z]+_DB_DIALECT)=.*/\1=postgres/' \
    -e "s/^([A-Z]+_DB_USERNAME)=.*/\1=${PG_USER}/" \
    -e 's/^([A-Z]+_DB_PASSWORD)=.*/\1=/' \
    "$ENV_FILE"
  rm -f "$ENV_FILE.bak"
  warn "Generated $ENV_FILE with local Postgres defaults (user=${PG_USER})."
  warn "Edit it if your database uses different credentials, then re-run setup."
fi

# Derive a safe, per-workspace database identifier from the workspace name
# (lowercase, non-alphanumerics collapsed to single underscores).
WS="${SUPERSET_WORKSPACE_NAME:-default}"
SLUG="$(printf '%s' "$WS" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_' '_' | sed -E 's/_+/_/g; s/^_//; s/_$//')"
[ -z "$SLUG" ] && SLUG="default"

DEV_DB="conduit_dev_${SLUG}"
TEST_DB="conduit_test_${SLUG}"

log "Using per-workspace databases: dev=$DEV_DB test=$TEST_DB"
sed -i.bak -E "s/^DEV_DB_NAME=.*/DEV_DB_NAME=${DEV_DB}/"   "$ENV_FILE"
sed -i.bak -E "s/^TEST_DB_NAME=.*/TEST_DB_NAME=${TEST_DB}/" "$ENV_FILE"
rm -f "$ENV_FILE.bak"

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
