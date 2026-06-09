import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react-swc'
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

// Follow the per-workspace ports that .superset/setup.sh writes into
// backend/.env so parallel worktrees don't collide. An actual environment
// variable wins if present; otherwise fall back to the upstream defaults.
function readEnvFile(path) {
  const out = {}
  try {
    for (const line of readFileSync(path, 'utf8').split('\n')) {
      const trimmed = line.trim()
      if (!trimmed || trimmed.startsWith('#')) continue
      const eq = trimmed.indexOf('=')
      if (eq === -1) continue
      out[trimmed.slice(0, eq).trim()] = trimmed.slice(eq + 1).trim()
    }
  } catch {
    // No backend/.env yet (e.g. before setup) — defaults below apply.
  }
  return out
}

const backendEnv = readEnvFile(resolve(here, '../backend/.env'))
const frontendPort = Number(process.env.FRONTEND_PORT || backendEnv.FRONTEND_PORT || 3000)
const backendPort = Number(process.env.PORT || backendEnv.PORT || 3001)

export default defineConfig({
  plugins: [react()],
  server: {
    port: frontendPort,
    proxy: {
      '/api': {
        target: `http://localhost:${backendPort}`,
      },
    },
  },
})
