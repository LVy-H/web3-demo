# Tessera — Unify on One Flutter Codebase (all platforms) — Design

> **Date:** 2026-06-02 · **Branch:** `feat/flutter-mobile` · **Owner:** Hoang
> Supersedes the "desktop read-only / live-meeting stays React" boundary in the
> 2026-05-31 flutter-mobile-port plan. User directive (2026-06-02) is the
> operative instruction.

## Decision (the project name)

The project is named **Tessera** — Latin for the token/tile used as both a ballot
and an admission pass in ancient Rome, tying to the app's signed "tickets". (Noted
collision: Consensys "Tessera" private-tx manager exists in the same space; name
stands by owner's call.)

## Goal

One Flutter codebase is the **whole product** across mobile (Android/iOS), desktop
(Linux/Windows/macOS), and web — **every feature on every platform**. The React
frontend **retires** once Flutter-web covers it. Platform-specific code only where
physically required (camera/QR, BLE, NFC).

## Operative priorities (2026-06-02 user directives)

1. **Approach A (Node sidecar)** for desktop ZK proving — chosen; "migrate later"
   to native FFI if ever needed.
2. **Visible-features-first.** Focus on what the user **CAN SEE** — the navigable
   UI surface across all platforms. Get a *working, clickable app* first.
3. **Leave the proper backend/proving path OPEN as a seam, but do NOT build it
   yet.** The `ProofService` desktop impl stays a clear stub until SP4. Backend
   may be simplified freely to make visible features work.
4. **Run until we have a working app** (autonomous execution).

## The one hard constraint — Groth16 proving

Proof generation needs a JS/WASM host. Unified behind the existing `ProofService`
seam, three hosts of the **same** `web/zkprover.js`:

| Platform | Prover host | Status |
|---|---|---|
| Web | snarkjs via `dart:js_interop` | ✅ done, browser-verified |
| Mobile (Android/iOS) | `webview_flutter` hosting `zkprover.js` | designed, device-pending |
| Desktop (Linux/Win/macOS) | **Node sidecar** running `zkprover.js` (`Process.start`) | seam only for now (SP4); de-risked — `web_prover/verify.mjs` already runs it under Node 22 vs the real vkey |

## Decomposition (each sub-project: spec → plan → build → verify)

Re-ordered for **visible-first**:

1. **SP1 — Linux launch + runtime verify** *(first)*. `flutter run -d linux`
   against the local stack; fix runtime issues; smoke browse→detail→verify.
   Verifiable here (`DISPLAY=:0`, Wayland present).
2. **SP2 — Identity management** — persist a Semaphore seed (cross-platform secure
   storage). Visible "Identity" screen. Unblocks frictionless voting + live ID.
3. **SP3 — Prover-free visible parity** — M2 blind-vote (commit-reveal, hash-based,
   no SNARK) + Participation Receipts (M3). Port to all platforms incl. Linux.
4. **SP5 — Live-meeting voter + host (UI-first)** — rotating-QR scan, ephemeral
   identity, face-to-face confirmation code, organizer pending-queue dashboard.
   Build the **visible** flow; proof generation goes through the existing seam
   (web works; desktop shows the flow with the stub until SP4).
5. **SP4 — Desktop proving (deferred risk gate)** — Node-sidecar `ProofService`
   so Linux/Win/macOS actually cast M1/Semaphore votes. Built **after** the
   visible surface is complete. De-risked by `verify.mjs`.
6. **SP6 — Proximity (BLE/NFC)** — platform-specific augment to live-meeting;
   Android-first, graceful fallback elsewhere.
7. **SP7 — Retire React** — make Flutter-web canonical, archive the React
   frontend, update CI/deploy/docs.

## Architecture (unchanged seams, extended)

- MVVM + Repository, `go_router`, `provider`/`ChangeNotifier`.
- Cross-client core (`ticket`/`confirmationCode`/`orgKeypair`) byte-identical to TS.
- Data layer reuses the relayer HTTP API + contract ABIs as the cross-client
  contract.
- `ProofService` interface with per-platform impls (web ✅ / mobile webview /
  desktop Node-sidecar). Conditional `proof_service_factory` selects the impl.

## Done-when (this effort)

- App **launches and renders on Linux desktop** against the local stack.
- All **visible** feature screens exist and are navigable on Linux desktop + web:
  browse, poll detail + vote (web prover), verify, create, identity, receipts,
  M2 blind-vote, live host, live voter.
- Desktop proving and BLE/NFC are wired as **clear seams/stubs**, not built.
- `flutter analyze` clean; widget tests for new screens; runtime smoke verified.
