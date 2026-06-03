# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: see [VERSIONING.md](./VERSIONING.md).

## [Unreleased]

### Added
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

### Deprecated

### Removed

### Fixed

### Security

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
