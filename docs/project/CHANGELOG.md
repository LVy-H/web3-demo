# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: see [VERSIONING.md](./VERSIONING.md).

## [Unreleased]

### Added

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
