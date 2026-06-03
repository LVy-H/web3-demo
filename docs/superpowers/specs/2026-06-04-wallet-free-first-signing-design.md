# Wallet-free-first signing — design

> **Framing (the load-bearing decision):** Tessera's thesis is **wallet-free,
> sponsored, anonymous voting for non-technical users**. Voting needs no wallet
> (it's a ZK proof relayed gaslessly); the relayer already creates / registers /
> starts polls wallet-free. So the "wallet connection is the most painful point"
> is solved not by polishing a wallet modal but by **taking the wallet off the
> critical path**: make wallet-free the default, and demote the wallet to an
> optional, **fenced** "advanced / public-testnet" path. The Reown connect/sign
> flow can only be validated on a real device with a real wallet against a public
> chain (Phase 10) — so this design does **not** claim to "fix" or productionize
> the wallet; it makes the wallet *unnecessary*.

## The three signing paths (today)

| Path | Who pays gas | Where it works | Role |
|---|---|---|---|
| **Sponsored relayer** | the relayer | any chain the relayer can reach (local + public testnet) | **The wallet-free production path.** Relayer owns + runs the poll. |
| **Dev-signer** (`DEV_PRIVATE_KEY`) | the local key | local Hardhat only | Local-dev convenience. *Never ship a build with it set.* |
| **Wallet** (Reown/WalletConnect) | the user | mobile/web, public chain only | **Advanced / optional.** Today: anon-vote create only; **fenced — pending Phase 10**, device-only. |

Voting itself uses none of these for "connecting" — the proof is generated
client-side and relayed gaslessly.

## The gap this closes

The relayer exposes a wallet-free lifecycle — `POST /api/relay/create-poll`
(+ `/register-voter`, `/start-voting`, `/info`) — but **the mobile Create screen
never wired it**: it offers only the dev-signer (local) or the wallet (anon-only,
device-only). So on anything but local-with-a-dev-key, creating a poll *requires*
a wallet. This design wires the sponsored create so **creating any sponsored
module needs no wallet and no dev-signer.**

## Design

### 1. Wallet-free create via the sponsored relayer
- **`RelayClient.getRelayerInfo()`** → `GET /api/relay/info` → `{relayer, registry}`.
  The `relayer` address is baked as the `owner` word inside `initData` so the
  relayer owns (and can register/start) the poll.
- **`RelayClient.createPoll(moduleType, title, description, initDataHex)`** →
  `POST /api/relay/create-poll` → `{pollAddress, txHash}` (or a client-facing
  error: daily cap / low funds / not configured).
- **Encoders made owner-parametric.** `PollCreator`'s per-module `initData`
  encoding (`initialize(semaphore, owner, options)`; survey double-wrapped) is
  extracted to pure top-level `encode*InitData(owner, …)` functions. The
  dev-signer path passes its signer; the sponsored path passes the relayer
  address. One encoder, two callers — no drift (cross-impl tests still pin it,
  plus a new sponsored-encode test).
- **All sponsored modules** (anon / approval / ranked / quadratic / survey;
  **not** blind — excluded by the relayer allow-list) become creatable
  wallet-free. (Today only anon is wallet-creatable, and only with a wallet.)

### 2. Create screen reframe (wallet-free-first)
- The signing banner leads with the **active wallet-free path**:
  - dev-signer set → "Signing locally (dev signer) — no wallet needed" (kept).
  - else, relayer reachable → "**Sponsored — Tessera covers the gas. No wallet
    needed.**" (the new default).
  - else → honest guidance (below), not a dead-end.
- The **module picker** no longer gates approval/ranked/quadratic/survey behind
  the dev-signer — they're enabled whenever a wallet-free path (dev-signer **or**
  sponsored relayer) is available.
- The **wallet** is demoted to a collapsed "Advanced — connect a wallet
  (public-testnet, pending Phase 10)" affordance, never the primary CTA.

### 3. Honest states (no dead-ends)
- Drawer pill `WALLET NOT CONFIGURED` → the wallet is **optional**; show a quiet
  "Wallet · optional" (or omit) rather than an alarming red dead-end.
- Desktop (Reown unsupported) → don't silently hide; "Wallet isn't available on
  desktop — Tessera signs locally (dev) or via the sponsored relayer."
- No-signer-at-all → "No signer available. Start the relayer (`dev-stack.sh up`)
  for sponsored creation, or set `DEV_PRIVATE_KEY` for local dev."

### 4. Settings — one place for the model
Expand the existing **SIGNING & PROVING** section with a short "How signing
works" explainer of the three paths + when a wallet is even relevant (only
public-testnet, pending Phase 10).

## Verified-or-fenced
- **Verified (this increment):** `RelayClient.createPoll`/`getRelayerInfo` unit
  tests (exact path/body/parse, like the other relay methods); the owner-
  parametric encoders (sponsored-encode test); `flutter analyze`/`flutter test`;
  and an **on-device** wallet-free create against the running local relayer
  (no wallet, no dev-signer) — the headline verification.
- **Fenced:** the Reown wallet pairing/sign stays device-only / public-testnet,
  pending Phase 10. This design does not claim it's production-ready.

## Out of scope / follow-up
- Sponsored **register-voter / start-voting** wired into poll-detail owner actions
  (the create step is here; the rest of the sponsored lifecycle is the next
  increment — the live-meeting flow already covers register via tickets).
- A custom Reown connect/connected/disconnect UI (deliberately **not** built — it
  can't be verified until Phase 10).
