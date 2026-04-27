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
```

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
