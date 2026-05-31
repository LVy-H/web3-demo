# Flutter Mobile Port — Implementation Plan & Living Progress Log

> **For agentic workers:** TDD task-by-task. Steps use checkbox (`- [ ]`) syntax.
> This doc is BOTH the plan and the durable progress log — update the "Current
> Status" block every iteration before acting, so a resumed/compacted context
> knows what is done.

**Goal:** Build the Flutter **recurring-member app** for the ZK-voting dApp
(browse polls, manage identity, view/verify receipts, async voting) targeting
mobile (Android/iOS) + web, reusing the existing relayer HTTP API + contract
ABIs as the cross-client contract.

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
- **D2 — ZK-on-Dart path:** hidden WebView + snarkjs (Option 1 in §2.5). Most
  tractable on-device; reuses the exact web prover artifacts. (Open-Q6)
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

- **Iteration:** 2 (starting)
- **PHASE 1 COMPLETE ✅** — cross-client core ported, byte-identical to TS+relayer:
  - `confirmation_code.dart` — 5/5 tests
  - `ticket.dart` — 10/10 tests (signTicket emits the EXACT TS wire string →
    ed25519_edwards == @noble proven)
  - `org_keypair.dart` — 8/8 tests
  - Full suite: 24/24 pass; `flutter analyze` clean on lib/core + test/core.
- **Now:** Phase 2 — data layer (relayer HTTP client + JSON-RPC contract reads + models).
- **Next:** Phase 3 ZK proof spike (WebView+snarkjs) — advisor check before starting.
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

## Phase 3 — ZK proof spike (WebView + snarkjs) [SPIKE, de-risk early]
Before UI that depends on voting: load Semaphore artifacts in a hidden WebView,
generate one real proof, return it over the JS channel, confirm it verifies
on-chain against local Hardhat. Behind a `ProofService` interface.

## Phase 4 — UI (Dark Bauhaus theme, go_router, MVVM screens)
Theme tokens from `docs/standards/visual-design-guide.md`. Screens: Browse,
Poll detail (results/tally), Verify receipt, Identity. Responsive per
`flutter-build-responsive-layout`. Widget tests per `flutter-add-widget-test`.

## Phase 5+ — async voting, receipts, polish, integration tests
Loop continues: idea → plan → build → test.
