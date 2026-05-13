# Using the Voting Hub — End-user / Demo-runner Guide

What you are going to do: connect a wallet (or skip it via the Relayer),
register an anonymous identity, cast a vote in either an **M1 anonymous
poll** or an **M2 blind (commit-reveal) poll**, then read the tallied
results. Two voting modules + one optional gasless relayer; one UI.

This file documents the **runtime user flow**. For architecture, contract
layout, and developer docs, start at [`codes/README.md`](codes/README.md)
and the index in [`README.md`](README.md).

---

## Prerequisites

| Requirement                 | Notes                                                                                                                |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Node.js **22.x**            | LTS is fine. Check with `node --version`.                                                                            |
| npm **9+**                  | Ships with Node 22.                                                                                                  |
| Browser                     | Any modern browser. Chrome / Firefox tested.                                                                         |
| MetaMask                    | **Optional.** Only needed for Flow A/B in *Direct (Wallet)* mode. Flow C (Relayer) works with no wallet at all.      |

The local stack runs entirely on `http://localhost` — Hardhat node on
`8545`, Vite dev server on `5173`, optional relayer on `3001`.

---

## Setup (one-time)

Install dependencies for both packages. The full multi-terminal runbook
(start node, deploy contracts) lives in
[`codes/README.md`](codes/README.md) — do not duplicate it here; come
back once contracts are deployed and the frontend dev server is up.

```bash
# Contracts
cd codes/contracts && npm install

# Frontend
cd codes/frontend && npm install
```

Then follow the **Quick start** in
[`codes/README.md`](codes/README.md#quick-start-local-4-terminals) to:

1. Start the Hardhat node (`npm run node` in `codes/contracts/`).
2. Deploy contracts to it (`npm run deploy:local` in `codes/contracts/`).
3. Start the dev server (`npm run dev` in `codes/frontend/`).

The deploy step writes addresses into
`codes/frontend/src/deployed-addresses.json`, which the dev server picks
up automatically. Open [`http://localhost:5173`](http://localhost:5173)
when all three are running.

> **MetaMask network setup** (skip if using *Test Account* or Relayer):
> Add a custom network — RPC `http://127.0.0.1:8545`, chain ID `31337`,
> currency `ETH`. Import any Hardhat test private key printed by
> `npm run node` to get a funded wallet. Full table in
> [`codes/README.md`](codes/README.md#metamask-setup).

---

## Flow A — Anonymous vote (M1)

M1 uses [Semaphore v4](https://docs.semaphore.pse.dev/) group membership.
You register a commitment to a group, then prove "I am in this group" via
a zero-knowledge proof when you vote. The chain learns *that* a member
voted, never *which* one.

### 1. Connect

Open [`http://localhost:5173`](http://localhost:5173) and use **one** of:

- **Test Account** (top-right, dev build only) — connects a wagmi `mock`
  connector wired to Hardhat account `#0`. No wallet, no popup, no gas
  confirmations. This is what the Playwright E2E suite drives.
- **Connect Wallet** — opens MetaMask. If you are on the wrong chain a
  yellow "Switch to Hardhat Network" banner appears.

_[screenshot: header with Test Account and Connect Wallet buttons]_

### 2. Create or open an M1 poll

From the **Dashboard** (`/`), either:

- Click **Create Poll**, pick **M1 — Anonymous voting**, set a question
  and 2–4 options, submit. The factory (`PollRegistry`) deploys an
  EIP-1167 clone of `ZkAnonVoting` and you land on its page.
- Or click any existing M1 poll tile to open it directly.

### 3. Register

In the voter panel, click **Generate Local Identity**. This creates a
Semaphore keypair in your browser `localStorage`, keyed by your wallet
address so multiple test accounts don't collide. Then click
**Register**. The transaction adds your identity commitment to the
poll's Semaphore group.

> The poll creator is the admin. They click **Start Voting** to move the
> poll from `Registration` to `Voting`. Until they do, the vote button
> stays disabled.

_[screenshot: voter panel showing Generate Local Identity → Register flow]_

### 4. Vote

Pick an option. Click **Vote**. The browser generates a Groth16 SNARK
proof client-side (the `MockSemaphoreVerifier` accepts any proof on
local dev — see [Troubleshooting](#troubleshooting)). MetaMask prompts
to send `castVote(option, proof)`; confirm. The on-chain contract
re-verifies the proof, records the nullifier so you cannot vote twice,
and increments the tally.

### 5. Results

The results panel updates live via the contract's `VoteCast` event. The
admin clicks **End Voting** to seal the tally; the UI then shows the
final counts and the winning option.

---

## Flow B — Blind vote (M2)

M2 uses a **commit-reveal** scheme — no SNARK. You first commit a hash
of `(your option, your secret)` during the commit phase, then reveal the
plaintext during the reveal phase. Tallies are only computable after
reveal. Trades off ZK anonymity for simpler crypto and no trusted setup.

The phases:

| Phase          | Admin action       | Voter action                                |
| -------------- | ------------------ | ------------------------------------------- |
| Registration   | (initial state)    | **Register** — claim a voter slot.          |
| Voting         | **Start Voting**   | **Commit** — submit `keccak256(option‖salt)`. |
| Reveal         | **End Voting**     | **Reveal** — submit `(option, salt)`.       |
| Tally          | (auto on deadline) | Read results panel.                         |

### 1. Connect & open a blind poll

Same as M1, then open or create a poll with module **M2 — Blind voting**.

### 2. Register

Click **Register**. M2 does not need a Semaphore identity; the contract
just tracks `address → registered` to cap who can commit.

### 3. Commit (during the Voting phase)

Pick an option. Click **Commit Vote**. The frontend generates a random
32-byte salt, stores `(option, salt)` in `localStorage`, and submits the
hash on-chain. The poll cannot see your choice yet.

### 4. Reveal (after admin runs **End Voting**)

Reveal-phase opens. Click **Reveal Vote**. The frontend reads `(option,
salt)` from `localStorage` and submits them; the contract recomputes
the hash, matches it to your stored commitment, and increments the
tally for the revealed option.

> **Do not clear `localStorage` between commit and reveal.** Without the
> salt you cannot reveal and your vote is lost. The reveal deadline
> shown in the UI is enforced on-chain — past it, your commitment is
> dead.

### 5. Results

Same panel as M1 — live `VoteRevealed` events, sealed totals once the
reveal deadline passes.

---

## Flow C — Optional gasless vote via Relayer

The relayer is an Express service in [`codes/relayer/`](codes/relayer/)
that submits your M1 vote (or airdrop claim) on-chain for you. **You
still generate the proof client-side** — the relayer never learns your
identity and cannot tamper with your vote (the option index is bound
into `proof.message`, enforced on-chain). It can only refuse to
forward.

### When to use it

- You want to try the demo without installing MetaMask.
- You want to demonstrate that the voter never has to hold ETH.
- You are running a kiosk-style demo where a single relayer wallet pays
  for many voters.

### Start the relayer

In a fourth terminal:

```bash
cd codes/relayer
cp .env.example .env   # defaults are fine for local dev
npm install
npm start              # listens on http://localhost:3001
```

Health check:

```bash
curl http://localhost:3001/api/relay/status
```

Full runbook, API surface, and trust model:
[`codes/relayer/README.md`](codes/relayer/README.md).

### Toggle the UI

When the relayer is reachable, the M1 poll page shows two tabs in the
vote panel:

- **Direct (Wallet)** — voter signs and pays gas. Default.
- **Relayer (No Wallet)** — voter generates proof, POSTs it to
  `/api/relay/vote`, relayer signs + sends the tx.

If `/api/relay/status` does not respond, the tabs collapse to
*Direct (Wallet)* only.

The frontend reads the relayer URL from `VITE_RELAYER_URL` (default
`http://localhost:3001`). Unset it to hide the tab entirely.

> Flow C is M1-only. M2 has no SNARK and no nullifier; gasless commit/
> reveal would require a different design (signed messages) that is not
> implemented.

---

## Troubleshooting

**Transactions fail immediately after restarting the Hardhat node.**
Hardhat resets state on every `npm run node`, but MetaMask still
remembers stale nonces. In MetaMask: *Settings → Advanced → Clear
activity tab data* (or *Reset Account*). Then refresh the dApp.

**"Could not find deployed addresses for chainId 31337"** in the
frontend. You started the dev server before `npm run deploy:local`
finished, or you restarted the Hardhat node and the addresses file is
now stale. Re-run `npm run deploy:local` in `codes/contracts/`.

**The dev server works, but `npm run build` (production) renders an
empty page.** Vite production builds enforce stricter env-var checks.
For Sepolia or any non-Hardhat target, you must set `VITE_NETWORK` and
`VITE_RPC_URL` (see `codes/frontend/.env.example`). The dev build falls
back to localhost defaults; the production build does not.

**`USE_REAL_VERIFIER` and `MockSemaphoreVerifier`.** `deploy:local`
deploys a `MockSemaphoreVerifier` that accepts any proof — this is the
fast path for local dev and CI. Public networks (Sepolia, mainnet)
require `USE_REAL_VERIFIER=true` plus the real-verifier wiring (tracked
as `P4-23` / `P4-24` in `docs/improvements/findings.md`). Until that
lands, `deploy:sepolia` will refuse to run. Full Sepolia runbook:
[`codes/contracts/README.md`](codes/contracts/README.md#deploy-to-sepolia).

**Relayer tab does not appear in the UI.** Confirm
`curl http://localhost:3001/api/relay/status` returns JSON. If not, the
relayer process is not running or `VITE_RELAYER_URL` points somewhere
else. The frontend silently hides the tab when the health check fails —
that is by design.

**Relayer responds with `Relayer balance too low to cover gas`.** The
hot wallet is empty. For local dev, restart the Hardhat node (the
default `RELAYER_PRIVATE_KEY` is Hardhat account `#0`, which respawns
funded). For Sepolia, top up the deployer/relayer address from a
faucet.

---

## What's next

- **Architecture deep dive** — [`docs/architecture/system-overview.md`](docs/architecture/system-overview.md)
  plus the per-module files (`module-m1-anon-voting.md`,
  `module-m2-blind-voting.md`, `module-airdrop.md`). The relayer
  subsection lands with `F-10`.
- **Deploy to a real testnet** — Sepolia runbook in
  [`codes/contracts/README.md`](codes/contracts/README.md#deploy-to-sepolia).
- **Backlog and known gaps** — [`docs/improvements/findings.md`](docs/improvements/findings.md)
  (`P4-23` / `P4-24` for real-verifier wiring, plus the open priority bands).
- **Issues** — file bugs and feature requests against the repo's GitHub
  issue tracker.
