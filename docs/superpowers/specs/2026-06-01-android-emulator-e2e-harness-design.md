# Android-emulator e2e harness for `zkvote_mobile` — Design

**Status:** Implemented on `feat/flutter-mobile`.
**Date:** 2026-06-01.
**Authors:** Hoang + Claude.

---

## TL;DR

Make `feat/flutter-mobile` reproducibly testable on a virtual device: one Nix
dev shell provisions Flutter + a writable Android SDK + a KVM-accelerated
emulator; one command (`./dev-stack.sh e2e`) brings up the local chain stack,
boots a headless emulator, builds the app onto it, and drives a real
browse → poll-detail → verify flow against live on-chain data.

## Context discovered while scoping

- **The Flutter app lives on `feat/flutter-mobile`**, not `dev/lvh`. The devenv
  work (`flake.nix` Android SDK block, `.mcp.json` for the `dart` MCP) was
  staged on `dev/lvh`; it was re-applied here (the only delta over this branch's
  flake was a `FLUTTER_ROOT`/`FLUTTER_SDK` block).
- **This branch deploys the *mock* verifier.** `deploy.ts` throws on
  `USE_REAL_VERIFIER=true` (the real Groth16 verifier — P4-23/P4-24 — was wired
  later on `dev/lvh`). This is irrelevant to the harness: the e2e covers
  **read paths**, which read on-chain state regardless of the verifier, and
  submits no proofs.
- **Proof generation is web-only.** The poll-detail screen itself states the
  build is read-only for voting on mobile. So a full vote (proof → relayer →
  tally) is **out of scope on the emulator by design**; it stays the web
  target's job until the deferred WebView proof path lands.
- **The seed script is `demo-poll.ts`** (one "Demo Poll", Registration state,
  options Yes/No/Abstain, 2 registered voters) — not `dev/lvh`'s `seed-demo.ts`.

## Architecture — five pieces

1. **`flake.nix` dev shell.** Flutter 3.41 (Dart 3.11), JDK17, Chromium, and a
   license-accepted Android SDK (NDK + emulator + `google_apis_playstore`
   x86_64 system image for KVM). `FLUTTER_ROOT`/`FLUTTER_SDK` point the `dart`
   MCP at the SDK.

2. **Writable `~/asdk` overlay** (shellHook). The Nix store SDK is read-only;
   AVD creation, license acks, and the Gradle build need to write. The hook
   mirrors the store SDK as a **symlink farm** under `$HOME/asdk` with a real,
   seeded `licenses/` dir; writes to the overlay root succeed, package subtrees
   stay read-only symlinks. `ANDROID_HOME`/`SDK_ROOT` point at the overlay;
   `ANDROID_AVD_HOME`/`USER_HOME` at a writable home. Rebuilt only when the
   store path changes.

3. **Emulator orchestration** (`dev-stack.sh emu`). Resolves
   `avdmanager`/`sdkmanager` from **cmdline-tools** (the legacy `tools/bin`
   variants crash on JDK17 — JAXB was removed in JDK11+). Discovers the system
   image package id from the filesystem (handles dotted API like `android-36.1`;
   never hard-pins). Creates the AVD if missing, boots headless with software
   GL (`-gpu swiftshader_indirect -no-window`), then `adb wait-for-device` +
   polls `sys.boot_completed`. Targets the emulator by serial (`emulator-5554`)
   because a physical device may also be attached.

4. **Debug cleartext** (`android/app/src/debug/AndroidManifest.xml`).
   `usesCleartextTraffic="true"` so the emulator can reach the host stack at
   `http://10.0.2.2:8545` / `:3001` (the emulator NATs `10.0.2.2` → host
   loopback; API 28+ blocks cleartext by default). Release manifest untouched.

5. **e2e harness** (`integration_test/app_test.dart` + `test_driver/`). Run with
   `flutter test integration_test/... -d emulator-5554 --dart-define RPC_URL=…`
   pointing at `10.0.2.2`. Asserts Browse lists the seeded poll → poll detail
   shows the real `N REGISTERED · M VOTES CAST` + options + the read-only banner
   → Verify screen renders. Uses a `pumpUntilFound` loop (not `pumpAndSettle`)
   to tolerate the loading spinner while on-chain reads are in flight.

## Data flow of `./dev-stack.sh e2e`

```
up:  Hardhat node → deploy (mock verifier) → demo-poll → relayer   (host loopback)
emu: ensure licenses → ensure AVD → headless KVM boot → wait sys.boot_completed
test: flutter test integration_test/app_test.dart -d emulator-5554
        --dart-define RPC_URL=http://10.0.2.2:8545 RELAYER_URL=http://10.0.2.2:3001
      (emulator NATs 10.0.2.2 → host 127.0.0.1 → real chain)
      browse → detail → verify on real seeded data
teardown: emulator killed (unless ZK_KEEP=1); chain+relayer left up
```

## Scope boundary

On the emulator the harness covers browse / poll-detail / verify. Casting a vote
is not e2e-tested on Android (proofs are web-only). The relayer is started for
fidelity but the read-path e2e does not depend on it (verify reads the chain
directly).
