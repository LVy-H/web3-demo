# Tessera — modular zero-knowledge voting

A modular, privacy-preserving on-chain voting platform built on the Semaphore
Protocol (v4), with an optional gasless/sponsored relayer. A central
`PollRegistry` factory deploys per-poll EIP-1167 minimal proxies for **six
registered voting modules** — anonymous, blind (commit-reveal), approval,
ranked-choice, quadratic, and survey. A standalone `ZkAirdrop` contract reuses
Semaphore for one-shot anonymous claims and is intentionally **not** part of the
registry.

The sole client is the Flutter workspace in `codes/app/` — one codebase across
mobile, desktop, and web (shell at `codes/app/apps/tessera/`).

## Quick start (local, 4 terminals)

```bash
# Terminal 1 — local chain
cd contracts && npm install && npm run node

# Terminal 2 — deploy contracts to the running node
cd contracts && npm run deploy:local

# Terminal 3 — the Tessera app (Flutter; canonical client for mobile/desktop/web)
cd app/apps/tessera && flutter run -d linux   # or -d chrome, -d <android-serial>

# Terminal 4 (optional) — gasless relayer (http://localhost:3001)
cd relayer && npm install && npm start

# Terminal 5 (optional) — Flutter tests
cd app && dart run melos run test
```

> Tip: `../dev-stack.sh up` does node → deploy → demo poll → relayer in one step.

`deploy:local` writes addresses to `codes/contracts/deployed-addresses.json`.
The React frontend has been removed — the Flutter app (`codes/app`) is the
sole client.

## Architecture at a glance

```
PollRegistry (factory, EIP-1167 clones) — six registered module types
├── ZkAnonVoting       — M1: Semaphore anonymous (single choice + nullifier)
├── ZkBlindVoting      — M2: commit-reveal, no Semaphore dependency
├── ZkApprovalVoting   — multi-select bitmask ballot
├── ZkRankedVoting     — ranked-choice (instant-runoff tally computed in Dart)
├── ZkQuadraticVoting  — credit allocation (CREDITS=100, sum of squares ≤ 100)
└── ZkSurveyVoting     — multi-question "Google-Forms"; one ballot per survey

ZkAirdrop              — standalone, uses Semaphore directly (not registered)

Relayer (optional)     — Express service; submits the SNARK-message votes
                         (anon / approval / ranked / quadratic / survey) and
                         airdrop claims on behalf of voters, plus a sponsored
                         (wallet-free) poll lifecycle. See ./relayer/README.md.
```

The app's VOTE-space DIRECTORY tab reads the opt-in listed polls from
`PollRegistry.getListedPolls()` (polls are unlisted by default — private polls
are joined by link/QR). Opening `/poll/<address>` resolves the poll's module
type on-chain (`PollModuleResolver` in
`codes/app/apps/tessera/lib/routing/`) and hosts the matching voter journey
screen — the module type is never trusted from the URL.

## Optional: gasless voting via relayer

`codes/relayer/` is an Express service that signs and submits ZK vote /
airdrop transactions on behalf of a voter, so the voter needs neither a
wallet nor ETH. Voters still generate their ZK proof client-side — the
relayer cannot see who they are and cannot alter the vote (the option /
answers are bound into the proof's `message` field, enforced on-chain). It
can only refuse to forward.

The relayer also provides a **sponsored** (wallet-free) poll lifecycle
(create / register / start) so non-technical users never touch a wallet.

In the app, casting a vote always runs in two steps: prove (client-side) then
relay — the vote screen shows `GENERATING PROOF…` then `SUBMITTING…`. The
relayer URL is configured via `AppConfig.relayerUrl`; the Settings screen shows
the active host.

Trust model and API reference: [`./relayer/README.md`](./relayer/README.md).

## Tests & CI

- Contracts: `cd contracts && npm test` (Hardhat — 268 passing).
- Relayer: `cd relayer && npm test` (Vitest — 96 passing, 2 skipped).
- Flutter: `cd app && dart run melos run analyze` and `dart run melos run test`.

CI (`.github/workflows/ci.yml`) runs three jobs — contracts, relayer, and
app. The **app** job (melos format/analyze/test across every workspace package
+ `flutter build web`) is the canonical-client release gate.

> Local dev and CI use `MockSemaphoreVerifier` (an always-true verifier), so no
> SNARK artifacts are needed. Public networks require the real Groth16
> `SemaphoreVerifier` (`USE_REAL_VERIFIER=true`; tracked as P4-23/P4-24).

## Documentation

- Full architecture: [`../docs/architecture/system-overview.md`](../docs/architecture/system-overview.md)
- Current project status: [`../docs/project/STATUS.md`](../docs/project/STATUS.md)
- Contributor backlog: [`../docs/improvements/README.md`](../docs/improvements/README.md)
- Relayer service: [`./relayer/README.md`](./relayer/README.md)

Per-module deep dives live alongside the overview in `../docs/architecture/`:
[`module-m1-anon-voting.md`](../docs/architecture/module-m1-anon-voting.md),
[`module-m2-blind-voting.md`](../docs/architecture/module-m2-blind-voting.md),
[`module-approval.md`](../docs/architecture/module-approval.md),
[`module-ranked.md`](../docs/architecture/module-ranked.md),
[`module-quadratic.md`](../docs/architecture/module-quadratic.md),
[`module-survey.md`](../docs/architecture/module-survey.md), and
[`module-airdrop.md`](../docs/architecture/module-airdrop.md).

## Wallets & signing (local dev)

The default local flow needs **no wallet**: contracts are deployed with the
deterministic Hardhat key, and votes are submitted through the dev-signer
(`DEV_PRIVATE_KEY`) or the sponsored relayer. MetaMask is only relevant to the
optional desktop/web WalletConnect (Reown) path.

If you do connect a wallet for the WalletConnect path, add a custom network for
the local Hardhat node:

| Field | Value |
| --- | --- |
| Network name | Hardhat Local |
| RPC URL | `http://127.0.0.1:8545` |
| Chain ID | `31337` |
| Currency symbol | ETH |

Import one of the deterministic Hardhat test accounts (printed by
`npm run node`) to get a funded wallet. Reset the account's transaction
history in MetaMask whenever you restart the local node — nonces will
otherwise drift.
