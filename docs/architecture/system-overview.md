# System Architecture Overview

## Contract Architecture

The system uses a modular contract architecture with a central registry.

### PollRegistry (Factory)
- **Address:** Deployed once per network. All integrations start here.
- **Role:** Creates poll instances as EIP-1167 minimal proxies. Maintains a list of all polls.
- **Module types currently registered:**
  - `"anon-vote"` (M1) — see [`module-m1-anon-voting.md`](./module-m1-anon-voting.md)
  - `"blind-vote"` (M2) — see [`module-m2-blind-voting.md`](./module-m2-blind-voting.md)
- **Key functions:**
  - `registerModule(moduleType, implementation)` -- owner registers a new module
  - `createPoll(moduleType, title, description, initData)` -- anyone creates a poll
  - `getAllPolls()` -- returns all polls with metadata

### IZkPoll (Interface)
- **Role:** Shared interface that all voting modules implement.
- **Key functions:**
  - `getState()` -- poll lifecycle state (Registration/Voting/Ended)
  - `getResults()` -- vote tally per option
  - `getOptions()` -- poll option labels
  - `getParticipantCount()` -- number of registered participants
  - `verifyParticipation(nullifierHash)` -- M3 receipt verification
  - `owner()` -- poll creator address

### Minimal Proxy Pattern (EIP-1167)
Each poll is a thin clone (~45 bytes of bytecode) that delegates all calls to a deployed implementation contract. This saves gas: creating a poll costs ~45k gas instead of ~2M+ gas for a full contract deployment.

The implementation contract is deployed once per module type. Clones are created by `PollRegistry.createPoll()` and initialized via `initialize()`.

## Frontend Architecture

### Hooks
- `useRegistry` -- reads polls from PollRegistry, creates polls
- `usePoll` -- reads poll state/results/options via IZkPoll interface (works for any module)
- `useBlindPoll` -- M2-specific reads: reveal deadline, hasVoted/hasRevealed, finalization

### Pages
- `/` (Home) -- browse active polls (read from `PollRegistry.getAllPolls`)
- `/create` -- create a new poll, choosing module type at submit time
- `/poll/:address` -- routed via `PollRouter`, which reads the module type from the registry and renders either:
  - `Poll.tsx` for `anon-vote` (M1)
  - `BlindPoll.tsx` for `blind-vote` (M2)

### Identity Management (M1 only)
- Semaphore identity stored in localStorage per poll address (`semaphore-identity-${pollAddress}`)
- Admin generates invite tokens (random secrets) and registers commitments on-chain
- Voters paste invite token to derive their identity

### Vote Storage (M2 only)
- Commit-reveal salt + option index stored in localStorage per poll (`blind-vote-${pollAddress}`)
- Voter must reveal from the same browser they committed in (or back the data up themselves)

## Relayer (off-chain, optional)

An off-chain Express service in [`codes/relayer/`](../../codes/relayer/) forwards M1 anonymous votes and ZK airdrop claims on behalf of voters who have no funded wallet. It is an optional component: when the frontend's `VITE_RELAYER_URL` is unset, the relayer tab is hidden and the system runs as direct-wallet only. The ZK proof is always generated client-side; the relayer never sees plaintext identity material.

### Position in architecture

```
Browser (frontend)              Relayer service              Node (Hardhat / Sepolia)
─────────────────────────       ─────────────────            ─────────────────────────
useRelay hook                   POST /api/relay/vote
  ├─ generates ZK proof  ─────► validation.ts (shape)
  └─ POST proof payload         relay.ts
                                  ├─ getState() ────────────► Poll clone (read)
                                  ├─ isNullifierUsed() ─────► Poll clone (read)
                                  └─ castVote(proof) ───────► Poll clone (write)
                                wallet.ts
                                  └─ signs with RELAYER_PRIVATE_KEY
```

The relayer is a thin pass-through: it owns the hot wallet that pays gas and a small pre-check layer in front of each broadcast, nothing else. It runs in its own container next to `contracts` and `frontend` (see [`docker-compose.yml`](../../docker-compose.yml)).

### Gasless flow

The voter generates a Semaphore proof in the browser, then POSTs `{pollAddress, vote, proof}` to the relayer instead of submitting on-chain. The relayer's pre-check layer (see [`codes/relayer/src/relay.ts`](../../codes/relayer/src/relay.ts)) calls `getState()`, `getOptionCount()`, and `isNullifierUsed()` on the target poll before broadcasting — duplicate-vote attempts and wrong-phase calls are rejected as HTTP errors rather than as reverted on-chain transactions that still cost gas. Each pre-check failure maps to a stable error string the frontend can display (`Poll is not in voting phase`, `Invalid vote index`, `This vote token has already been used (nullifier consumed)`). The nullifier pre-check is a gas optimization, not an anonymity boundary; the on-chain contract performs the same check authoritatively and would reject a duplicate even without it.

On a successful pre-check the relayer signs `castVote(vote, proof)` with `RELAYER_PRIVATE_KEY`, waits for the receipt, and returns the tx hash. The proof carries the same nullifier and Merkle root the direct-wallet path would emit; on-chain state is identical regardless of which path was used.

### Trust model summary

| Property              | Direct mode                     | Relayer mode                       |
| --------------------- | ------------------------------- | ---------------------------------- |
| Anonymity             | Yes (ZK proof; sender unlinked) | Yes (ZK proof; sender = relayer EOA) |
| No-ETH-needed         | No (voter pays gas)             | Yes (relayer pays gas)             |
| Censorship resistance | High (any RPC works)            | Partial (relayer can refuse; fall back to direct) |
| Liveness              | Voter wallet + RPC              | Partial (voter + relayer + relayer RPC) |

The relayer cannot deanonymize the voter, alter the vote (`proof.message` is bound to the option index and verified on-chain), double-vote (the nullifier is consumed on first submission), or redirect an airdrop (the `receiver` is bound into the proof's scope). It can only forward correctly or refuse.

### When to enable vs disable

- **Local dev** — relayer-on by default. UX guarantee: a contributor with a fresh checkout can vote without funding a wallet. The frontend exposes the relayer tab whenever `/api/relay/status` is reachable.
- **Staging / Sepolia** — relayer-on with monitored hot-wallet balance. `/api/relay/status` returns the balance; alert on `balance < daily_volume × gas_price × safety_multiple`. Otherwise failure mode is silent reverts visible only to voters.
- **Production / mainnet** — depends on the threat model. The relayer adds a censorship vector (it can refuse service) and a liveness dependency, in exchange for onboarding voters who hold no ETH. If gasless onboarding is not a requirement, omit the service and ship direct-mode only; the contracts have no relayer dependency.

### Architectural integration points

- **Hot wallet key.** [`codes/relayer/src/wallet.ts`](../../codes/relayer/src/wallet.ts) lazy-constructs a single `ethers.Wallet` from `RELAYER_PRIVATE_KEY` on first use and caches both the wallet and its `JsonRpcProvider` in module scope. The key is consumed only at process start; nothing else in the codebase reads it. A malformed key throws synchronously at first request, which surfaces in the boot-time `getRelayerInfo()` log line — startup failures are loud, not silent. For local dev the value defaults to Hardhat account #0 via [`docker-compose.yml`](../../docker-compose.yml); any non-dev deploy must override it (KMS / secret manager — never the on-disk `.env`).
- **Container wiring.** [`docker-compose.yml`](../../docker-compose.yml) defines the `relayer` service alongside `contracts` and `frontend`. It is built from [`codes/relayer/`](../../codes/relayer/), binds port 3001 to loopback only (`127.0.0.1:3001`), and points `RPC_URL` at `http://contracts:8545` over the compose-internal DNS. `depends_on: [contracts]` ensures the node is up before the relayer starts but does not gate readiness — the relayer logs its hot-wallet balance on boot, and the frontend's `useRelayStatus` poll is what actually decides whether the relayer tab appears. The frontend may point at an external RPC via `VITE_RPC_URL`; the relayer's `RPC_URL` is independent and routes traffic across the internal docker network.
- **Frontend client.** The browser-side client lives at [`codes/frontend/src/hooks/useRelay.ts`](../../codes/frontend/src/hooks/useRelay.ts). It reads `VITE_RELAYER_URL` from config and exposes two hooks: `useRelayVote()` for the vote path and `useRelayStatus()` as a one-shot health check used to gate tab visibility. The hook defines a `RelayProof` interface that accepts both `bigint` and `NumericString` (snarkjs emits stringified field elements, but in-memory call sites hold bigints) and normalizes to decimal strings before posting — that conversion happens client-side so the relayer can stay schema-strict.
- **Request validation.** [`codes/relayer/src/validation.ts`](../../codes/relayer/src/validation.ts) shape-checks every request body before any RPC call: address syntax via `ethers.isAddress`, option-index range, proof field presence, and an 8-element `points` array. This is shape validation only — proof correctness is the on-chain `SemaphoreVerifier`'s job, not the relayer's. The error tiers are distinct: HTTP 400 for malformed input (validation), 503 for insufficient hot-wallet balance, and 500 for unexpected reverts or RPC failures, which lets the frontend distinguish "fix your request" from "service is down".

## Deployment Stack

```
PoseidonT3 (library)
    └── Semaphore (ZK verification, linked to PoseidonT3 + a Verifier)
        ├── PollRegistry (factory)
        │   ├── ZkAnonVoting   (M1 impl — uses Semaphore for ZK proofs; clone source)
        │   └── ZkBlindVoting  (M2 impl — no Semaphore dependency; clone source)
        └── ZkAirdrop          (standalone — uses Semaphore directly, NOT in registry)

Verifier slot:
    - Local dev:    MockSemaphoreVerifier  (always returns true — no SNARK artifacts needed)
    - Production:   SemaphoreVerifier      (real Groth16; requires SNARK artifact CDN at runtime)

    Toggle via env var: USE_REAL_VERIFIER=true npm run deploy:local
    (default = mock; deploy script prints a loud banner when the mock is wired)
```

## Upgrades & Immutability

This system has **no upgrade pattern**. None of the contracts sit behind a UUPS / Transparent / Beacon proxy. The choices below are deliberate; do not try to retrofit an upgrade slot onto modules without redesigning the registry.

### Per-poll clones are immutable

Every poll created via `PollRegistry.createPoll()` is an EIP-1167 minimal proxy (~45 bytes) whose bytecode hard-codes the implementation address it delegates to. There is no admin slot, no `upgradeTo`, no beacon lookup. A poll's behavior is fixed at creation time to whatever implementation was registered for its module type at that moment.

### `registerModule` swaps don't migrate existing polls

The registry owner can call `registerModule("anon-vote", newImpl)` to point future clones at a new implementation. **Existing clones are unaffected.** Each clone's delegate target is baked into its own bytecode at deploy time — the registry's mapping is only consulted by `createPoll()`. A swap therefore only changes which implementation new polls are cloned from; every poll that already exists keeps running against the implementation it was originally cloned from, forever.

### "Upgrading" a module = ship a new module, create new polls

If a bug is found in `ZkAnonVoting`:

1. Deploy a fixed implementation.
2. Call `registerModule("anon-vote", fixedImpl)` (or register under a new module type, e.g. `"anon-vote-v2"`).
3. Direct users to create new polls. Old polls keep their old (buggy) behavior until they end naturally.

There is no in-place migration path for state already held in a clone. Treat each poll as a single-use, immutable instance.

### `ZkAirdrop` is standalone, not a clone

`ZkAirdrop` is deployed once with a real constructor and is **not** managed by `PollRegistry`. It has no clone factory, no upgrade hook, and a fixed address. To "upgrade" the airdrop, deploy a fresh `ZkAirdrop` contract and point users (and the frontend's `deployed-addresses.json`) at the new address. The old contract remains live at its original address and cannot be patched.

### The Registry itself is permanent

`PollRegistry` is also deployed without a proxy. Its address is permanent for the lifetime of the deployment. The only mutable registry state is:

- `registerModule(moduleType, impl)` — owner adds or replaces module entries (affects future `createPoll` calls only).
- `transferOwnership(newOwner)` — standard `Ownable` (or `Ownable2Step`'s 2-step variant once P1-6 lands) ownership handoff.

If the registry itself needs to change shape, the migration is: deploy a new `PollRegistry`, re-register modules on it, and switch the frontend over. Polls created against the old registry keep working — they don't depend on it after construction — but they will no longer appear in `getAllPolls()` of the new registry.

## Container Architecture

```
podman-compose
├── contracts (Hardhat node + auto-deploy)
│   ├── Port 8545 (JSON-RPC)
│   └── Runs: hardhat node → deploy.ts
└── frontend (Vite dev server)
    ├── Port 5173 (HTTP)
    └── Reads: deployed-addresses.json (baked at build time)
```
