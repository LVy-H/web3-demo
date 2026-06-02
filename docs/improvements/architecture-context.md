# Architecture context for contributors

Read this before opening any code in `codes/`. It captures the things that will bite you if you assume defaults.

## What this repo is, in one paragraph

Modular ZK voting platform. A `PollRegistry` contract acts as a factory: it deploys per-poll **EIP-1167 minimal proxies** (clones) of registered module implementations. Two modules ship: `ZkAnonVoting` (Semaphore-based anonymous voting, M1) and `ZkBlindVoting` (commit-reveal, M2). A standalone `ZkAirdrop` exists outside the registry. Frontend is React 19 + Wagmi + Viem; pages dispatch by module type via `PollRouter`.

## Mental model

```
PollRegistry ─registerModule("anon-vote",  ZkAnonVoting impl)──┐
             ─registerModule("blind-vote", ZkBlindVoting impl)─┤
             ─createPoll(moduleType, …)──clones──────────────► ZkAnonVoting / ZkBlindVoting (initialize'd)

ZkAirdrop      Standalone — NOT in registry. Funded with ETH at deploy time.
Semaphore      Deployed once, linked against PoseidonT3 + a Verifier.
Verifier       MockSemaphoreVerifier (local, always returns true) OR SemaphoreVerifier (real Groth16).
```

## Things that will bite you

### 1. Local deploys use a Mock verifier
`scripts/deploy.ts` wires `Semaphore` against `MockSemaphoreVerifier` which **always returns true**. ZK proofs are **not actually verified** on the Hardhat node. If your test passes and you didn't think about this, your test isn't actually exercising what you think it is. To run real Groth16, you must swap to `SemaphoreVerifier` in the deploy script — there's no environment switch yet.

### 2. Clones use `initialize()`, not constructors
The voting modules are deployed once as bare implementation contracts. `PollRegistry.createPoll` clones them via `Clones.clone()` and calls `initialize(...)`. Implementations have a manual `bool _initialized` guard (P1-5 wants to replace this with OZ `Initializable`). When adding a new module: no constructor, an `initialize` function, and don't forget to also `_disableInitializers()` on the impl in production.

### 3. PoseidonT3 must be linked as a library
The `Semaphore` contract is linked at deploy time. The artifact name is exactly `poseidon-solidity/PoseidonT3.sol:PoseidonT3` (see `scripts/deploy.ts:25-29`). Get the name wrong and Hardhat complains cryptically.

### 4. ABIs are committed under `frontend/src/abi/`
They're generated from `contracts/artifacts/` — but the copy is **manual** today (a `npm run copy-abis` script is referenced in `package.json` but the underlying script may be missing). When you change a Solidity ABI, you must regenerate and re-copy or the frontend breaks at runtime.

### 5. `deployed-addresses.json` is overwritten by the deploy script
`codes/contracts/deployed-addresses.json` is the handoff between contracts and frontend. The deploy script writes it. On a fresh Hardhat node, the addresses are deterministic — restart the node, redeploy, and you get identical addresses. Don't edit this file by hand.

### 6. Two voting modules, two state machines
| Module | Registration | Voting | Ended |
|---|---|---|---|
| **M1 (anon)** | Owner registers identity commitments | Voter submits ZK proof | Poll closed |
| **M2 (blind)** | Anyone calls `register()` (permissionless) | Voter commits `keccak256(option, salt)` | Reveal window: voter calls `revealVote(option, salt)` |

Don't transplant logic between them. M1 has a Semaphore group; M2 doesn't. M1 is anonymous; M2 is pseudonymous (address-bound at reveal).

### 7. `ZkAirdrop` is an orphan
Not in the registry, not in `IZkPoll`, no tests. It uses Semaphore directly. Its constructor (not `initialize` — it's not a clone) creates a group and stores `groupId`. Permissionless registration. See `architecture/module-airdrop.md`.

### 8. Module-level state in `Poll.tsx` is a bug
`codes/frontend/src/pages/Poll.tsx:137-138` declares:
```ts
let group: Group | null = null;
let isGroupSynced = false;
```
**outside the component.** This persists across navigation and breaks under HMR / multiple instances. Tracked as P0-2 — fix with a hook + `useRef`.

### 9. `localStorage['my-nullifier']` is global
`codes/frontend/src/pages/Poll.tsx:185-186, 377` writes/reads `'my-nullifier'` with no per-poll scoping. Voting on poll A makes poll B think you've voted there too. P0-1.

### 10. Solidity pragma drift
- `PollRegistry`, `ZkAnonVoting`, `ZkBlindVoting`: `pragma solidity ^0.8.20;`
- `ZkAirdrop`: `pragma solidity ^0.8.23;`
- `hardhat.config.ts`: compiles with `0.8.34`

Compiles fine today, but pin everything to one version (P1-10).

## Where to find things

| Want | Path |
|---|---|
| Solidity sources | `codes/contracts/contracts/` |
| Solidity tests | `codes/contracts/test/` |
| Deploy script | `codes/contracts/scripts/deploy.ts` |
| Frontend pages | `codes/frontend/src/pages/` (`Home`, `CreatePoll`, `Poll`, `BlindPoll`, `PollRouter`) |
| Frontend hooks | `codes/frontend/src/hooks/` (`useRegistry`, `usePoll`, `useBlindPoll`) |
| Frontend ABIs | `codes/frontend/src/abi/` |
| E2E tests | `codes/frontend/tests/e2e.spec.ts` |
| Architecture docs | `docs/architecture/` |
| Project status | `docs/project/STATUS.md` |
| Roadmap | `docs/project/ROADMAP.md` |

## Commands

Run from inside the relevant package:

```bash
# Contracts (codes/contracts/)
npm install
npm run compile
npm test                              # all tests
npx hardhat test test/<file>.test.ts  # single file
npm run node                          # local JSON-RPC at 127.0.0.1:8545
npm run deploy:local                  # deploy + write deployed-addresses.json

# Frontend (codes/frontend/)
npm install
npm run dev                           # http://localhost:5173
npm run lint
npm run build
npx playwright test                   # E2E (needs node + deploy + dev server running)
```

Full local stack: 4 terminals — node, deploy, dev server, playwright. See `docs/architecture/system-overview.md`.

## Things you must NOT do in this repo

1. **Do not commit `CLAUDE.md`** or any agent state files. They stay untracked. Do not add them to `.gitignore` either.
2. **Do not push directly to `main`** — feature branches + PRs.
3. **Do not** add `Co-Authored-By` or any AI attribution to commits.
4. **Do not** run destructive git commands (`reset --hard`, `push --force`, etc.) without explicit authorization.
5. **Do not** auto-generate code that depends on internet artifacts (e.g. SNARK files from `snark-artifacts.pse.dev`) without confirming the artifact source is acceptable.
