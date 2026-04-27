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
