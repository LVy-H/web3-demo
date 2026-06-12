# Relayer — gasless vote submission

Express service that signs and submits M1 anonymous votes and ZK airdrop
claims on behalf of voters, so voters need neither a wallet nor ETH. The
voter still generates the ZK proof client-side; the relayer forwards it.

## How it works

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
     │                        │     castVote(vote,proof)│
     │                        │                         │
     │                        │  5. Wait for receipt    │
     │  6. {txHash}           │  <────────────────────  │
     │  <─────────────────────│                         │
```

The relayer only ever sees the ZK proof. The proof reveals the nullifier
and Merkle root but nothing about which group member produced it.

## Stack

| Library            | Purpose                                       |
| ------------------ | --------------------------------------------- |
| Express.js         | HTTP server                                   |
| ethers v6          | Tx signing + RPC reads                        |
| express-rate-limit | 20 req/min/IP                                 |
| cors               | Cross-origin requests from the frontend       |
| dotenv             | Environment configuration                     |

## API endpoints

### `POST /api/relay/vote` — relay an M1 anonymous vote

Request:

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

Success:

```json
{ "success": true, "txHash": "0x..." }
```

Error (one of):

```json
{ "error": "This vote token has already been used (nullifier consumed)" }
{ "error": "Poll is not in Voting phase" }
{ "error": "Invalid option index" }
{ "error": "Relayer balance too low to cover gas" }
```

### `POST /api/relay/claim-airdrop` — relay an anonymous airdrop claim

Request:

```json
{
  "airdropAddress": "0x...",
  "receiver": "0x...",
  "proof": { "...": "same shape as above" }
}
```

`receiver` is bound into the proof's scope on the client, so the relayer
cannot redirect the airdrop to a different address. The on-chain verifier
rejects any mismatch.

Success: `{ "success": true, "txHash": "0x..." }`.

### `GET /api/relay/status` — health + hot-wallet balance

Response:

```json
{
  "relayer": "0xf39F...2266",
  "balance": "9989.99",
  "rateLimitPerMinute": 20
}
```

The frontend polls this endpoint to decide whether to expose the "Relayer
(No Wallet)" tab.

### Live Meeting Vote — ticket queue (S1.2)

> **Versioned API contract.** These four endpoints are the coordination channel
> between the wallet-free voter page and the organizer's host dashboard. Both
> the web app and any future Flutter client consume them — keep the shapes
> stable. All sit under `/api/relay/tickets` (behind the same rate limiter).
>
> **Registration is NOT done here.** On-chain `registerVoter` is `onlyOwner`, so
> the **organizer's browser wallet** registers voters. The relayer only tracks
> tickets — `redeem` marks a ticket consumed; it does not touch the chain. This
> overrides the original design doc's `/relay/register`.
>
> State is **in-memory and per-poll** — lost on relayer restart (fine for a
> single live meeting; persistence is a Sprint 2 concern, open-Q3). The `queue`
> endpoint is currently unauthenticated; it only exposes `(code, commitment)`
> pairs, never votes — org-key auth is a Sprint 2 hardening item.

`POST /api/relay/tickets/issue` — organizer registers the per-poll ed25519
**public** key (the verification anchor). Ticket *signing* stays in the
organizer's browser. Body: `{ pollId, orgPubKey }` (orgPubKey = 32-byte hex).
→ `{ "success": true }`.

`POST /api/relay/tickets/pending` — a voter announces itself. Requires a
**fresh** (unexpired, correctly-signed) ticket and that `issue` ran first.
Body: `{ pollId, ticket, ephemeralIdentityCommitment, confirmationCode }`.
→ `{ "success": true, "status": "pending", "confirmationCode": "0427" }`.
Errors: `400` (not issued / malformed / expired / bad signature),
`409` (ticket already redeemed).

`GET /api/relay/tickets/queue?pollId=…` — organizer dashboard reads the
pending voters. → `{ "pollId", "voters": [{ ticketNonce, ephemeralIdentityCommitment, confirmationCode, status, createdAt }] }`
(only `status: "pending"` rows).

`POST /api/relay/tickets/redeem` — organizer confirms a voter face-to-face;
the ticket is marked consumed (exactly once) and its queue row flips to
`confirmed`. Body: `{ pollId, ticket }`. → `{ "success": true }`.
Errors: `400` (not issued / malformed / bad signature), `409` (replay — already
redeemed). Signature is checked but **expiry is not** — redeem legitimately
happens after the 30s TTL, once the organizer has confirmed.

## Trust model

The relayer is untrusted by design — using it costs the voter nothing in
privacy or vote integrity. The only thing the relayer can do is refuse
service (censor). If that happens, the voter switches back to direct
wallet voting.

| Property              | Direct (wallet)              | Relayer (No Wallet)                | Notes                                                                                                                          |
| --------------------- | ---------------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Anonymity             | ZK proof; tx-sender unlinked | ZK proof; tx-sender = relayer EOA  | The on-chain nullifier is the same in both; the relayer never learns the voter's identity beyond what the network reveals.     |
| No-ETH-needed         | No — voter pays gas          | Yes — relayer pays gas             | Relayer hot-wallet must be funded; see Production checklist.                                                                   |
| Censorship resistance | High — any RPC works         | Medium — relayer can refuse a vote | Mitigation: fall back to direct wallet path. Frontend keeps both tabs visible.                                                 |
| Liveness              | Voter's wallet + RPC         | Voter + relayer + relayer's RPC    | Relayer is an additional single point of failure. The `/api/relay/status` endpoint surfaces relayer-down to the UI.            |

The relayer cannot:

- See who the voter is — the proof reveals only the nullifier + Merkle root.
- Change the vote — `proof.message` is bound to the option index and verified on-chain.
- Double-vote on the voter's behalf — the nullifier is consumed on first submission.
- Redirect an airdrop — `receiver` is bound into the airdrop proof's scope.

The relayer can only forward correctly or refuse to forward.

## Running locally

```bash
cp .env.example .env   # edit if needed
npm install
npm start              # listens on http://localhost:3001
```

Health check:

```bash
curl http://localhost:3001/api/relay/status
```

## Environment variables

| Variable                | Default                          | Description                                   |
| ----------------------- | -------------------------------- | --------------------------------------------- |
| `RPC_URL`               | `http://127.0.0.1:8545`          | Ethereum JSON-RPC endpoint                    |
| `RELAYER_PRIVATE_KEY`   | Hardhat account #0               | Hot wallet that signs and pays gas            |
| `PORT`                  | `3001`                           | HTTP listen port                              |
| `RELAY_RATE_LIMIT_MAX`  | `20`                             | Per-IP request cap per window (global `/api/relay` limiter) |
| `RELAY_RATE_LIMIT_WINDOW_MS` | `60000`                     | Rate-limit window in milliseconds             |
| `RELAY_CREATE_DAILY_MAX` | `5`                             | Per-IP daily cap on sponsored create-poll     |
| `RELAY_REGISTER_PER_POLL_MAX` | `50`                       | Per-(IP, poll) daily cap on sponsored register-voter |

The rate-limit defaults (20 req / 60 s per IP) are production values. Local
e2e / cross-client test bursts exceed them quickly, so `dev-stack.sh` launches
the relayer with `RELAY_RATE_LIMIT_MAX=600` (override by exporting your own
value before `./dev-stack.sh up`).

Likewise the sponsored daily caps (5 creates/day/IP, 50 registers/day/IP/poll)
are production values — a local demo hits 5 creates in minutes and is then
blocked for 24 h, so `dev-stack.sh` launches the relayer with
`RELAY_CREATE_DAILY_MAX=1000` (again, export your own value to override). The
legacy unprefixed names `CREATE_DAILY_MAX` / `REGISTER_PER_POLL_MAX` are still
honored as fallbacks.

The Tessera client (`codes/mobile/`) reads the relayer host from its
`AppConfig` (default `http://localhost:3001`); when the host is unreachable the
client falls back to submitting transactions directly.

## Production checklist

This relayer is a local-dev convenience. Before exposing it on a public
network, address each item:

- **Rate limiting.** The default 20 req/min/IP only stops casual abuse. Front
  with a real reverse proxy (nginx, Cloudflare) and apply per-poll caps —
  one IP should not be able to drain the hot wallet via a single popular
  poll.
- **Balance monitoring.** `/api/relay/status` returns the hot-wallet
  balance. Alert on `balance < N` where `N` covers expected daily vote
  volume × current gas price × safety multiple. Failure mode is silent
  reverts visible only to voters.
- **Key management.** `RELAYER_PRIVATE_KEY` in `.env` is acceptable only
  for local dev. Production deployments should source the key from a
  KMS / HSM / cloud secret manager and never write it to disk on the
  relayer host.
- **Nonce management.** Single-instance ethers v6 manages nonces fine.
  Horizontal scaling needs an external nonce coordinator or sticky
  routing per wallet.
- **Pre-checks.** The relayer pre-checks nullifier consumption and poll
  state before broadcasting (saves gas on duplicate votes). Keep these
  on in production; they are the difference between a refused HTTP
  request and a reverted on-chain tx that still costs gas.
- **Front-running.** The relayer's tx is public in the mempool. For polls
  where vote order leaks information (it does not for M1 — ZK hides
  identity), consider a private mempool (Flashbots) or commit-reveal (M2).
