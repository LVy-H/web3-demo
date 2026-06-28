#!/usr/bin/env bash
# Local dev stack for Tessera (2026-06-19 redesign).
#
# The old stack (Hardhat chain + relayer + Android-emulator e2e) was removed with
# the on-chain architecture. The new stack is just the self-hosted server
# (codes/server); the Flutter client runs separately via `flutter run`. The server
# is a skeleton today (health route) and this script grows with Phases 2-3.
#
#   ./dev-stack.sh up      start the server (npm run dev) on :3001, wait for /health
#   ./dev-stack.sh down    stop the server this script started
#   ./dev-stack.sh status  is the server healthy?
#
# For the full ONE-COMMAND demo (server + built Flutter web client + admin token),
# use ./demo.sh up — it builds the web app and serves it alongside the server.
set -euo pipefail

# ── Re-exec inside the Nix devShell if the Node toolchain is absent ──
if [ -z "${TESSERA_IN_DEVSHELL:-}" ] && ! command -v node >/dev/null 2>&1; then
  if command -v nix >/dev/null 2>&1 && [ -f "$(dirname "${BASH_SOURCE[0]}")/flake.nix" ]; then
    echo "==> entering Nix devShell (node not on PATH)…"
    exec env TESSERA_IN_DEVSHELL=1 nix develop "$(dirname "${BASH_SOURCE[0]}")" --command bash "${BASH_SOURCE[0]}" "$@"
  fi
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="$ROOT/codes/server"
SERVER_LOG=/tmp/tessera-server.log
SERVER_PID=/tmp/tessera-server.pid
PORT="${PORT:-3001}"

server_alive() { curl -s --max-time 3 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; }

up() {
  if server_alive; then echo "Server already healthy on :${PORT}"; exit 0; fi
  if [ ! -d "$SERVER/node_modules" ]; then
    echo "==> Installing server deps"
    ( cd "$SERVER" && npm install )
  fi
  echo "==> Starting server (log: $SERVER_LOG)"
  ( cd "$SERVER" && setsid env PORT="$PORT" npm run dev >"$SERVER_LOG" 2>&1 </dev/null & echo $! >"$SERVER_PID" )
  echo -n "    waiting for /health"
  for _ in $(seq 1 20); do server_alive && { echo " ok"; break; }; echo -n "."; sleep 1; done
  if ! server_alive; then echo " FAILED — see $SERVER_LOG" >&2; exit 1; fi
  echo "  server   http://127.0.0.1:${PORT}/health"
  echo "  client   run the Flutter app separately:  (cd codes/app/apps/tessera && flutter run)"
}

down() {
  if [ -f "$SERVER_PID" ]; then
    kill "$(cat "$SERVER_PID")" 2>/dev/null || true
    rm -f "$SERVER_PID"
    echo "stopped server"
  else
    echo "no server PID file; nothing to stop"
  fi
}

status() {
  if server_alive; then echo "server: healthy (http://127.0.0.1:${PORT}/health)"; else echo "server: down"; fi
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  status) status ;;
  *) echo "usage: $0 {up|down|status}" >&2; exit 1 ;;
esac
