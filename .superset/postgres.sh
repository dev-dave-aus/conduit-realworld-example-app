#!/usr/bin/env bash
#
# Superset PostgreSQL helpers — SOURCED (not executed) by setup.sh / teardown.sh.
#
# The Superset scripts use a single shared Postgres server with one database
# per workspace. This library centralises the "is it up? / bring it up" logic
# so setup and teardown stay in sync. It targets Homebrew-managed Postgres on
# macOS; every function is best-effort and returns non-zero rather than exiting,
# so callers can warn-and-continue.

# Formula installed on demand when no postgresql formula is present yet.
PG_DEFAULT_FORMULA="postgresql@17"
PG_HOST="127.0.0.1"
PG_PORT="5432"

# Echo the brew formula to use: the highest already-installed postgresql
# formula (e.g. postgresql@16), or the default if none is installed.
pg_formula() {
  local installed
  installed="$(brew list --formula 2>/dev/null \
    | grep -E '^postgresql(@[0-9.]+)?$' | sort -V | tail -n1)"
  printf '%s' "${installed:-$PG_DEFAULT_FORMULA}"
}

# Echo the bin dir of the resolved (keg-only) formula, where pg_isready lives.
pg_bin_dir() {
  local prefix
  prefix="$(brew --prefix "$(pg_formula)" 2>/dev/null)" || return 0
  [ -n "$prefix" ] && printf '%s/bin' "$prefix"
}

# Return 0 if a server is accepting connections on PG_HOST:PG_PORT.
pg_ready() {
  local bin; bin="$(pg_bin_dir)"
  if [ -n "$bin" ] && [ -x "$bin/pg_isready" ]; then
    "$bin/pg_isready" -q -h "$PG_HOST" -p "$PG_PORT"
  elif command -v pg_isready >/dev/null 2>&1; then
    pg_isready -q -h "$PG_HOST" -p "$PG_PORT"
  else
    # No client tools available — fall back to a raw TCP probe.
    (exec 3<>"/dev/tcp/$PG_HOST/$PG_PORT") 2>/dev/null
  fi
}

# Poll until the server is ready or <timeout> seconds elapse. Returns 0 if ready.
pg_wait_ready() {
  local timeout="${1:-30}" i=0
  while [ "$i" -lt "$timeout" ]; do
    pg_ready && return 0
    sleep 1
    i=$((i + 1))
  done
  pg_ready
}

# Bring up an ALREADY-INSTALLED brew postgres service, without installing
# anything. Used by teardown so a stopped server can still be dropped from.
pg_ensure_running() {
  pg_ready && return 0
  command -v brew >/dev/null 2>&1 || return 1
  local f; f="$(pg_formula)"
  brew list --formula 2>/dev/null | grep -qx "$f" || return 1
  brew services start "$f" >/dev/null 2>&1 || true
  pg_wait_ready 30
}

# Install (if missing) and start the brew postgres service, then wait for it.
# Used by setup as the one place allowed to install software.
pg_ensure_installed_and_running() {
  pg_ready && return 0
  command -v brew >/dev/null 2>&1 || return 1
  local f; f="$(pg_formula)"
  if ! brew list --formula 2>/dev/null | grep -qx "$f"; then
    brew install "$f" || return 1
  fi
  brew services start "$f" || return 1
  pg_wait_ready 60
}
