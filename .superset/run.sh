#!/usr/bin/env bash
#
# Superset RUN script — triggered by the Run button (restartable, in its own
# terminal pane). Starts both dev servers via the root "dev" script, which
# runs them together with concurrently:
#
#   - Express API → http://localhost:$PORT/api
#   - Vite client → http://localhost:$FRONTEND_PORT  (proxies /api to the API)
#
# The ports are per-workspace: setup.sh assigns each worktree its own pair and
# writes them to backend/.env (PORT for the API, FRONTEND_PORT for the client),
# so parallel workspaces can run their dev servers at the same time.

set -euo pipefail

cd "${SUPERSET_WORKSPACE_PATH:-$(git rev-parse --show-toplevel)}"

# Safety net in case Run is pressed before setup finished installing deps.
if [ ! -d node_modules ]; then
  echo "[run] node_modules missing — installing dependencies first…"
  npm install
fi

# Report this workspace's ports (assigned by setup.sh, read from backend/.env).
be_port="$(grep -E '^PORT=' backend/.env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
fe_port="$(grep -E '^FRONTEND_PORT=' backend/.env 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
echo "[run] API    → http://localhost:${be_port:-3001}/api"
echo "[run] client → http://localhost:${fe_port:-3000}"

exec npm run dev
