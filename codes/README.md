# Anonymous Web3 Voting System

A modular zero-knowledge voting platform on Ethereum. A central `PollRegistry`
factory deploys per-poll EIP-1167 minimal proxies for two voting modules —
**M1 anonymous voting** (Semaphore-based ZK group membership) and
**M2 blind voting** (commit-reveal). A standalone `ZkAirdrop` contract reuses
Semaphore for one-shot anonymous claims and is intentionally not part of the
registry.

## Quick start (local, 4 terminals)

```bash
# Terminal 1 — local chain
cd contracts && npm install && npm run node

# Terminal 2 — deploy contracts to the running node
cd contracts && npm run deploy:local

# Terminal 3 — frontend dev server (http://localhost:5173)
cd frontend && npm install && npm run dev

# Terminal 4 (optional) — gasless relayer (http://localhost:3001)
cd relayer && npm install && npm start

# Terminal 5 (optional) — end-to-end tests
cd frontend && npx playwright test
```

`deploy:local` writes addresses to `frontend/src/deployed-addresses.json`,
which the dev server picks up automatically.

## Architecture at a glance

```
PollRegistry (factory, EIP-1167 clones)
├── ZkAnonVoting   — M1: Semaphore group membership + nullifier
└── ZkBlindVoting  — M2: commit-reveal, no Semaphore dependency

ZkAirdrop          — standalone, uses Semaphore directly (not registered)

Relayer (optional) — Express service, submits M1 votes / airdrop claims
                     on behalf of voters so they don't need a wallet or ETH.
                     See ./relayer/README.md.
```

Frontend reads polls from `PollRegistry.getAllPolls()`, then a `PollRouter`
component reads each poll's module type and renders `Poll.tsx` (M1) or
`BlindPoll.tsx` (M2).

## Optional: gasless voting via relayer

`codes/relayer/` is an Express service that signs and submits ZK vote /
airdrop transactions on behalf of a voter, so the voter needs neither a
wallet nor ETH. Voters still generate their ZK proof client-side — the
relayer cannot see who they are and cannot alter the vote (the option
index is bound into the proof's `message` field, enforced on-chain).

The relayer is **off by default**. Skip Terminal 4 above and the frontend
falls back to direct wallet voting only. When the relayer is running, the
frontend exposes an additional "Relayer (No Wallet)" tab on the vote UI.

Trust model and API reference: [`./relayer/README.md`](./relayer/README.md).

## Documentation

- Full architecture: [`../docs/architecture/system-overview.md`](../docs/architecture/system-overview.md)
- Current project status: [`../docs/project/STATUS.md`](../docs/project/STATUS.md)
- Contributor backlog: [`../docs/improvements/README.md`](../docs/improvements/README.md)
- Relayer service: [`./relayer/README.md`](./relayer/README.md)

Per-module deep dives live alongside the overview in
`../docs/architecture/` (`module-m1-anon-voting.md`,
`module-m2-blind-voting.md`, `module-airdrop.md`).

## MetaMask setup

Add a custom network for the local Hardhat node:

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
