# Self-host the web prover's SNARK artifacts (cut the CDN) — design

**Date:** 2026-06-04
**Status:** approved (autonomous build; approval gate waived per the 8-hour mandate — write-it-down kept)
**Closes:** P4-24 (web side)

## Problem

Voting is web-primary, and the web prover fetches the Groth16 `wasm`/`zkey` from
the **PSE CDN** (`https://snark-artifacts.pse.dev`) at vote time. `entry.js` only
passes explicit artifact URLs when a caller provides `opts.wasm/zkey` — the mobile
WebView prover does (bundled), but **`ProofServiceWeb` does not**, so the web app
falls through to the CDN default.

That's a real workaround the user asked to cut: a hard runtime dependency on a
third-party CDN for the core action (down CDN → can't vote), and a privacy leak
(the CDN observes who fetches prover artifacts = who's about to vote).

## Approach

Self-host the artifacts the web build already could ship, and pass their URLs to
the prover — which already supports this path. **No JS-bundle rebuild**: the built
`web/zkprover.js` already accepts `opts = {depth, wasm, zkey}` (mobile uses it).

### 1. Ship the artifacts in the web build

Copy the bundled depth-16 artifacts into `web/zk/semaphore-16.{wasm,zkey}`.
`web/` is served verbatim at the app root, so they're reachable at `zk/...`
(relative to the base href) in the real build **and** under a locally-served
`web/` in the browser test — one URL that works in both (no Flutter
`assets/assets/...` path quirk, no build-time copy step to forget).

The cost is ~5.2 MB git-tracked twice (also in `assets/zk/` for mobile, which
loads via `rootBundle`). Accepted: robust same-origin serving for the primary
voting client is worth it, and it's the productionization, not scattered cruft.

### 2. Pass the URLs from `ProofServiceWeb`

- Extend the two `external` JS bindings with a 5th `JSObject opts` param.
- `ProofServiceWeb({this.artifactBase = ''})` — default `''` → relative `zk/...`
  (base-href-aware, same origin). The browser test passes
  `artifactBase: 'http://localhost:8099/'` because its page origin is the Flutter
  test harness, not the served `web/`.
- Build `opts = {depth: 16, wasm: '${base}zk/semaphore-16.wasm', zkey:
  '${base}zk/semaphore-16.zkey'}` and pass it on both the int and wide paths.

Depth is fixed to **16** — matches the bundled artifact and the rest of the system
(mobile, `RealVerifier.test.ts`, the relayer e2e all use depth 16). When `opts.wasm
&& opts.zkey` are set, `entry.js` passes explicit artifacts to `generateProof`, so
snarkjs fetches **those** URLs and never the CDN (no silent fallback).

### 3. Scope

Web only. The **desktop** Node-sidecar prover (`proof_service_desktop.dart` /
`web_prover/desktop_prover.mjs`) still CDN-fetches — a follow-up; P4-24 stays
Partial until that lands. Note it on the board.

## Verification (headless)

- Serve the worktree's `web/` on `:8099`, run `flutter test --platform chrome
  test/web/proof_service_web_test.dart` with `artifactBase` pointed at it: a valid
  proof generates + verifies **from the local artifacts, no CDN**. The harness is
  confirmed working in this environment (the existing CDN test passes in ~5s).
- A negative assertion (bogus `artifactBase` → generation throws) proves there is
  no CDN fallback.
- `flutter analyze` clean; the VM `flutter test` suite stays green (the browser
  test is `@TestOn('browser')`, skipped by the VM run, exactly as today).
