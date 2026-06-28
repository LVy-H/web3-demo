#!/usr/bin/env bash
# Tessera one-command LOCAL demo (2026-06-19 redesign — self-hosted bulletin board).
#
# Brings up the WHOLE product on localhost with no cloud, no wallet, no account:
#   • the self-hosted server (codes/server) — the verifiable ballot log + read API
#   • the Flutter web client (codes/app/apps/tessera) — create → vote → close →
#     publish → verify, driving that live server
#
#   ./demo.sh up      build the web client, start the server, serve the client,
#                     print the URLs + the admin (convener) token
#   ./demo.sh down    stop everything this script started
#   ./demo.sh status  are the server + web both live?
#   ./demo.sh build   build the web client and copy it into site/demo/ so the
#                     static marketing SITE can host the real app alongside it
#                     (site/demo/ is a heavy CanvasKit artifact — gitignored)
#
# Ports (override via env): SERVER_PORT=3001  WEB_PORT=8080
# The web build is pinned at SERVER_URL=http://127.0.0.1:$SERVER_PORT so the app
# talks to the local server out of the box. Re-point it anytime in-app:
#   Settings → Network → Server URL (+ paste the admin token shown on `up`).
set -euo pipefail

# ── Re-exec inside the Nix devShell when the Flutter/Node toolchain is absent ──
# `flutter` lives only in the devShell; `node` is usually on PATH but we force the
# shell when either is missing so a clean checkout still works in one command.
if [ -z "${TESSERA_IN_DEVSHELL:-}" ] && ! command -v flutter >/dev/null 2>&1; then
  if command -v nix >/dev/null 2>&1 && [ -f "$(dirname "${BASH_SOURCE[0]}")/flake.nix" ]; then
    echo "==> entering Nix devShell (flutter not on PATH)…"
    exec env TESSERA_IN_DEVSHELL=1 nix develop "$(dirname "${BASH_SOURCE[0]}")" --command bash "${BASH_SOURCE[0]}" "$@"
  fi
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="$ROOT/codes/server"
APP="$ROOT/codes/app/apps/tessera"
WEB_BUILD="$APP/build/web"
SITE_DEMO="$ROOT/site/demo"

SERVER_PORT="${SERVER_PORT:-3001}"
WEB_PORT="${WEB_PORT:-8080}"
SERVER_URL="http://127.0.0.1:${SERVER_PORT}"

SERVER_LOG=/tmp/tessera-demo-server.log
SERVER_PID=/tmp/tessera-demo-server.pid
WEB_PID=/tmp/tessera-demo-web.pid
DATA_DIR="${DATA_DIR:-$ROOT/.demo-data}"

server_alive() { curl -s --max-time 3 "${SERVER_URL}/health" >/dev/null 2>&1; }
web_alive()    { curl -s --max-time 3 -o /dev/null "http://127.0.0.1:${WEB_PORT}/index.html"; }

# Build the Flutter web client, pinned at the local server URL. Idempotent-ish:
# rebuilds every time so a code change is reflected; cheap on a warm pub cache.
build_web() {
  command -v flutter >/dev/null 2>&1 || { echo "ERROR: flutter not found (run inside the Nix devShell)" >&2; exit 1; }
  echo "==> Building Flutter web client (SERVER_URL=${SERVER_URL}) …"
  ( cd "$APP" && flutter build web --dart-define=SERVER_URL="${SERVER_URL}" )
  echo "    built → $WEB_BUILD"
}

# Copy the built web bundle into site/demo/ so the static SITE hosts the real app.
sync_site_demo() {
  [ -f "$WEB_BUILD/index.html" ] || { echo "ERROR: no web build at $WEB_BUILD — run a build first" >&2; exit 1; }
  rm -rf "$SITE_DEMO"
  mkdir -p "$SITE_DEMO"
  cp -R "$WEB_BUILD/." "$SITE_DEMO/"
  echo "    copied web bundle → site/demo/ ($(du -sh "$SITE_DEMO" | cut -f1))"
}

start_server() {
  if server_alive; then echo "    server already healthy on :${SERVER_PORT}"; return; fi
  if [ ! -d "$SERVER/node_modules" ]; then
    echo "==> Installing server deps"
    ( cd "$SERVER" && npm install )
  fi
  if [ ! -f "$SERVER/dist/index.js" ]; then
    echo "==> Building server (tsc → dist/)"
    ( cd "$SERVER" && npm run build )
  fi
  mkdir -p "$DATA_DIR"
  echo "==> Starting server on :${SERVER_PORT} (data: $DATA_DIR, log: $SERVER_LOG)"
  ( cd "$SERVER" && setsid env PORT="$SERVER_PORT" DATA_DIR="$DATA_DIR" node dist/index.js \
      >"$SERVER_LOG" 2>&1 </dev/null & echo $! >"$SERVER_PID" )
  echo -n "    waiting for /health"
  for _ in $(seq 1 30); do server_alive && { echo " ok"; break; }; echo -n "."; sleep 1; done
  if ! server_alive; then echo " FAILED — see $SERVER_LOG" >&2; exit 1; fi
}

# Serve the built web bundle with whatever static server is available, no install.
start_web() {
  [ -f "$WEB_BUILD/index.html" ] || build_web
  if web_alive; then echo "    web already served on :${WEB_PORT}"; return; fi
  echo "==> Serving web client on :${WEB_PORT} (root: $WEB_BUILD)"
  if command -v python3 >/dev/null 2>&1; then
    ( cd "$WEB_BUILD" && setsid python3 -m http.server "$WEB_PORT" --bind 127.0.0.1 \
        >/tmp/tessera-demo-web.log 2>&1 </dev/null & echo $! >"$WEB_PID" )
  elif command -v npx >/dev/null 2>&1; then
    ( setsid npx --yes serve -l "$WEB_PORT" "$WEB_BUILD" \
        >/tmp/tessera-demo-web.log 2>&1 </dev/null & echo $! >"$WEB_PID" )
  else
    echo "ERROR: need python3 or npx to serve the web bundle" >&2; exit 1
  fi
  echo -n "    waiting for /index.html"
  for _ in $(seq 1 20); do web_alive && { echo " ok"; break; }; echo -n "."; sleep 1; done
  if ! web_alive; then echo " FAILED — see /tmp/tessera-demo-web.log" >&2; exit 1; fi
}

# The admin (convener) token the server prints once on a fresh DATA_DIR. Grep the
# server log; on a re-used DATA_DIR it was printed on the FIRST boot only.
print_token() {
  local tok
  tok="$(grep -m1 'ADMIN TOKEN' "$SERVER_LOG" 2>/dev/null | sed 's/.*shown once): //')"
  if [ -n "$tok" ]; then
    echo "  admin token   $tok"
  else
    echo "  admin token   (already issued — wipe $DATA_DIR for a fresh one, or check $SERVER_LOG)"
  fi
}

up() {
  start_server
  start_web
  echo ""
  echo "  ── Tessera demo is live ─────────────────────────────────────────"
  echo "  web app       http://127.0.0.1:${WEB_PORT}/"
  echo "  server API    ${SERVER_URL}/health"
  print_token
  echo "  ─────────────────────────────────────────────────────────────────"
  echo "  In the app: Settings → Network → paste the admin token to convene."
  echo "  Stop with:  ./demo.sh down"
}

down() {
  for pidfile in "$WEB_PID" "$SERVER_PID"; do
    if [ -f "$pidfile" ]; then
      kill "$(cat "$pidfile")" 2>/dev/null || true
      rm -f "$pidfile"
    fi
  done
  # Belt-and-braces: kill any stragglers bound to our ports.
  pkill -f "http.server ${WEB_PORT}" 2>/dev/null || true
  echo "stopped server + web"
}

status() {
  server_alive && echo "server: healthy (${SERVER_URL}/health)" || echo "server: down"
  web_alive    >/dev/null 2>&1 && echo "web:    serving (http://127.0.0.1:${WEB_PORT}/)" || echo "web:    down"
}

case "${1:-}" in
  up)     up ;;
  down)   down ;;
  status) status ;;
  build)  build_web; sync_site_demo ;;
  *) echo "usage: $0 {up|down|status|build}" >&2; exit 1 ;;
esac
