# ZK Ballot & Lottery — PoC

A **Zero-Knowledge voting system with anonymous lottery** built on Semaphore Protocol v4.  
Voters register anonymously, cast votes, and one winner is drawn from the pool — with full privacy.

---

## Architecture

```
web3-demo/
├── contracts/   Solidity + Hardhat (smart contracts, tests, deploy script)
└── frontend/    React 19 + Vite + Wagmi (web UI)
```

### Smart Contract (`ZkVotingLottery.sol`)

| Phase | Description |
|-------|-------------|
| **Registration** (0) | Users submit their Semaphore identity commitment on-chain. |
| **Voting** (1) | Owner transitions to voting. Users cast anonymous votes with ZK proofs. |
| **Ended** (2) | Owner closes the poll, a pseudo-random lottery winner is drawn from voters' nullifiers. The winner proves ownership to claim a prize. |

Key properties:
- **Anonymity** – votes are linked to ZK nullifiers, not Ethereum addresses.
- **Double-vote prevention** – each nullifier can only be used once per poll.
- **Prize claim** – winner generates a fresh ZK proof specifying the receiver address.

> ⚠️ **PoC only** – the lottery randomness (`block.timestamp + prevrandao`) is NOT safe for production. Use Chainlink VRF on mainnet.

### Frontend (`App.tsx`)

Built with **React 19**, **Wagmi v3**, **Viem v2**, and **TailwindCSS v4**.

- Generates and persists a Semaphore identity in `localStorage`.
- Reads live poll state and vote tallies directly from the contract.
- Generates ZK proofs client-side with `@semaphore-protocol/proof` and submits them.
- Admin panel (owner only) to advance the poll phases.
- Automatic network validation — prompts user to switch to the Hardhat network.

---

## Prerequisites

| Tool | Version |
|------|---------|
| Node.js | ≥ 20 |
| npm | ≥ 9 |
| MetaMask browser extension | latest |

---

## Quick Start (local dev)

### 1 – Smart Contracts

```bash
cd contracts
npm install
npm test           # Run all tests (no internet needed — uses MockSemaphoreVerifier)
```

### 2 – Start the local Hardhat node

```bash
# In a dedicated terminal:
cd contracts
npm run node       # Starts JSON-RPC at http://127.0.0.1:8545
```

### 3 – Deploy the contracts

```bash
# In another terminal (while the node is running):
cd contracts
npm run deploy:local
```

Expected output:
```
ZkVotingLottery deployed to: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
```

> The address is **deterministic** on a fresh Hardhat node — it always matches the hardcoded value in `frontend/src/config.ts`.

### 4 – Start the frontend

```bash
cd frontend
npm install
npm run dev        # http://localhost:5173
```

### 5 – Configure MetaMask

Add the Hardhat network to MetaMask:

| Field | Value |
|-------|-------|
| Network Name | Hardhat Local |
| RPC URL | `http://127.0.0.1:8545` |
| Chain ID | `31337` |
| Currency | ETH |

Import one of the Hardhat test accounts using its private key (printed by `npm run node`).

---

## Full User Flow

```
1. Open http://localhost:5173
2. Click "Connect MetaMask"
3. Click "Generate Local Identity"   ← creates a Semaphore keypair in your browser
4. Click "Submit Commitment On-chain" ← registers you as a voter
   [Admin] Click "Start Voting"
5. Select Candidate A or B
6. Click "Generate Proof & Vote"      ← generates ZK proof, submits on-chain
   [Admin] Click "Close & Draw Lottery"
7. If you won, enter a receiver address and click "Verify & Claim Prize"
```

---

## Testing

### Contract tests

```bash
cd contracts
npm test
```

Tests use `MockSemaphoreVerifier` so no SNARK artifacts need to be downloaded:

| Test | Description |
|------|-------------|
| Should allow voters to register | Verifies `VoterRegistered` event |
| Should reject registration during voting phase | Phase transition guard |
| Should reject double voting via nullifier reuse | Nullifier uniqueness |
| Should execute a full ZK voting, lottery, and prize-claim flow | End-to-end happy path |

### Frontend (Playwright E2E)

> E2E tests require a running Hardhat node with deployed contracts AND a running frontend dev server.

```bash
# Terminal 1
cd contracts && npm run node

# Terminal 2
cd contracts && npm run deploy:local

# Terminal 3
cd frontend && npm run dev

# Terminal 4
cd frontend && npx playwright test
```

---

## Configuration

### `frontend/src/config.ts`

```ts
export const CONTRACT_ADDRESS = "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9";
```

This matches the deterministic address from a fresh Hardhat node.  
If you restart the node and redeploy, the address resets to the same value.

If you deploy to a different network, update `CONTRACT_ADDRESS` and the `chains` / `transports` in `createConfig`.

---

## Project Structure

```
contracts/
├── contracts/
│   ├── ZkVotingLottery.sol        Main contract
│   └── MockSemaphoreVerifier.sol  Test-only verifier (always returns true)
├── scripts/
│   └── deploy.ts                  Deployment script
├── test/
│   └── ZkVotingLottery.ts         Hardhat/Chai tests
└── hardhat.config.ts

frontend/
├── src/
│   ├── App.tsx                    Main React component
│   ├── config.ts                  Wagmi config + contract address
│   ├── main.tsx                   React entry point (WagmiProvider, QueryClientProvider)
│   ├── ZkVotingLottery.json       Contract ABI
│   └── index.css                  Tailwind base
├── tests/
│   └── e2e.spec.ts                Playwright E2E tests
└── vite.config.ts
```

---

## Security Notes

This is a **Proof of Concept** — do not use in production without the following changes:

1. **Lottery randomness** — replace `block.timestamp + prevrandao` with [Chainlink VRF](https://docs.chain.link/vrf).
2. **Group state** — the frontend maintains a local off-chain group mirror. In production, build it from `VoterRegistered` event history.
3. **MockSemaphoreVerifier** — the mock verifier in `contracts/contracts/MockSemaphoreVerifier.sol` is for local testing only. The deploy script uses the real `SemaphoreVerifier`.
4. **SNARK artifacts** — the production verifier requires SNARK artifacts from `snark-artifacts.pse.dev`. In a production frontend, ensure these are served from a trusted CDN or bundled locally.
