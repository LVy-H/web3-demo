# System Architecture Overview

## Contract Architecture

The system uses a modular contract architecture with a central registry.

### PollRegistry (Factory)
- **Address:** Deployed once per network. All integrations start here.
- **Role:** Creates poll instances as EIP-1167 minimal proxies. Maintains a list of all polls.
- **Module types:** `"anon-vote"` (M1), `"blind-live"` (M2a, future), `"blind-sealed"` (M2b, future)
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
- `usePoll` -- reads poll state/results/options via IZkPoll interface

### Pages
- `/` (Home) -- create polls, browse active polls
- `/poll/:address` -- vote on a poll, view results, admin controls

### Identity Management
- Semaphore identity stored in localStorage per poll address
- Admin generates invite tokens (random secrets) and registers commitments on-chain
- Voters paste invite token to derive their identity

## Deployment Stack

```
PoseidonT3 (library)
    └── Semaphore (ZK verification)
        ├── PollRegistry (factory)
        │   └── ZkAnonVoting (M1 implementation, clone source)
        └── ZkAirdrop (standalone, unchanged)
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
