# Relayer — Gasless Vote Relay Service

Express.js backend that submits ZK voting transactions on behalf of voters, enabling **gasless anonymous voting** without requiring a wallet or ETH.

## How It Works

```
Browser (voter)          Relayer (server)           Blockchain
     │                        │                         │
     │  1. Generate ZK proof  │                         │
     │     (client-side WASM) │                         │
     │                        │                         │
     │  2. POST /api/relay/vote                         │
     │  ─────────────────────>│                         │
     │   {pollAddress, vote,  │  3. Validate + pre-check│
     │    proof}              │     (nullifier, state)  │
     │                        │                         │
     │                        │  4. Sign & send tx      │
     │                        │  ────────────────────>  │
     │                        │     castVote(vote,proof) │
     │                        │                         │
     │                        │  5. Wait for receipt    │
     │  6. {txHash}           │  <────────────────────  │
     │  <─────────────────────│                         │
```

The voter's identity is never exposed — the relayer only sees the ZK proof, which reveals nothing about who the voter is.

## Stack

| Library | Purpose |
|---------|---------|
| Express.js | HTTP server |
| ethers.js v6 | Blockchain interaction + tx signing |
| express-rate-limit | Rate limiting (20 req/min/IP) |
| cors | Cross-origin requests from frontend |
| dotenv | Environment configuration |

## API Endpoints

### `POST /api/relay/vote`

Relay an anonymous vote to a ZkAnonVoting poll.

**Request:**
```json
{
  "pollAddress": "0x...",
  "vote": 0,
  "proof": {
    "merkleTreeDepth": "20",
    "merkleTreeRoot": "123...",
    "nullifier": "456...",
    "message": "0",
    "scope": "789...",
    "points": ["...8 elements..."]
  }
}
```

**Response (success):**
```json
{ "success": true, "txHash": "0x..." }
```

**Response (error):**
```json
{ "error": "This vote token has already been used (nullifier consumed)" }
```

### `POST /api/relay/claim-airdrop`

Relay an anonymous airdrop claim.

**Request:**
```json
{
  "airdropAddress": "0x...",
  "receiver": "0x...",
  "proof": { ... }
}
```

### `GET /api/relay/status`

Check relayer health and balance.

**Response:**
```json
{
  "relayer": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  "balance": "9989.99",
  "rateLimitPerMinute": 20
}
```

## Running Locally

```bash
cp .env.example .env   # Edit if needed
npm install
npm start              # Starts on port 3001
```

## Running via Docker

The relayer is included in the root `docker-compose.yml`:

```bash
docker compose up --build -d
```

The relayer connects to the Hardhat node at `http://contracts:8545` (Docker internal network).

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RPC_URL` | `http://127.0.0.1:8545` | Ethereum JSON-RPC endpoint |
| `RELAYER_PRIVATE_KEY` | Hardhat Account #0 | Private key of the hot wallet that pays gas |
| `PORT` | `3001` | HTTP server port |

## Security Features

- **Rate limiting**: 20 requests per minute per IP
- **Nullifier pre-check**: Checks on-chain before sending tx (saves gas on duplicates)
- **Poll state check**: Rejects votes if poll is not in Voting phase
- **Vote index validation**: Rejects invalid option indices
- **Balance monitoring**: Returns error if relayer wallet is low on funds
- **Proof format validation**: Validates all proof fields before relay

## Trust Model

The voter does NOT need to trust the relayer because:
- Relayer cannot see who the voter is (ZK proof hides identity)
- Relayer cannot change the vote (proof.message == vote, enforced on-chain)
- Relayer cannot vote twice (nullifier prevents double-vote)
- Relayer can only: (a) forward correctly, or (b) refuse to forward (censorship)
- If the relayer refuses, the voter can always fall back to voting directly with a wallet
