# Tessera — Close the Loop on Mobile (QR scanner + native proving) — Design

> **Date:** 2026-06-02 · **Owner:** Hoang · **Status:** approved, pre-implementation
> Implements the "Mobile WebView prover" bullet of ROADMAP Phase 9 and promotes it
> to a dedicated effort (ROADMAP Phase 11). Builds on the unified Flutter codebase
> (`docs/superpowers/specs/2026-06-02-tessera-unify-flutter-design.md`).

## Goal

Make the **live-meeting flow complete on a phone, device-to-device**: a voter
**scans** the host's rotating QR with the camera (instead of pasting), then the
phone **generates the Groth16 vote proof on-device** and casts. Today the QR can
only be pasted, and only web (`dart:js_interop`) and desktop (Node sidecar) can
prove — mobile falls through to `ProofServiceUnsupported`.

## Decisions (from the 2026-06-02 brainstorm)

1. **Scope:** one spec covering *both* the scanner *and* native proving (the full
   loop), not split.
2. **Hosts:** `mobile_scanner` for the camera; **`webview_flutter`** hosting the
   *same* `codes/mobile/web/zkprover.js` for proving (already named as the mobile
   prover host in the unify spec).
3. **Artifacts:** **bundled as Flutter assets** (offline, deterministic, no CDN
   trust — satisfies finding P4-24), at **one fixed tree depth = 16**.
4. **Test hardware:** **emulator now, real device later.** Proving is verified on
   the emulator; the camera is the only piece that needs real hardware.

## Key finding — web/desktop provers stay untouched

Semaphore v4 uses a **LeanIMT**, whose root is a function of the **member set
only**, not of circuit depth. Confirmed in
`web_prover/node_modules/@semaphore-protocol/proof/dist/index.browser.js:127`:
`merkleTreeRoot: merkleProof.root.toString()`. The optional `merkleTreeDepth`
arg (lines 75–112) only selects which compiled circuit/artifact to use and pads
the sibling path (`merkleProofLength` is a separate public signal); `verifyProof`
picks the vkey by the proof's own `merkleTreeDepth` (line 1550–1551).

**Consequence:** every client builds the group from the same on-chain
`registeredCommitments`, so all clients compute the **same root regardless of the
depth they prove at**, and each proof self-describes its depth to the on-chain
verifier. Mobile can therefore fix depth 16 and bundle one artifact pair **without
editing the already-verified web/desktop provers** — no cross-client "agree on
depth" requirement, no regression risk to working paths.

## Artifact sizes (PSE CDN, semaphore/4.13.0, measured 2026-06-02)

| depth | members | wasm | zkey | pair |
|---|---|---|---|---|
| 4 | 16 | 1.80 MB | 1.85 MB | 3.7 MB |
| 10 | 1,024 | 1.82 MB | 2.42 MB | 4.2 MB |
| **16** | **65,536** | **1.84 MB** | **3.41 MB** | **5.2 MB** |
| 20 | ~1M | 1.85 MB | 3.89 MB | 5.7 MB |

Depth 16 (65k members, far past any live meeting) bundles as a single **~5.2 MB**
pair. Today these are **fetched at runtime** from `snark-artifacts.pse.dev` via
`@zk-kit/artifacts`; mobile will load the bundled copies instead.

## Architecture

### Native proving — `ProofServiceMobile`

- New `ProofService` impl selected by the factory on Android/iOS (extend the
  conditional-import seam in `proof_service_factory.dart` /
  `proof_service_stub.dart`; today mobile resolves to `ProofServiceUnsupported`).
- Drives a **headless `webview_flutter`** that loads a tiny bundled HTML page
  including the *same* `zkprover.js`. Dart→JS via `runJavaScript`/
  `runJavaScriptReturningResult`; JS→Dart via a `JavaScriptChannel`
  (`postMessage` of the result JSON). Mirrors the **exact** web API surface:
  `zkGenerateVoteProof(seed, members, message, scope)` and `zkCommitment(seed)`,
  returning the same `RelayProof` JSON shape (`lib/data/models/relay_proof.dart`).
- Single-flight init (load page + bundle once), readiness handshake, and
  `dispose()` tears down the WebView. Same contract as the other impls
  (`proof_service.dart:15–34`).

### `entry.js` — additive artifact override (the only prover-bundle change)

`zkGenerateVoteProof` gains an **optional** trailing `opts` arg:

```js
async function zkGenerateVoteProof(seed, members, message, scope, opts) {
  const id = new Identity(seed)
  const group = new Group(members.map((c) => BigInt(c)))
  const depth = opts?.depth                       // mobile: 16; web/desktop: undefined
  const artifacts = (opts?.wasm && opts?.zkey)     // mobile: local blob URLs
    ? { wasm: opts.wasm, zkey: opts.zkey } : undefined
  const proof = await generateProof(id, group, Number(message), scope, depth, artifacts)
  /* ...same JSON as today... */
}
```

Web and desktop call it **without** `opts` → unchanged behaviour (CDN fetch,
dynamic depth). Purely additive; rebuild `web/zkprover.js` once via the existing
`web_prover` vite build. Desktop sidecar inherits the same bundle, still unused.

### Getting the bundled artifacts into snarkjs (the spike, M1)

snarkjs in an Android WebView commonly **cannot `fetch()` `file://`** artifacts.
- **Primary:** read the bundled asset bytes in Dart → pass to the WebView over a
  JS channel → `URL.createObjectURL(new Blob([bytes]))` → hand the blob URLs to
  `zkGenerateVoteProof` as `opts.wasm`/`opts.zkey`.
- **Fallback:** a localhost loopback HTTP server (Dart `HttpServer`) serving the
  two asset byte-streams; pass `http://127.0.0.1:<port>/…` URLs.
- **Final fallback (out of scope):** native FFI prover — deferred per the unify
  spec. If both in-WebView paths fail, proving stays unshipped on mobile and we
  re-plan; the loop's scanner half can still ship.

### QR scanner

- `mobile_scanner` camera sheet surfaced on the live-vote **`needsTicket`** stage
  (`lib/ui/features/live_vote/`). On detect → existing
  `LiveVoteViewModel.extractTicket()` (`live_vote_view_model.dart:73`) →
  `setTicket()` → `join()`. No new parsing — `extractTicket` already handles both
  full `tessera://…?t=…` links and bare tickets.
- Camera **permission** flow; the existing **paste field stays** as the always-
  available fallback (and the only input on desktop/web or when permission is
  denied). Android: add `CAMERA` permission + **non-required** `uses-feature` so
  camera-less devices still install.

## Milestones (each: build → verify)

- **M1 — WebView proving spike (HARD go/no-go gate).** Prove a small (e.g.
  3-member) group inside a headless WebView **on the emulator** using bundled
  depth-16 artifacts, and **verify the proof against the real Groth16 vkey** via
  the desktop sidecar's `verifyProof` (the trusted path). Decide primary-vs-
  fallback artifact delivery here. **Nothing else builds until this passes.**
- **M2 — `ProofServiceMobile` + plumbing.** Factory wiring; `entry.js` override +
  rebuilt bundle; bundle the depth-16 pair as assets; cast a **real M1 vote from
  the emulator** end-to-end (proof lands on-chain, nullifier set).
- **M3 — Scanner UI.** `mobile_scanner` sheet on `needsTicket`, permission flow,
  paste fallback, Android manifest perms. Wire detect → `extractTicket` → join.
- **M4 — Verify + fence + docs.** Emulator e2e (proving verified vs vkey);
  capability-gate the camera with a real-device follow-up gate; widget tests with
  a fake scanner + fake WebView prover; update ROADMAP / STATUS / TEST-COVERAGE.

## Verification — verified-or-fenced (corrected split)

- **Proving = EMULATOR-VERIFIED**, *not* device-pending. It is JS in a WebView;
  it runs on the emulator and its output is checked against the real vkey. A
  genuinely verified native-proving path.
- **Camera scan = real-device / fenced.** Emulator virtual-camera QR injection is
  unreliable, so the scanner is capability-gated; **paste is the verified
  fallback** and real-device confirmation is a named follow-up gate. The unverified
  camera path can never regress voting.

## Risks

- **WebView fetch(file://) blocked** → blob-URL injection (primary) / loopback
  server (fallback). Resolved/measured in M1.
- **snarkjs proving latency on mobile** (seconds) → show progress in the vote UI;
  measure in M1.
- **App size** +~5.2 MB from bundled artifacts → acceptable; documented.
- **Overlap with PR #44** (live_vote `extractTicket` test, vote form) → implement
  on top of merged `main` after #44 lands.

## Out of scope

- Native FFI prover (deferred). iOS device verification (Android-first; iOS rides
  the same `webview_flutter` host but is unverified until a device exists).
  Mobile *blind*-vote already works (no SNARK); unchanged here.

## Done-when

- Emulator: scan-or-paste a live ticket → on-device WebView proof → **M1 vote
  lands on-chain**, verified against the real vkey.
- `flutter analyze` clean; widget tests for scanner + mobile prover (fakes);
  web/desktop provers **unchanged** and still green.
- Camera scan capability-gated with paste fallback; real-device confirmation
  logged as a follow-up gate. ROADMAP/STATUS/TEST-COVERAGE updated.
