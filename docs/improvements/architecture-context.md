# Architecture context for contributors

Read this before opening any code in `codes/`. It captures the things that will bite you if you assume defaults.

## What this repo is, in one paragraph

Modular ZK voting platform (**Tessera**). A `PollRegistry` contract acts as a factory: it deploys per-poll **EIP-1167 minimal proxies** (clones) of registered module implementations. **Six modules** ship: `ZkAnonVoting` (Semaphore-based anonymous voting, M1), `ZkBlindVoting` (commit-reveal, M2), `ZkApprovalVoting` (multi-select bitmask), `ZkRankedVoting` (ranked-choice; instant-runoff tallied off-chain), `ZkQuadraticVoting` (credit budget, Σvᵢ²≤100), and `ZkSurveyVoting` (multi-question). A standalone `ZkAirdrop` exists outside the registry. The sole client is the **Flutter app** in `codes/mobile/` (mobile/desktop/web); it dispatches on the on-chain module type in `lib/router.dart`.

## Mental model

```
PollRegistry ─registerModule("anon-vote",      ZkAnonVoting impl)──────┐
             ─registerModule("blind-vote",     ZkBlindVoting impl)     │
             ─registerModule("approval-vote",  ZkApprovalVoting impl)  │
             ─registerModule("ranked-vote",    ZkRankedVoting impl)    │
             ─registerModule("quadratic-vote", ZkQuadraticVoting impl) │
             ─registerModule("survey-vote",    ZkSurveyVoting impl)    │
             ─createPoll(moduleType, …)──clones────────────────────────► <module impl> (initialize'd)

ZkAirdrop      Standalone — NOT in registry. Funded with ETH at deploy time.
Semaphore      Deployed once, linked against PoseidonT3 + a Verifier.
Verifier       MockSemaphoreVerifier (local, always returns true) OR SemaphoreVerifier (real Groth16).
```

## Things that will bite you

### 1. Local deploys use a Mock verifier
`scripts/deploy.ts` wires `Semaphore` against `MockSemaphoreVerifier` which **always returns true**. ZK proofs are **not actually verified** on the Hardhat node. If your test passes and you didn't think about this, your test isn't actually exercising what you think it is. To run real Groth16, deploy with `USE_REAL_VERIFIER=true` (`npm run deploy:real-verifier`) and supply the SNARK artifacts (P4-23 / P4-24).

### 2. Clones use `initialize()`, not constructors
The voting modules are deployed once as bare implementation contracts. `PollRegistry.createPoll` clones them via `Clones.clone()` and calls `initialize(...)`. Implementations have a manual `bool _initialized` guard (P1-5 wants to replace this with OZ `Initializable`). When adding a new module: no constructor, an `initialize` function, and don't forget to also `_disableInitializers()` on the impl in production.

### 3. PoseidonT3 must be linked as a library
The `Semaphore` contract is linked at deploy time. The artifact name is exactly `poseidon-solidity/PoseidonT3.sol:PoseidonT3` (see `scripts/deploy.ts`). Get the name wrong and Hardhat complains cryptically.

### 4. ABIs are generated, not hand-written
The contract ABIs live in `codes/contracts/artifacts/` (produced by `npm run compile`). The Flutter client encodes only the calls it needs; when you change a Solidity ABI, recompile and re-run the cross-impl tests so the client and `deployed-addresses.json` stay in sync. (The old React `frontend/src/abi/` copy is gone with the deleted frontend.)

### 5. `deployed-addresses.json` is overwritten by the deploy script
`codes/contracts/deployed-addresses.json` is the handoff between the contracts and the client. The deploy script writes it. On a fresh Hardhat node the addresses are deterministic — restart the node, redeploy, and you get identical addresses. Don't edit this file by hand.

### 6. Each module is its own state machine
M1 (anon) and M2 (blind) differ fundamentally; the richer modules each add their own ballot encoding on top of the shared `IZkPoll` lifecycle.

| Module | Registration | Voting | Ended |
|---|---|---|---|
| **M1 (anon)** | Owner registers identity commitments | Voter submits ZK proof | Poll closed |
| **M2 (blind)** | Anyone calls `register()` (permissionless) | Voter commits `keccak256(option, salt)` | Reveal window: voter calls `revealVote(option, salt)` |

Don't transplant logic between modules. M1 has a Semaphore group; M2 doesn't. M1 is anonymous; M2 is pseudonymous (address-bound at reveal). Approval/ranked/quadratic/survey are Semaphore-anonymous like M1 but carry a richer `proof.message` (bitmask / ranking / credit vector / answer-commitment) that the contract recomputes and binds on-chain.

### 7. `ZkAirdrop` is standalone (and tested)
Not in the registry, not in `IZkPoll`. It uses Semaphore directly. Its constructor (not `initialize` — it's not a clone) creates a group and stores `groupId`. Permissionless registration. Tested in `test/ZkAirdrop.test.ts`. See `architecture/module-airdrop.md`.

### 8. Ranked & quadratic tallies are off-chain; survey commitment is cross-impl
The instant-runoff (ranked) and credit-allocation (quadratic) **winners are computed off-chain in Dart** (`codes/mobile/lib/core/voting/ranked_irv.dart`, `quadratic_alloc.dart`) — the contract stores ballots, the client tallies. The survey answer commitment (`codes/mobile/lib/core/crypto/survey_commit.dart`) must byte-match the Solidity `keccak256(abi.encode(answers)) >> 8`. These cross-impl matches are load-bearing: change one side and you must change the other and re-run the cross-impl tests.

### 9. Solidity pragma drift
The contracts do not yet pin a single pragma (e.g. caret ranges differ across modules while `hardhat.config.ts` compiles with a fixed version). It compiles today, but P1-10 wants everything pinned to one version.

## Where to find things

| Want | Path |
|---|---|
| Solidity sources | `codes/contracts/contracts/` |
| Solidity tests | `codes/contracts/test/` |
| Deploy script | `codes/contracts/scripts/deploy.ts` |
| Client (Flutter) | `codes/mobile/lib/` (`data/`, `ui/features/`, `core/`; `router.dart` dispatches by module) |
| Client tests | `codes/mobile/test/` + `codes/mobile/integration_test/` |
| Off-chain tallies | `codes/mobile/lib/core/voting/` (`ranked_irv.dart`, `quadratic_alloc.dart`) |
| Relayer | `codes/relayer/src/` |
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

# Relayer (codes/relayer/)
npm install
npm test                              # vitest
npm start                             # http://localhost:3001

# Client (codes/mobile/)
flutter pub get
flutter analyze
flutter test
flutter run -d chrome                 # or -d linux / -d <android-serial>
```

Full local stack: `./dev-stack.sh up` (node → deploy → demo poll → relayer), then `flutter run`. See `docs/architecture/system-overview.md`.

## Things you must NOT do in this repo

1. **Do not commit `CLAUDE.md`** or any agent state files. They stay untracked. Do not add them to `.gitignore` either.
2. **Do not push directly to `main`** — feature branches + PRs.
3. **Do not** add `Co-Authored-By` or any AI attribution to commits.
4. **Do not** run destructive git commands (`reset --hard`, `push --force`, etc.) without explicit authorization.
5. **Do not** auto-generate code that depends on internet artifacts (e.g. SNARK files from `snark-artifacts.pse.dev`) without confirming the artifact source is acceptable.
