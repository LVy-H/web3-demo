#!/usr/bin/env bash
# Local full-stack launcher + Android-emulator e2e harness for the zkVote dApp
# (feat/flutter-mobile).
#
#   ./dev-stack.sh up      Hardhat node -> deploy (mock verifier, local) ->
#                          seed one demo poll -> relayer. Logs to /tmp, PIDs to
#                          /tmp/zkvote-*.pid. Returns when ready.
#   ./dev-stack.sh down    stop node + relayer.
#   ./dev-stack.sh status  what's listening (chain / relayer / emulator).
#   ./dev-stack.sh emu      boot the headless KVM Android emulator (AVD auto-created).
#   ./dev-stack.sh emu-kill stop the emulator this script started.
#   ./dev-stack.sh e2e      up + emu + run integration_test on the emulator,
#                           pointed at the host stack via 10.0.2.2. ZK_KEEP=1
#                           leaves the emulator running afterwards.
#
# Everything that needs flutter/adb/emulator/avdmanager runs inside the Nix
# devShell; the script re-execs itself there if those tools aren't on PATH.
set -euo pipefail

# ── Re-exec inside the Nix devShell if the Android/Flutter toolchain is absent ──
if [ -z "${ZK_IN_DEVSHELL:-}" ] && ! command -v flutter >/dev/null 2>&1; then
  if command -v nix >/dev/null 2>&1 && [ -f "$(dirname "${BASH_SOURCE[0]}")/flake.nix" ]; then
    echo "==> entering Nix devShell (flutter not on PATH)…"
    exec env ZK_IN_DEVSHELL=1 nix develop "$(dirname "${BASH_SOURCE[0]}")" --command bash "${BASH_SOURCE[0]}" "$@"
  fi
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS="$ROOT/codes/contracts"
RELAYER="$ROOT/codes/relayer"
MOBILE="$ROOT/codes/mobile"
ADDRESSES="$ROOT/codes/frontend/src/deployed-addresses.json"

NODE_LOG=/tmp/zkvote-hardhat.log
RELAYER_LOG=/tmp/zkvote-relayer.log
EMU_LOG=/tmp/zkvote-emulator.log
NODE_PID=/tmp/zkvote-node.pid
RELAYER_PID=/tmp/zkvote-relayer.pid
EMU_PID=/tmp/zkvote-emulator.pid

AVD_NAME="${ZK_AVD_NAME:-zkvote}"
EMU_SERIAL="${ZK_EMU_SERIAL:-emulator-5554}"
# Derive the emulator console port from the serial (emulator-5554 -> 5554) so a
# custom ZK_EMU_SERIAL boots on the matching port instead of always 5554.
EMU_PORT="${EMU_SERIAL#emulator-}"
CHAIN_ID=31337

rpc() { curl -s --max-time 3 -X POST http://127.0.0.1:8545 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null; }

relayer_alive() { curl -s --max-time 3 http://127.0.0.1:3001/ >/dev/null 2>&1; }

# ── Stack ───────────────────────────────────────────────────────────────────
up() {
  if rpc | grep -q result; then
    echo "A node is already listening on :8545 — run './dev-stack.sh down' first." >&2; exit 1
  fi
  echo "==> Starting Hardhat node (log: $NODE_LOG)"
  ( cd "$CONTRACTS" && setsid npx hardhat node >"$NODE_LOG" 2>&1 </dev/null & echo $! >"$NODE_PID" )
  echo -n "    waiting for RPC"
  for _ in $(seq 1 40); do rpc | grep -q result && break; echo -n "."; sleep 1; done; echo
  rpc | grep -q result || { echo "    node failed to start; see $NODE_LOG" >&2; exit 1; }

  echo "==> Deploying contracts (local MockSemaphoreVerifier — real verifier is not wired on this branch)"
  ( cd "$CONTRACTS" && npx hardhat run scripts/deploy.ts --network localhost )

  echo "==> Seeding demo poll"
  ( cd "$CONTRACTS" && npx hardhat run scripts/demo-poll.ts --network localhost )

  echo "==> Starting relayer (log: $RELAYER_LOG)"
  local key
  key="$(grep -m1 'Private Key:' "$NODE_LOG" | grep -oE '0x[0-9a-fA-F]{64}' | head -n1 || true)"
  if [ -z "$key" ]; then
    echo "    WARN: could not parse Hardhat #0 key from $NODE_LOG; relayer not started." >&2
    echo "          (read-path e2e does not need the relayer — voting does.)" >&2
  else
    ( cd "$RELAYER" && RPC_URL=http://127.0.0.1:8545 RELAYER_PRIVATE_KEY="$key" PORT=3001 \
        setsid npm run start >"$RELAYER_LOG" 2>&1 </dev/null & echo $! >"$RELAYER_PID" )
    echo -n "    waiting for relayer"
    for _ in $(seq 1 20); do grep -q "running on port" "$RELAYER_LOG" 2>/dev/null && break; echo -n "."; sleep 1; done; echo
    grep -q "running on port" "$RELAYER_LOG" 2>/dev/null \
      || echo "    WARN: relayer did not report ready; see $RELAYER_LOG (non-fatal for read-path e2e)" >&2
  fi

  echo
  echo "Stack up:"
  echo "  chain    http://127.0.0.1:8545  (chainId $CHAIN_ID, mock verifier)"
  echo "  relayer  http://127.0.0.1:3001"
  echo "  app      cd codes/mobile && flutter run -d $EMU_SERIAL --dart-define RPC_URL=http://10.0.2.2:8545"
}

down() {
  for f in "$RELAYER_PID" "$NODE_PID"; do
    [ -f "$f" ] && { kill "$(cat "$f")" 2>/dev/null || true; rm -f "$f"; }
  done
  pkill -f "hardhat node" 2>/dev/null || true
  pkill -f "relayer.*src/index.ts" 2>/dev/null || true
  pkill -f "scripts/demo-poll" 2>/dev/null || true
  echo "Stopped node + relayer."
}

# ── Emulator ──────────────────────────────────────────────────────────────────
# Resolve avdmanager/sdkmanager from cmdline-tools first. The legacy tools/bin
# variants crash on JDK17 (NoClassDefFoundError javax/xml/bind — JAXB removed in
# JDK11+); the cmdline-tools versions bundle their deps and run fine.
find_sdk_tool() {
  local name="$1" p
  for p in "$ANDROID_SDK_ROOT"/cmdline-tools/latest/bin/"$name" \
           "$ANDROID_SDK_ROOT"/cmdline-tools/*/bin/"$name" \
           "$ANDROID_SDK_ROOT"/tools/bin/"$name"; do
    [ -x "$p" ] && { echo "$p"; return; }
  done
  command -v "$name" 2>/dev/null || echo "$name"
}
AVDMANAGER="$(find_sdk_tool avdmanager)"
SDKMANAGER="$(find_sdk_tool sdkmanager)"

ensure_licenses() {
  if [ ! -f "$ANDROID_SDK_ROOT/licenses/.zk-accepted" ]; then
    echo "==> Accepting Android SDK licenses (one-time, into the writable overlay)"
    yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
    touch "$ANDROID_SDK_ROOT/licenses/.zk-accepted" 2>/dev/null || true
  fi
}

system_image_pkg() {
  # Discover the installed google_apis_playstore x86_64 system image; never
  # hard-pin the API level (the flake resolves "latest" against pinned nixpkgs).
  # API dir can carry a minor version, e.g. android-36.1 — match digits + dots.
  local d
  d="$(ls -d "$ANDROID_SDK_ROOT"/system-images/android-*/google_apis_playstore/x86_64 2>/dev/null | head -n1)"
  [ -z "$d" ] && { echo "" ; return; }
  local api; api="$(echo "$d" | sed -E 's#.*/system-images/(android-[0-9.]+)/.*#\1#')"
  echo "system-images;${api};google_apis_playstore;x86_64"
}

ensure_avd() {
  if "$AVDMANAGER" list avd 2>/dev/null | grep -q "Name: $AVD_NAME"; then
    return
  fi
  local pkg; pkg="$(system_image_pkg)"
  [ -z "$pkg" ] && { echo "No google_apis_playstore x86_64 system image found under $ANDROID_SDK_ROOT" >&2; exit 1; }
  echo "==> Creating AVD '$AVD_NAME' from $pkg"
  echo "no" | "$AVDMANAGER" create avd -n "$AVD_NAME" -k "$pkg" --abi "google_apis_playstore/x86_64" --force
  # avdmanager defaults this AVD to 2 GB RAM; the API-36 Play Store image
  # OOM-panics into a boot loop at 2 GB. Give it headroom.
  local cfg="$ANDROID_AVD_HOME/$AVD_NAME.avd/config.ini"
  if [ -f "$cfg" ]; then
    sed -i -E '/^hw\.ramSize *=/d; /^vm\.heapSize *=/d' "$cfg"
    printf 'hw.ramSize = 4096\nvm.heapSize = 256\n' >> "$cfg"
  fi
}

# "Running" means booted AND responsive — not merely listed by adb (a dying or
# still-booting emulator lingers in `adb devices` and would be skipped wrongly).
emu_running() { [ "$(adb -s "$EMU_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; }

emu() {
  ensure_licenses
  ensure_avd
  adb start-server >/dev/null 2>&1 || true
  if emu_running; then
    echo "==> Emulator $EMU_SERIAL already online."
    return
  fi
  echo "==> Booting headless KVM emulator '$AVD_NAME' (log: $EMU_LOG)"
  # swiftshader_indirect: software GL, avoids the Nix Mesa/host-GL mismatch.
  # -memory 4096: belt-and-suspenders against the 2 GB OOM boot loop.
  # ZK_EMU_WIPE=1 -> -wipe-data, to reset a /data partition corrupted by an
  # earlier crash/OOM loop (symptom: pm/am "DELETE_FAILED_INTERNAL_ERROR").
  local wipe=""; [ "${ZK_EMU_WIPE:-0}" = "1" ] && wipe="-wipe-data"
  ( emulator -avd "$AVD_NAME" -no-window -no-audio -no-boot-anim -no-snapshot $wipe \
      -memory 4096 -gpu swiftshader_indirect -port "$EMU_PORT" >"$EMU_LOG" 2>&1 </dev/null & echo $! >"$EMU_PID" )

  # Bounded boot wait: poll sys.boot_completed (works while offline — returns
  # empty), and bail fast if the emulator process dies (a boot crash) rather
  # than blocking forever in `adb wait-for-device`.
  echo -n "    booting (up to ~7m)"
  sleep 3
  local booted= waited=0
  while [ "$waited" -lt 420 ]; do
    if ! pgrep -f "qemu-system.*-avd $AVD_NAME" >/dev/null 2>&1; then
      echo; echo "    emulator exited during boot (crash/OOM?); see $EMU_LOG" >&2; return 1
    fi
    if [ "$(adb -s "$EMU_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
      booted=1; break
    fi
    echo -n "."; sleep 5; waited=$((waited + 5))
  done
  echo
  [ -n "$booted" ] || { echo "    emulator did not finish booting in ~7m; see $EMU_LOG" >&2; return 1; }
  adb -s "$EMU_SERIAL" shell input keyevent 82 >/dev/null 2>&1 || true   # dismiss keyguard
  echo "==> Emulator $EMU_SERIAL ready."
}

emu_kill() {
  adb -s "$EMU_SERIAL" emu kill >/dev/null 2>&1 || true
  [ -f "$EMU_PID" ] && { kill "$(cat "$EMU_PID")" 2>/dev/null || true; rm -f "$EMU_PID"; }
  pkill -f "emulator -avd $AVD_NAME" 2>/dev/null || true
  echo "Stopped emulator."
}

# ── e2e ───────────────────────────────────────────────────────────────────────
registry_address() {
  # Read the freshly-deployed registry by key (robust to JSON key reordering).
  jq -r --arg c "$CHAIN_ID" '.[$c].REGISTRY_ADDRESS // empty' "$ADDRESSES" 2>/dev/null
}

e2e() {
  rpc | grep -q result || up

  # Target: emulator (default) or a physical device via ZK_DEVICE=<serial>.
  local serial="${ZK_DEVICE:-$EMU_SERIAL}" rpc_url relay_url is_emu=
  if [ "${serial#emulator-}" != "$serial" ]; then
    is_emu=1
    emu
    # Emulator NATs 10.0.2.2 -> host loopback.
    rpc_url="http://10.0.2.2:8545"; relay_url="http://10.0.2.2:3001"
  else
    echo "==> Target is physical device $serial — bridging host stack via adb reverse"
    adb -s "$serial" reverse tcp:8545 tcp:8545 >/dev/null 2>&1 || true
    adb -s "$serial" reverse tcp:3001 tcp:3001 >/dev/null 2>&1 || true
    # adb reverse maps the device's localhost to the host loopback.
    rpc_url="http://127.0.0.1:8545"; relay_url="http://127.0.0.1:3001"
  fi

  local reg; reg="$(registry_address)"
  [ -z "$reg" ] && { echo "Could not read REGISTRY_ADDRESS from $ADDRESSES" >&2; return 1; }

  echo "==> Running integration_test on $serial (registry $reg)"
  local rc=0
  ( cd "$MOBILE" && flutter test integration_test/app_test.dart \
      -d "$serial" \
      --dart-define RPC_URL="$rpc_url" \
      --dart-define RELAYER_URL="$relay_url" \
      --dart-define REGISTRY_ADDRESS="$reg" ) || rc=$?

  if [ -n "$is_emu" ] && [ "${ZK_KEEP:-0}" != "1" ]; then
    emu_kill
  elif [ -n "$is_emu" ]; then
    echo "    (ZK_KEEP=1 — leaving emulator $serial up)"
  fi

  if [ "$rc" -eq 0 ]; then
    echo "✅ e2e PASSED"
  else
    echo "❌ e2e FAILED (rc=$rc)"
  fi
  echo "   chain+relayer still up; './dev-stack.sh down' to stop them."
  return "$rc"
}

status() {
  echo -n "chain    :8545  "; rpc | grep -q result && echo "UP" || echo "down"
  echo -n "relayer  :3001  "; relayer_alive && echo "UP" || echo "down"
  echo -n "emulator $EMU_SERIAL  "; emu_running && echo "UP" || echo "down"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  status) status ;;
  emu) emu ;;
  emu-kill) emu_kill ;;
  e2e) e2e ;;
  *) echo "usage: $0 {up|down|status|emu|emu-kill|e2e}" >&2; exit 2 ;;
esac
