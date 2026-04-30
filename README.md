# ZK Voting Hub

A **Zero-Knowledge anonymous voting platform** built on Semaphore Protocol v4. Supports two voting modules — **Anonymous ZK Vote** and **Blind Commit-Reveal** — with an optional **Gasless Relayer** so voters can participate without a wallet.

## Architecture

```
web3-demo/
├── contracts/    Solidity + Hardhat — smart contracts, tests, deploy scripts
├── frontend/     React 19 + Vite — web UI with dark mode
├── relayer/      Express.js — gasless vote relayer service
└── docs/         Architecture docs, roadmap, improvement tracker
```

### Smart Contracts (Modular)

| Contract | Purpose |
|----------|---------|
| **PollRegistry** | EIP-1167 factory — creates poll clones via minimal proxies |
| **ZkAnonVoting** (M1) | Anonymous voting with Semaphore ZK proofs |
| **ZkBlindVoting** (M2) | Commit-reveal blind voting (no ZK required) |
| **ZkAirdrop** | Semaphore-gated anonymous ETH airdrop |

### Services

| Service | Port | Description |
|---------|------|-------------|
| Hardhat Node | 8545 | Local EVM blockchain (Chain ID 31337) |
| Frontend | 5173 | React app with Wagmi + Viem |
| Relayer | 3001 | Gasless vote relay API |
| Block Explorer | 3728 | Ethereum Lite Explorer |

## Quick Start (Docker)

```bash
docker compose up --build -d
```

Wait for logs to show "Contracts are fully deployed", then open:
- Frontend: `http://localhost:5173`
- Explorer: `http://localhost:3728`
- Relayer: `http://localhost:3001/api/relay/status`

## Quick Start (Manual — 3 terminals)

```bash
# Terminal 1 — Blockchain node
cd contracts && npm install && npx hardhat node

# Terminal 2 — Deploy contracts
cd contracts && npm run deploy:local && npm run copy-abis

# Terminal 3 — Frontend
cd frontend && npm install && npm run dev

# Optional: Terminal 4 — Relayer
cd relayer && npm install && npm start
```

## MetaMask Setup

| Field | Value |
|-------|-------|
| Network Name | Hardhat Local |
| RPC URL | `http://127.0.0.1:8545` |
| Chain ID | `31337` |
| Currency | ETH |

Import test account (Admin): `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

## Usage Workflow

### Admin Flow

1. Connect MetaMask (Admin account) → **Create Poll** → choose type (ZK or Blind)
2. **Generate Tokens** (ZK polls only) → distribute tokens to voters privately
3. **Start Voting** → voters can now vote
4. **Close Poll** → results locked on-chain

### Voter Flow — Via Relayer (no wallet needed)

1. Open poll link → paste invite token → **Load Identity**
2. Select **Relayer (No Wallet)** tab → choose option → **Vote**
3. ZK proof generates in browser → relayer submits to blockchain
4. Vote recorded anonymously — no wallet, no ETH, no on-chain identity

### Voter Flow — Direct (with wallet)

1. Connect MetaMask → paste invite token → **Load Identity**
2. Select **Direct (Wallet)** tab → choose option → **Cast Anonymous Vote**
3. Confirm in MetaMask → vote recorded on-chain

## Testing

```bash
# Contract unit tests
cd contracts && npm test

# E2E frontend tests
cd frontend && npx playwright test
```

## Tech Stack

| Layer | Technologies |
|-------|-------------|
| Blockchain | Hardhat, Solidity 0.8.34, Semaphore v4, OpenZeppelin Clones |
| Frontend | React 19, Vite 8, TailwindCSS 4, Wagmi 3, Viem 2 |
| Relayer | Express.js, ethers.js v6 |
| Infra | Docker Compose, Nix flake |

## Project Docs

- [Architecture](docs/architecture/system-overview.md)
- [Roadmap](docs/project/ROADMAP.md)
- [Changelog](docs/project/CHANGELOG.md)
- [Improvement Tracker](docs/improvements/findings.md)
