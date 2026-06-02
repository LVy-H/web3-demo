# Tessera

One Flutter app for **anonymous on-chain voting** across **mobile, desktop, and web**.
The canonical client for the modular ZK-voting dApp (Semaphore v4). Replaces the
legacy React frontend (`../frontend`, deprecated).

## Features

- **Browse / poll detail** — live on-chain phase + tally.
- **M1 anon-vote** — Semaphore membership proof, gasless relay.
- **M2 blind-vote** — commit-reveal (hash-based, no SNARK).
- **Verify / receipts** — `isNullifierUsed` participation check.
- **Create** — deploy a poll via a wallet or the local dev-signer.
- **Identity** — manage a Semaphore seed in platform secure storage.
- **Live-meeting** — organizer HOST dashboard (rotating QR + face-to-face confirm)
  and the VOTER flow (ephemeral identity → confirmation code → vote).
- **Settings** — network / signer / proving / version diagnostics.

## Run

```sh
# bring up the local stack first (Hardhat node + relayer + a demo poll):
../../dev-stack.sh up        # from repo root

flutter run -d linux         # or: -d chrome, -d <android-serial>
```

### Local dev-signer (no wallet needed)
A phone wallet can't reach the host-local Hardhat node, so for local dev pass a
Hardhat key — the app signs + broadcasts directly (Create + all voting actions):

```sh
flutter run -d linux \
  --dart-define RPC_URL=http://127.0.0.1:8545 \
  --dart-define REGISTRY_ADDRESS=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 \
  --dart-define DEV_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

### Desktop ZK proving (opt-in Node sidecar)
Desktop generates real Semaphore proofs by spawning Node on the same prover
bundle the web build uses:

```sh
flutter run -d linux \
  --dart-define DESKTOP_PROVER_SIDECAR=$PWD/web_prover/desktop_prover.mjs \
  --dart-define DESKTOP_PROVER_BUNDLE=$PWD/web/zkprover.js \
  --dart-define DEV_PRIVATE_KEY=0x...
```

## Test

```sh
flutter analyze
flutter test                              # unit + widget + (self-skipping) integration
RUN_DESKTOP_PROVER=1 flutter test \
  test/integration/desktop_prover_test.dart   # proves a desktop proof vs the real vkey
```

The on-chain integration tests under `test/integration/` self-skip when the local
stack isn't running, so `flutter test` is green in CI.

## Architecture

MVVM + Repository, `go_router`, `provider`. Data layer reuses the relayer HTTP API
+ contract ABIs as the cross-client contract; the cross-client crypto core
(`ticket` / `confirmationCode` / `orgKeypair` / blind commit) is byte-identical to
the TS reference. ZK proving is behind a `ProofService` seam: web (`dart:js_interop`),
desktop (Node sidecar), mobile (webview, device-pending). See
`../../docs/superpowers/specs/2026-06-02-tessera-unify-flutter-design.md`.
