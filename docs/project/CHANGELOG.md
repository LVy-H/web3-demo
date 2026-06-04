# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: see [VERSIONING.md](./VERSIONING.md).

## [Unreleased]

### Added
- **Runtime network config — point one build at any backend (no rebuild)** —
  the backend pointers (RPC, relayer, registry, Semaphore verifier, chain id)
  were compile-time only (`--dart-define`), so a hosted build (e.g. on Cloudflare
  Pages) had `localhost` baked in and couldn't reach your chain. A new
  **Settings → Network** screen edits them in-app; the override is persisted
  (secure storage, incl. browser localStorage on web) and overlaid onto the
  compile-time defaults once at startup. Web offers a one-tap **Reload to apply**;
  native shows "restart to apply". Hardened: the override is applied in exactly
  one place (`main()`) so every consumer stays consistent for the run, and a
  format-validated load guard means a corrupt/garbage blob can never brick
  startup (the registry address is parsed eagerly — a bad value would otherwise
  white-screen the app with Settings unreachable). Unit + widget tested
  (store/validator contract, form save/validate/reset).
- **CI publishes downloadable build artifacts** — every CI run now uploads
  `tessera-web` (the static `build/web` site, the thing you deploy to Cloudflare
  Pages / any static host) from the `mobile` job, and a new `android` job builds
  and uploads `tessera-apk` (release APK, debug-signed so it installs for
  testing). The `android` job is separate so an Android/Gradle hiccup never
  blocks the web gate. 14-day retention.
- **"MINE" filter — the polls you created** — answers the natural next question
  after the ownership work: *which of these are mine?* Under wallet-free the
  relayer is the on-chain `creator` of every sponsored poll, so "mine" can't come
  from the chain — `CreatedPollsStore` (mirrors `IdentityStore`, secure-storage
  backed) records each poll this device creates, and a new **MINE** pill in the
  browse status strip filters to them. Unit-tested store contract + a browse
  widget test (a device that created one poll sees only it under MINE). Design:
  `docs/superpowers/specs/2026-06-04-mine-filter-design.md`.
- **Ownership labels on the browse cards** — completes the ownership-clarity
  feedback at the surface where it was actually felt (the list). Each card showed
  `PollInfo.creator` as a raw hex — and under wallet-free the relayer creates every
  poll, so every card read the same opaque address. The card now reuses
  `pollOwner` (#88) to read a short tag — **SPONSORED** (relayer-run) / **YOU** /
  the creator's address — by probing the relayer address once on open (down →
  short-address fallback). Widget-tested. Next: a "Mine" filter + local
  created/voted tracking. Design:
  `docs/superpowers/specs/2026-06-04-browse-ownership-design.md`.
- **BLE proximity attestation for live meetings** — the other half of NFC/BLE.
  While a live-meeting voter is *pending* (showing their 4-digit code), the app
  scans (`flutter_blue_plus`) for the organizer's BLE beacon — a service UUID both
  sides derive from the public poll address (`bleBeaconUuid`, unit-tested) — and
  shows a silent **"✓ Verified in the room (BLE)"** chip. Anti-remote-voting: it
  only *adds* trust and never gates the face-to-face code. The `ProximityService`
  seam was refactored web-safe (conditional-import factory keeping
  `flutter_blue_plus`/`dart:io` out of the web compile, mirroring NFC) and wired
  into `LiveVoteViewModel` (default no-op, so existing callers are unaffected).
  `analyze` + `flutter test` green; the BLE scan + the organizer *advertising* the
  beacon (flutter_blue_plus is scan-only — needs a physical beacon or a
  peripheral-mode plugin) are device-fenced. Design:
  `docs/superpowers/specs/2026-06-04-ble-proximity-design.md`.
- **NFC tap-to-open polls** — a poll's `tessera://poll/<addr>?module=<m>` link
  (the *same* payload the QR encodes) can be written to an **NFC tag** from the
  share sheet: a venue/booth puts a tap-to-vote sticker instead of asking people
  to aim a camera. Reuses `shareLinkForPoll` + `routeForScannedValue` — NFC is a
  transport, not a new format. Capability-gated exactly like `ProximityService`
  (`NfcService` seam + web-safe conditional-import factory keeping `nfc_manager`/
  `dart:io` out of the web compile): the **WRITE TO NFC TAG** button appears only
  where a radio is present (probed `isAvailable()`), and the QR stays the baseline
  everywhere else. `analyze` + `flutter test` (NFC affordance + payload parity +
  no-op contract) + `build web` (NFC-free) all green; the Android plugin build and
  the radio write itself are device-fenced (real NFC phone + writable tag).
  Design: `docs/superpowers/specs/2026-06-04-nfc-tap-share-design.md`.
- **Poll ownership + permissions clarity** — answers "I don't know who owns a
  poll or what permission everyone has." The poll detail's bare `OWNER: 0x…` row
  is now a meaningful **RUN BY** label: a relayer-owned (wallet-free) poll reads
  **"Sponsored · relayer-run"**, your own poll reads **"You"**, otherwise a
  specific creator's short address (pure `pollOwner`, unit-tested). A new **"Who
  can do what"** sheet explains the model — leading with the ZK guarantee that
  *nobody, not even the owner, can see who voted for what* — then owner / voters /
  your access. Design: `docs/superpowers/specs/2026-06-04-poll-roles-permissions-design.md`.
- **Share + the signing explainer reach every screen** — the **SHARE** button now
  appears on all six poll-detail surfaces (anon / blind / approval / ranked /
  quadratic / survey), each generating its own correct module deep-link; and the
  **How signing works** explainer is now linked from the create screen too. This
  is the "adopt it with a one-liner" follow-through on the two features below,
  completing the scan loop and the wallet-free messaging app-wide.
- **"How signing works" explainer + truthful Settings signer status** — directly
  on the wallet-UX pain point. Settings → SIGNING & PROVING no longer claims
  `"wallet (connect to sign)"` when there's no dev-signer; it probes the relayer
  and shows the *active* path — `wallet-free (sponsored relayer)` when sponsorship
  is reachable (resolved by the pure, unit-tested `signerStatusLabel`). A new
  **How signing works** link opens a reusable sheet (`signing_explainer.dart`)
  that leads with **"You don't need a wallet."** and explains the three paths
  (wallet-free default · local dev-signer · optional wallet). Design:
  `docs/superpowers/specs/2026-06-04-signing-explainer-design.md`.
- **Share a poll** — closes the scan loop opened by the navbar SCAN action (#76):
  the poll-detail header now has a **SHARE** button that opens a themed sheet with
  a scannable QR + copyable `tessera://poll/<addr>?module=<m>` deep-link. The link
  generator (`shareLinkForPoll`) is the exact inverse of the scanner's
  `routeForScannedValue`, pinned by a round-trip property test across all six
  module types (a shared QR always scans back to the same poll). No new
  dependency — reuses the bundled `qr_flutter`. Share lives in the shared
  `pollDetailHeaderRow` (opt-in `onShare`), so other module screens adopt it with
  a one-liner. Design: `docs/superpowers/specs/2026-06-04-share-a-poll-design.md`.
- **Wallet-free voting proven against the real Groth16 verifier on the live
  chain** — `ZK_REAL_VERIFIER=1 ./dev-stack.sh up` now brings up a real-verifier
  stack end to end (the demo seed skips its mock-proof cast under
  `USE_REAL_VERIFIER` instead of reverting and aborting `up` via `set -e`). Two
  scripts assert the result on the *running* chain (the same `:8545` the app
  hits): `scripts/check-live-verifier.ts` — a bad proof must REVERT, the only
  behaviour that tells the real verifier from the accept-anything mock; and
  `scripts/e2e-relayer-real-vote.ts` — the full mobile submission path (real
  Groth16 proof → `POST /api/relay/vote` → relayer `castVote` → on-chain
  verifier), which rejects a tampered proof and lands a valid one (on-chain
  tally `[1,0]`). Closes the last real-vs-mock workaround: the local Hardhat
  chain is a genuine ZK-verifying chain the app votes against wallet-free.
- **Real Groth16 verifier wired (P4-23)** — `deploy.ts` deploys the real
  `SemaphoreVerifier` when `USE_REAL_VERIFIER=true` (`npm run deploy:real-verifier`,
  `ZK_REAL_VERIFIER=1 ./dev-stack.sh up`), pulled into the compile graph by
  `contracts/SemaphoreVerifierImport.sol`. `test/integration/RealVerifier.test.ts`
  generates a REAL proof from the bundled depth-16 artifacts (no CDN) and asserts
  the verifier accepts a valid vote + rejects a tampered one — gated behind
  `RUN_REAL_VERIFIER=1`. The local chain can now genuinely verify ZK proofs
  instead of the accept-anything mock.
- **QR scan in the navbar** — a 5th bottom-nav entry **SCAN** (`qr_code_scanner`)
  that opens the camera scanner (mobile) or an always-reachable paste dialog and
  **routes** the decoded Tessera deep-link: `tessera://live/<a>/vote?t=…` →
  live-vote, `tessera://verify?…` → verify, `tessera://poll/<a>?module=…` → poll
  detail (also tolerates `https` mirrors). SCAN is an *action*, not a tab (it
  doesn't switch branches). The pure `routeForScannedValue` parser is unit-tested
  (13 cases); the camera decode stays the device-fenced path, paste is the
  verified fallback. The existing live-vote scanner was generalized (title/hint
  params, a success haptic, a "paste a link instead" affordance). Design:
  `docs/superpowers/specs/2026-06-03-navbar-qr-scan-design.md`.
- **Phase 12d — Multi-question survey voting (`survey-vote`)**, shipped
  full-stack and closing the Phase 12 voting-types epic (12a/12b/12c/12d all
  shipped):
  - **Contract** `ZkSurveyVoting` — one survey = an ordered `Question[]` (per
    question: single-choice or multi-select, own options, own tally); one ballot,
    one Semaphore proof, one nullifier per voter per survey; the answer vector is
    bound by a hash commitment `message = keccak256(abi.encode(answers)) >> 8`
    that the contract recomputes on-chain; per-question results via
    `getSurveyResults()` (`IZkPoll` frozen — `getResults()` is a documented
    question-0 degenerate). 45 hardhat tests.
  - **Relayer** `POST /api/relay/survey-vote` route + `validateSurveyVoteRequest`
    (14 tests); ABIs + `deploy.ts` registers `survey-vote` and persists
    `SURVEY_VOTING_IMPL`.
  - **Flutter** — survey read / answer / cast / per-question results (N
    `ResultsBars`) + a question-builder create flow (`?module=survey-vote`).
  - **Prover** widened `Number→BigInt` (`web_prover/entry.js`, re-bundled +
    parity-guarded) so the wide keccak-commitment message survives; regression-
    verified against all four shipped SNARK-message modules.
  - **Cross-impl gate** — Dart `surveyCommitment` ≡ ethers ≡ Solidity for the
    commitment and the `(uint8,string[])[]` init encoding.
  - **Stack e2e seed** — `scripts/demo-poll.ts` creates a survey on the local
    chain, casts a ballot `[2,5]`, and reads non-empty per-question tallies. The
    on-device mobile UI survey cast is device-gated/fenced (same bound as every
    module's on-device proving), not a regression risk.
  - Spec: `docs/superpowers/specs/2026-06-03-survey-voting-design.md`;
    architecture: `docs/architecture/module-survey.md`.

### Changed
- **Nightly real-verifier CI** — `.github/workflows/real-verifier.yml` runs the
  `RealVerifier.test.ts` Groth16 integration test (a real snarkjs proof, accept +
  tamper-reject) on a nightly schedule and on manual dispatch. Kept off the
  per-PR `CI` gate because the proof generation is too slow for every push.
  Closes Phase 2.5 (the real-verifier path is now exercised automatically).
- **CI hardening** — the `contracts` job's `npm test` is now a real gate (the
  stale `continue-on-error` was removed; the cited blocker — untracked hardhat
  config — no longer holds, and all 268 tests pass). The `relayer` job now runs
  `npm test` (96 tests) instead of a no-op `lint || true`.
- **Version alignment** — `codes/contracts` and `codes/relayer` `package.json`
  pinned to `0.2.0`, matching the canonical client (`codes/mobile`) and the
  pre-1.0 repo semver (they previously claimed `1.0.0`, which `VERSIONING.md`
  reserves for post-testnet + real-verifier + zero-open-P0/P1).

### Deprecated

### Removed
- Committed snapshot binaries `system-description.pdf`, `system-description.txt`,
  and `web3-demo.zip` (P3-18) — live source stays; frozen blobs dropped.

### Fixed
- **Settings signer status — review follow-ups** (adversarial review of the
  signing-explainer PR): `signerStatusLabel` now reports **`wallet connected`**
  when a wallet is actually connected (instead of always falling back to
  `connect to sign`); the relayer probe is **skipped when a dev-signer is active**
  (its result is never displayed then — no wasted up-to-8s round-trip); and the
  dead `.catchError` on `getRelayerInfo()` (which never rejects) was removed.
- **Documentation truth-up** — purged stale references to the deleted React/Vite
  frontend across `README.md`, `INSTRUCTIONS.md`, `codes/README.md`,
  `docs/architecture/system-overview.md`, `docs/project/STATUS.md`,
  `docs/project/ROADMAP.md`, and `docs/improvements/` (the docs now describe the
  Tessera Flutter client, all six voting modules, current test counts, and the
  existing CI). Closed/MOOT statuses synced to reality (P0-*, P2-*, P3-15..18).

### Security
- **`registerVoters` batch cap lowered 100 → 50** (`ZkAnonVoting`, P1-13) so a full
  batch fits a 30M mainnet block (~24.5M gas; 100 ≈ 50M is unreachable). Test
  boundary and `module-m1-anon-voting.md` updated; full suite green (268).
- **P1 contract-hardening pass verified complete** (P1-5..P1-12): OZ
  `Initializable` + `Ownable` on every module, custom errors throughout,
  `ZkAirdrop` `ReentrancyGuard` + `endClaiming`/`withdrawUnclaimed` escape hatch,
  unified `0.8.28` pragma, anon-vote `≥1`-voter + batch-cap invariants. The stale
  "Open" statuses in `findings.md` / `improvements/README.md` were corrected to
  Done.

---

## [0.2.0] — 2026-06-02

### Added
- **Tessera — unified Flutter client** (`codes/mobile/`) across mobile, desktop,
  AND web, replacing per-platform frontends. Parity with the React app + more:
  - Browse / poll detail / **M2 blind-vote** (commit-reveal) / verify-receipts /
    **Create** (wallet or dev-signer).
  - **Identity** management (secure-storage Semaphore seed; vote prefill).
  - **Live-meeting**: organizer HOST dashboard (rotating signed-ticket QR +
    pending queue + face-to-face confirm = on-chain `registerVoter`) and the
    VOTER flow (ephemeral identity → confirmation code → register → vote).
  - **Desktop ZK proving** via an opt-in Node sidecar reusing the web prover
    bundle — verified against the real Groth16 vkey on Linux.
  - **Local dev-signer** (`DEV_PRIVATE_KEY`) that signs txs directly (bypasses
    WalletConnect for host-local Hardhat).
  - **Proximity (BLE/NFC)** capability-gated seam (Android radio impl device-pending).
- CI `mobile` job (analyze + test) as the Flutter release gate.

### Changed
- Project renamed **zkVote → Tessera**; visible + build identity updated.

### Deprecated

### Removed
- The **React/Vite frontend** (`codes/frontend/`) — the Flutter app is the sole
  client. The prover bundle is self-contained (`codes/mobile/web_prover/` has its
  own deps) and the deployed-addresses fixture moved to `codes/contracts/`.

### Fixed
- Linux desktop build: demote the strict-clang `-Werror` deprecation from
  `flutter_secure_storage_linux`'s vendored `json.hpp`.

### Security
- Identity seed + blind-vote salts + org keypair persisted via platform secure
  storage (Keychain / libsecret / DPAPI), never plaintext prefs.

---

## [0.x.x] — pre-release work

The project has not had a tagged release yet. The following major work landed on `main`:

- **Foundation:** modular architecture with `PollRegistry` + `IZkPoll` interface + EIP-1167 clones (Phase 0–1)
- **M1 — Anonymous Token Voting:** `ZkAnonVoting` contract + Semaphore integration + invite-token UX
- **M2 — Blind Voting:** `ZkBlindVoting` contract + commit-reveal UX + reveal-deadline countdown
- **`ZkAirdrop`:** standalone Semaphore-gated airdrop (untested)
- **Frontend:** registry-driven Home page, CreatePoll with module-type selector, Poll/BlindPoll pages, dark mode + visual design system
- **Docs:** `architecture/`, `framework/`, `standards/`, `archive/`, `project/`, `improvements/`

For the full prehistory, see `git log` and `archive/`.

---

## How to maintain this file

- Every PR that ships user-visible behavior change adds a line under the relevant subsection of `## [Unreleased]`.
- At release time (per `RELEASING.md`):
  1. Rename `## [Unreleased]` → `## [vX.Y.Z] — YYYY-MM-DD`.
  2. Add a fresh empty `## [Unreleased]` block at the top.
  3. Commit as part of the release commit.
- For deployed-network entries, include the deployed addresses or a link to the network-specific addresses file.
- Keep entries terse — one line each. The PR they came from has the long story.
- Don't backdate entries. If something shipped before this changelog existed, it lives under "[0.x.x] — pre-release work" or in `git log`, not invented as a versioned entry.
