#!/usr/bin/env bash
#
# Superset RUN script — triggered by the Run button (restartable, in its own
# terminal pane). Starts both dev servers via the root "dev" script, which
# runs them together with concurrently:
#
#   - Express API → http://localhost:3001/api
#   - Vite client → http://localhost:3000  (proxies /api to the API)
#
# Note: the ports are fixed (3001 API, 3000 client), so only one workspace
# can run at a time. Stop another workspace's servers before starting these.

set -euo pipefail

cd "${SUPERSET_WORKSPACE_PATH:-$(git rev-parse --show-toplevel)}"

# Safety net in case Run is pressed before setup finished installing deps.
if [ ! -d node_modules ]; then
  echo "[run] node_modules missing — installing dependencies first…"
  npm install
fi

exec npm run dev
