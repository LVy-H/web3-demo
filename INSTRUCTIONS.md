# System Usage & Workflow Instructions

Complete guide to launching and using the ZK Voting Hub system.

## Prerequisites

- **Docker** and **Docker Compose** installed
- **MetaMask** browser extension (for admin; optional for voters using relayer)

## 1. Starting the Environment

```bash
cd web3-demo
docker compose up --build -d
```

This starts 4 services:

| Service | Port | Description |
|---------|------|-------------|
| `contracts` | 8545 | Hardhat node + auto-deploys all contracts |
| `frontend` | 5173 | Vite dev server (React app) |
| `relayer` | 3001 | Gasless vote relay API |
| `explorer` | 3728 | Ethereum Lite Block Explorer |

Wait for contracts deployment (~30s). Verify with:

```bash
docker compose logs contracts | grep "Contracts are fully deployed"
```

## 2. MetaMask Configuration

### Add Hardhat Network

1. MetaMask > Settings > Networks > Add Network
2. Fill in:
   - **Network Name**: `Hardhat Local`
   - **RPC URL**: `http://127.0.0.1:8545`
   - **Chain ID**: `31337`
   - **Currency Symbol**: `ETH`

### Import Admin Account (#0)

Private key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

This account has ~10,000 ETH and is the deployer/owner of all contracts.

### Import Voter Account (#1) — optional

Private key: `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d`

Use this for testing direct wallet voting. Not needed if using the relayer.

## 3. Admin Workflow — Anonymous ZK Poll

### Step 1: Create Poll

1. Open `http://localhost:5173` (or WSL IP if using WSL2)
2. Connect MetaMask with Admin account
3. Click **Create Poll** in navigation
4. Fill in title, description, at least 2 options
5. Select **Anonymous (ZK)** poll type
6. Click **Create Poll** → Confirm in MetaMask
7. Wait for redirect to Dashboard

### Step 2: Generate Invite Tokens

1. Click into the poll you just created
2. In the **Admin Panel** (right column, amber border):
   - Set number of tokens (e.g. 5)
   - Click **Generate N Tokens** → Confirm in MetaMask
3. Token list appears in dark box
4. Click **Copy All** and save the tokens
5. Distribute tokens privately to voters (via chat, email, etc.)

### Step 3: Start Voting

1. In Admin Panel, click **Start Voting** → Confirm in MetaMask
2. Poll transitions from Registration to Voting phase
3. Voters can now cast votes

### Step 4: Close Poll

1. When ready, click **Close Poll** → Confirm in MetaMask
2. Results are locked on-chain permanently

## 4. Voter Workflow — Via Relayer (No Wallet)

This flow requires NO MetaMask, NO ETH, NO wallet at all.

1. Open the poll link sent by admin
2. In the **Identity** section, paste the invite token you received
3. Click **Load Identity** → shows "Identity Ready"
4. In the **Cast Your Vote** section:
   - Click the **Relayer (No Wallet)** tab (purple)
   - See message: "Your vote will be submitted anonymously via the relayer service"
5. Select your preferred option
6. Click **Vote via Relayer (No Wallet)**
7. Wait for:
   - "Generating zero-knowledge proof..." (~5-15 seconds)
   - "Sending vote to relayer service..."
   - "Vote relayed successfully! Tx: 0x..."
8. Done — your vote is recorded anonymously on the blockchain

## 5. Voter Workflow — Direct (With Wallet)

1. Switch MetaMask to a voter account
2. Open the poll page
3. Paste invite token → **Load Identity**
4. Keep the **Direct (Wallet)** tab selected (teal)
5. Select option → Click **Cast Anonymous Vote**
6. Confirm in MetaMask
7. Wait for confirmation

## 6. Admin Workflow — Blind Commit-Reveal Poll

### Create

Same as ZK poll but select **Blind (Commit-Reveal)** type and set a Reveal Duration.

### Voter Registration (Registration Phase)

Voters connect their wallet and click **Register** — no invite tokens needed.

### Voting (Voting Phase)

1. Admin clicks **Start Voting**
2. Voters select option → click **Commit Vote**
3. A hash commitment is submitted (vote is hidden)
4. Salt is saved in browser localStorage — **do not clear browser data**

### Reveal (Reveal Phase)

1. Admin clicks **End Voting** — starts the reveal timer
2. Voters click **Reveal Vote** before the timer expires
3. Unrevealed votes are excluded from results

### Finalize

Admin clicks **Finalize Results** after the reveal window closes.

## 7. Viewing Results

- **Dashboard** (`/`): shows all polls with stats
- **Poll page**: right column has live results with animated bar charts
- **Block Explorer** (`http://localhost:3728`): view all on-chain transactions

## 8. System Management

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Rebuild after code changes
docker compose up --build -d

# View logs
docker compose logs contracts --tail 20
docker compose logs frontend --tail 20
docker compose logs relayer --tail 20

# Check relayer health
curl http://localhost:3001/api/relay/status
```

## 9. Troubleshooting

| Problem | Solution |
|---------|----------|
| Frontend shows white page | Open DevTools (F12) > Console, check for errors. Try clearing localStorage |
| MetaMask "Nonce too high" | MetaMask > Settings > Advanced > Clear activity tab data |
| Poll created but not visible | Verify `VITE_RPC_URL` points to correct Hardhat node |
| Relayer returns 503 | Relayer wallet is low on funds. Check with `/api/relay/status` |
| WSL2: localhost not accessible | Use WSL2 IP instead (run `ip addr show eth0` in WSL) |

## Hardhat Test Accounts

| Account | Address | Private Key |
|---------|---------|-------------|
| #0 (Admin) | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| #1 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| #2 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |

Each account has 10,000 ETH on a fresh Hardhat node.
