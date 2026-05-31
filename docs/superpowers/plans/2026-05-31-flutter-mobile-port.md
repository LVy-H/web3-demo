# Flutter Mobile Port — Implementation Plan & Living Progress Log

> **For agentic workers:** TDD task-by-task. Steps use checkbox (`- [ ]`) syntax.
> This doc is BOTH the plan and the durable progress log — update the "Current
> Status" block every iteration before acting, so a resumed/compacted context
> knows what is done.

**Goal:** Build the Flutter **recurring-member app** for the ZK-voting dApp
(browse polls, manage identity, view/verify receipts, async voting) targeting
**all platforms — mobile (Android/iOS), desktop (Linux/Windows/macOS), and web**,
reusing the existing relayer HTTP API + contract ABIs as the cross-client contract.

**Platform status:** all 6 platforms scaffolded. Verified-here builds: web ✅,
Linux desktop ✅, Android APK ✅. Windows/macOS build on their own OSes (source
scaffolded; not buildable on this Linux host). The app + data layer are pure
Dart → uniform across all targets.

**Architecture:** MVVM + Repository (per project `flutter-apply-architecture-best-practices`),
`go_router` routing, `provider`/`ChangeNotifier` state, `http` for the relayer,
JSON-RPC (`eth_call`/`eth_getLogs`) for on-chain reads. A ported **cross-client
core** (`ticket`, `confirmationCode`, `orgKeypair`) proven byte-identical to the
TS reference via golden vectors. ZK proof generation isolated behind a
`ProofService` interface, implemented via a hidden WebView running snarkjs.

**Tech Stack:** Flutter 3.41 / Dart 3.11, `ed25519_edwards`, `crypto`, `convert`,
`http`, `go_router`, `provider`, `webview_flutter` (later).

---

## Scope (read first — prevents drift)

The project's own strategy (Agile Plan §2.5) says the **live-meeting voter page
stays web by design** and must NOT be re-ported. The sanctioned Flutter target
is the **recurring-member app**. This plan builds that. We do NOT clone the web
voter page. We DO reuse the documented portability boundary: the relayer HTTP
API + contract ABIs + the three canonical encodings.

**User directive (2026-05-31) overrides the docs' "defer Flutter" stance.** The
user asked to port to Flutter and support mobile now, in a continuous loop. That
is the operative instruction.

## Autonomous decisions (Owner: Hoang — taken without pausing; revise if you object)

- **D1 — Surface first:** recurring-member app (browse → identity → receipts →
  async vote), per §2.5 scope. (Open-Q5)
- **D2 — ZK-on-Dart path (revised):** **web-first via `dart:js_interop` → snarkjs**
  (lowest risk, testable in Chrome, reuses the proven crypto). Native proving
  matrix is **UNRESOLVED and deliberately deferred** — do NOT commit to Rust-FFI
  or a webview package now (zero runtime evidence yet; the support matrix must be
  re-verified against pub.dev, not memory). It hinges on an open product question:
  **does desktop-native voting (Linux/Windows, no browser) need to work at launch?**
  **RESOLVED by user (2026-05-31): "Web + mobile voting; desktop read-only."**
  Native prover = **WebView-only (Android/iOS)** hosting the SAME verified
  `web/zkprover.js` — NO Rust-FFI epic. Desktop (Linux/Windows/macOS) keeps the
  `Unsupported` stub (browse/verify only). (Open-Q6 closed.)
  - Known matrix caveats to verify later: `webview_flutter` ≈ Android/iOS only;
    `flutter_inappwebview` ≈ +macOS/Windows but NOT Linux; nothing gives Linux a
    native webview; `flutter_js`/QuickJS can't run snarkjs WASM.
- **D3 — Placement:** buildable project on ext4 git worktree
  (`/home/hoang/zkvote-flutter-wt`, branch `feat/flutter-mobile`); the NTFS main
  tree can't create symlinks. Source = regular files, checks out fine to NTFS.
- **D4 — ed25519 lib:** `ed25519_edwards` (synchronous, seed-based like @noble).
  Arbiter is the golden-vector test; switch to `cryptography`/`pinenacl` if it
  ever mismatches.
- **D5 — Network/contracts:** default Hardhat (chainId 31337, RPC
  `http://127.0.0.1:8545`), relayer `http://localhost:3001`, addresses from
  `codes/frontend/src/deployed-addresses.json`. Config-driven for Sepolia later.

---

## Current Status (UPDATE EVERY ITERATION)

- **Iteration:** 2 (in progress)
- **PHASE 1 COMPLETE ✅** — cross-client core byte-identical to TS+relayer:
  `confirmation_code.dart` (5), `ticket.dart` (10, exact wire match), `org_keypair.dart` (8).
- **PHASE 2 part A DONE ✅** — `RelayClient` + `PendingVoter`/`RelayProof` models:
  10/10 MockClient tests asserting exact paths/body-keys/parsing for
  issue/pending/queue/redeem/vote/status (verified vs codes/relayer/src + liveRelay.ts/useRelay.ts).
- **ZK RISK A (crypto) RESOLVED ✅** — de-risk spike: Semaphore v4
  `generateProof → verifyProof == true` against the **real Groth16 vkey** (not
  the local mock), CDN artifacts fetched in 3.7s. Golden proof vector →
  `test/fixtures/zk_proof_vector.json`. `ProofService` seam defined +
  `FakeProofService` (4/4 tests). Remaining ZK = plumbing only (Risk B).
- **PHASE 2 part B DONE ✅** — `ChainReader` (web3dart) + `PollInfo`: integration
  test decodes REAL values from a live Hardhat node (getState/getOptions/
  getResults/owner/getParticipantCount + getAllPolls struct array). Demo poll
  created by `codes/contracts/scripts/demo-poll.ts` → `test/fixtures/local_chain.json`.
  Full suite 40/40; analyze clean. (Local node = MockSemaphoreVerifier, fine for reads.)
- **PHASE 4 DONE ✅ — read-only member app is functional** (browse → detail):
  - UI shell: Dark Bauhaus theme (index.css tokens), go_router, MVVM (provider).
  - `BrowseScreen` (loading/empty/error/list, module chips) + 3 widget tests.
  - `PollDetailScreen` (phase badge, options, live results bars w/ %, participant
    count, owner) + 2 widget tests. `PollRepository`/`PollDetailViewModel`.
  - Full suite **44/44**; analyze clean; `flutter build web` succeeds.
- **MOBILE BUILD VALIDATED ✅** — `flutter build apk --debug` produces a real
  147MB APK with `libflutter.so` for **arm64-v8a / armeabi-v7a / x86_64**; the
  whole dep stack (web3dart/pointycastle, ed25519_edwards, crypto, http, provider,
  go_router) is mobile-clean (also `flutter build linux` native AOT passes). NO
  dep change forced. The only blockers were the read-only Nix Android SDK missing
  components — fixed with a writable overlay (see "Android build in this env").
- **WEB VOTE PATH — proof generation VERIFIED IN-BROWSER ✅** — `web_prover/`
  bundles Semaphore v4 → `web/zkprover.js` (vite IIFE). `ProofServiceWeb`
  (`dart:js_interop`) + conditional `proof_service_factory` (web→web impl,
  native→clear `Unsupported` stub). Verified two ways: `verify.mjs` (exact bundle,
  Node) AND `flutter test --platform chrome` — the full Dart→js_interop→prover
  round-trip produces a `RelayProof` that **verifies against the real Groth16 vkey
  in a real browser** (not a false green). Browser test serves the bundle on :8099
  + auto-skips when absent. **Remaining for web voting:** wire a vote screen
  (identity seed + `getRegisteredCommitments` group → `ProofService` → `relayVote`).
- **GROUP RECONSTRUCTION DONE ✅** — `ChainReader.getRegisteredCommitments`
  (`eth_getLogs` for `VoterRegistered(uint256)`, web3dart `FilterOptions.events`)
  decodes the member set from real logs; integration test verifies vs 2 voters
  registered on the demo poll. This is the ZK proof's member-set input. 45 tests.
- **Now / next iteration options:**
  1. **Risk B — ZK plumbing** (the remaining vote-path blocker): bundle Semaphore
     JS, web `ProofService` via `dart:js_interop` (Chrome, testable here), then a
     vote screen wired through `relayVote(proof)` using `getRegisteredCommitments`
     as the group. Mobile webview after. (Group-reconstruction input: DONE above.)
  2. Verify screen (nullifier lookup via `isNullifierUsed` — small, ZK-independent).
  3. Runtime smoke: launch app vs live node, confirm the demo poll renders.

## Android build in this env (read-only Nix SDK)

The Nix `androidsdk` lives in read-only `/nix/store` and ships only NDK
29.0.14206865, `platforms;android-36.1`, `build-tools;36.1.0` — but AGP wants
`android-36` + `build-tools;35.0.0` + `cmake;3.22.1` and can't install into the
store. Fix (one-time, machine-local):
1. `android/app/build.gradle.kts`: pin `ndkVersion = "29.0.14206865"` (committed).
2. Writable overlay at `~/asdk`: symlink the read-only components
   (ndk, platform-tools, cmdline-tools, platforms/android-36.1, build-tools/36.1.0)
   into writable `platforms/`, `build-tools/`, `cmake/`, copy `licenses/`, then
   `sdkmanager --sdk_root=~/asdk "platforms;android-36" "build-tools;35.0.0" "cmake;3.22.1"`.
3. Build with the overlay via env var (robust — `flutter test`/`pub get`
   rewrites `local.properties`'s `sdk.dir`, so don't rely on editing it):
   `ANDROID_SDK_ROOT=$HOME/asdk ANDROID_HOME=$HOME/asdk flutter build apk --debug`.
Verified: produces `build/app/outputs/flutter-apk/app-debug.apk` (147MB, 3 ABIs).
The proper fix is augmenting the Nix `androidsdk` derivation, but that needs an
`/etc/nixos` rebuild (out of scope).
- **Local chain for integration tests:** `cd codes/contracts && npm run deploy:local
  && npx hardhat run scripts/demo-poll.ts --network localhost` (regenerates fixture).
- **Oracle:** recreate `codes/frontend/src/lib/__vectors.gen.test.ts` + `npx vitest run …`
  to regenerate vectors; delete after. Durable artifact = the committed fixture.
- **Build/test runs via Bash** (`flutter test`/`flutter analyze`) — Dart MCP is
  locked to the NTFS root and can't reach the ext4 worktree.

---

## Phase 1 — Cross-client core (byte-identical port) [TDD]

Target dir: `codes/mobile/lib/core/crypto/`. Tests: `codes/mobile/test/core/crypto/`.
Golden fixture: `codes/mobile/test/fixtures/cross_client_vectors.json`.

### Task 1: confirmationCode

**Files:**
- Create: `codes/mobile/lib/core/crypto/confirmation_code.dart`
- Test: `codes/mobile/test/core/crypto/confirmation_code_test.dart`

- [x] **Step 1 — failing test** asserting golden codes (`4861`, `3480`, `3518`),
  4-digit invariant, hex/bytes + bigint/string equivalence, negative throws.
- [x] **Step 2 — ran, failed** (method not found).
- [x] **Step 3 — implemented** `sha256(nonceBytes ‖ commitment_32B_BE)`, first 16
  bits BE, `% 10000`, padLeft(4,'0').
- [x] **Step 4 — ran, 5/5 pass.**
- [x] **Step 5 — commit** (with scaffold).

### Task 2: ticket (ed25519, base64url-nopad, 32B preimage / 96B wire)

**Files:**
- Create: `codes/mobile/lib/core/crypto/ticket.dart`
- Test: `codes/mobile/test/core/crypto/ticket_test.dart`

- [x] Failing test (preimage/wire/decode/verify states/createPayload). 10 tests.
- [x] Ran, failed (then fixed a missing `dart:convert` import).
- [x] Implemented with `ed25519_edwards`, `base64Url` no-pad, big-endian u32.
- [x] Ran, 10/10 pass — exact TS wire match.
- [x] Committed (95abee0).

### Task 3: orgKeypair

**Files:**
- Create: `codes/mobile/lib/core/crypto/org_keypair.dart`
- Test: `codes/mobile/test/core/crypto/org_keypair_test.dart`

- [x] Failing test (golden pubKey, round-trip, KeyStore CRUD, corrupt→null). 8 tests.
- [x] Ran, failed.
- [x] Implemented ed25519 keypair (hex) + `KeyStore` abstraction + JSON storage.
- [x] Ran, 8/8 pass.
- [x] Committed (with Phase-1 wrap).

## Phase 2 — Data layer (relayer HTTP + JSON-RPC reads) [TDD]
Detail when reached. Relayer client mirrors `liveRelay.ts` endpoints; JSON-RPC
`eth_call` for `getState/getOptions/getResults/getParticipantCount/owner/
registeredCommitments/isNullifierUsed`; JSON models with `fromJson`. Verify ABIs
& selectors against `codes/frontend/src/abi/*.json` and the contract source.

## Phase 3 — ZK proof (decomposed; behind `ProofService`)
- **Risk A — crypto [DONE ✅]:** `generateProof → verifyProof` against the real
  Groth16 vkey (Node, zero Flutter). NOTE: local Hardhat = MockSemaphoreVerifier
  (always-true) → never use "vote lands locally" as a crypto success criterion.
- **Risk B — plumbing [TODO]:** host the same Semaphore JS bundle and marshal
  the `RelayProof` back. (1) Flutter-web JS-interop in Chrome — testable on this
  machine; (2) mobile `webview_flutter` — last mile, needs device/emulator.
  Output must match `zk_proof_vector.json`.

## Phase 4 — UI (Dark Bauhaus theme, go_router, MVVM screens)
Theme tokens from `docs/standards/visual-design-guide.md`. Screens: Browse,
Poll detail (results/tally), Verify receipt, Identity. Responsive per
`flutter-build-responsive-layout`. Widget tests per `flutter-add-widget-test`.

## Phase 5+ — async voting, receipts, polish, integration tests
Loop continues: idea → plan → build → test.
