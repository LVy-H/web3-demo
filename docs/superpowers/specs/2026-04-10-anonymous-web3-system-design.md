# Anonymous Web3 System -- Design Specification

**Date:** 2026-04-10
**Status:** Draft
**Scope:** Modular anonymous voting platform with privacy infrastructure for third-party integration

---

## 1. Context & Goals

### Background
This is a web development course project. The system serves as **privacy infrastructure** that other student projects can integrate with (via UI-as-service or JS SDK) to prove they don't cheat on data.

### Primary Scenario
The professor's "most basic scenario": vote on whether he is the most handsome in class. Requirements:
- **Participation is visible** -- he can see who voted and who didn't
- **Vote content is hidden** -- nobody can see who voted "No"
- Results may be live or sealed depending on configuration

### Three Modules to Build (Incrementally)
1. **M1: Anonymous Token Voting** -- existing PoC, needs stabilization and refactoring
2. **M2: Identity-Visible, Content-Hidden Voting** -- two sub-modes (live tally vs sealed-until-trigger)
3. **M3: Participation Receipts** -- prove you voted without revealing your vote

### Non-Goals (for now)
- Weighted voting, liquid democracy, updatable votes (future phases beyond scope)
- Production mainnet deployment
- Relayer/gasless network (future)
- Full FHE-based tallying (simplified crypto approach instead)

---

## 2. Privacy Dimensions Framework

Instead of a linear tier system (Tier 1-4), privacy is modeled as **3 independent axes**. Each voting module picks a position on each axis. No module is "better" -- they solve different problems.

### Axes

| Dimension | Question | Positions |
|-----------|----------|-----------|
| **Identity** | Who voted? | `anonymous` -- ZK proof, no address link · `pseudonymous` -- address visible, person unknown · `identified` -- address visible, person known |
| **Content** | What did they vote? | `public-realtime` -- live tally, traceable to individual · `public-aggregate` -- live tally, not traceable to individual · `sealed` -- hidden until reveal trigger · `forever-blind` -- never revealed per-voter |
| **Temporality** | When is information revealed? | `immediate` · `threshold` -- N votes or N% participation · `time-locked` -- after deadline · `never` |

### Module Mapping

| Module | Identity | Content | Temporality |
|--------|----------|---------|-------------|
| M1: Anonymous Token Voting | anonymous | public-aggregate | immediate |
| M2a: Blind Voting (live tally) | identified | public-aggregate | immediate |
| M2b: Blind Voting (sealed) | identified | sealed | threshold or time-locked |
| M3: Participation Receipt | (cross-cutting) | -- | on-demand |

### Impossible Combinations
- `anonymous` identity + `public-realtime` content in small groups: if 5 voters and 4 voted "Yes," the 5th is deanonymized
- `sealed` content + `immediate` temporality: contradictory by definition
- `anonymous` identity + participation receipt to a specific person: the receipt itself is a ZK proof ("I'm in the voter set") not a direct identity claim

---

## 3. System Architecture

### Approach: Modular Contracts with Shared Registry

Separate contracts per voting mode, united by a Registry/Factory contract. Each module is independent but shares a common interface.

```
┌─────────────────────────────────────────────────┐
│                  PollRegistry                    │
│  - createPoll(moduleType, params) → pollId       │
│  - getPoll(pollId) → address                     │
│  - listPolls() → Poll[]                          │
│  - Module whitelist (owner-managed)              │
├─────────────────────────────────────────────────┤
│              IZkPoll (shared interface)           │
│  - getState() → PollState                        │
│  - getResults() → uint256[]                      │
│  - hasParticipated(address) → bool               │
│  - getParticipantCount() → uint256               │
│  - verifyParticipation(proof) → bool             │
├──────────┬──────────────────┬────────────────────┤
│ ZkAnon   │ ZkBlindLive      │ ZkBlindSealed      │
│ Voting   │ Voting           │ Voting             │
│ (M1)     │ (M2a)            │ (M2b)              │
└──────────┴──────────────────┴────────────────────┘
```

**Key decisions:**
- **PollRegistry** is the single entry point for integrators. One address to call.
- **IZkPoll** is the common interface. Frontend/SDK codes against this, agnostic to module type.
- **Minimal proxy (EIP-1167)** for poll creation. Each poll is a thin clone (~45k gas) pointing to a module implementation deployed once.
- **M3 (receipts)** is a method on IZkPoll, not a separate contract.

---

## 4. Module Specifications

### 4.1 M1: Anonymous Token Voting

**Refactor of existing ZkVoting.sol PoC.**

- **Crypto:** Semaphore v4 ZK membership proof + nullifier
- **Identity:** Anonymous. Voter registers a commitment (no address link). Votes via ZK proof.
- **Content:** Public aggregate. Contract increments `voteCounts[option]` on each valid vote. Individual votes not traceable.
- **Double-vote prevention:** Nullifier hash tracked per poll.
- **Flow:**
  1. Poll creator deploys via Registry with options list
  2. Voters register identity commitments (Registration phase)
  3. Owner starts voting phase
  4. Voters generate ZK proof client-side, submit `castVote(proof, optionIndex)`
  5. Contract verifies proof, checks nullifier, increments tally
  6. Owner ends poll
- **Changes from current PoC:**
  - Implement `IZkPoll` interface
  - Deploy via `PollRegistry` factory (not standalone)
  - Add `verifyParticipation()` for M3
  - Improve event emissions for SDK consumption
  - Harden edge cases in tests

### 4.2 M2a: Blind Voting -- Live Tally

**New contract. Identity visible, vote content hidden, aggregate tally visible in real-time.**

- **Crypto:** ElGamal encryption on elliptic curve (additive homomorphism) + ZK proof of valid vote
- **Identity:** Voter address recorded on-chain when casting vote. Everyone knows who participated.
- **Content:** Individual votes encrypted. Contract adds encrypted votes homomorphically. Only the aggregate is decryptable.
- **Flow:**
  1. Poll creator deploys via Registry. A poll-specific encryption keypair is generated (creator holds private key).
  2. Voters register (address recorded)
  3. Owner starts voting
  4. Voter encrypts their choice with the poll's public key, submits `castVote(encryptedVote, zkProofOfValidity)`
  5. ZK proof verifies: "my encrypted blob encodes a valid option (one of 0..N-1)"
  6. Contract homomorphically adds the encrypted vote to the running encrypted tally
  7. Poll ends. Creator submits decryption key. Contract decrypts aggregate tally.
- **Simplification for course scope:** If full ElGamal + ZK is too complex for the timeline, fallback to: votes stored encrypted (not homomorphic), tally computed at reveal time by the poll creator off-chain, with the decrypted result posted on-chain. Less trustless but drastically simpler.

### 4.3 M2b: Blind Voting -- Sealed

**New contract. Identity visible, all votes hidden until trigger.**

- **Crypto:** Commit-reveal scheme with keccak256
- **Identity:** Voter address recorded on-chain.
- **Content:** Votes hidden until reveal phase triggered by threshold or time-lock.
- **Flow:**
  1. Poll creator deploys via Registry with `revealThreshold` (participant count) and/or `revealDeadline` (timestamp)
  2. Voters register
  3. Owner starts voting
  4. Voter submits `commitVote(keccak256(optionIndex, salt))` -- hash stored on-chain
  5. Trigger fires: `participantCount >= threshold` OR `block.timestamp >= deadline`
  6. Reveal phase: voters submit `revealVote(optionIndex, salt)` -- contract verifies hash match
  7. Tally computed from revealed votes
- **Edge case -- voter doesn't reveal:** Vote excluded from tally after a grace period. This is a known limitation of commit-reveal. Documented, not hidden.
- **Future upgrade path:** Replace commit-reveal with threshold encryption (N-of-M key holders must cooperate to decrypt). Out of scope for initial implementation.

### 4.4 M3: Participation Receipts

**Cross-cutting feature on all modules.**

- **Interface:** `verifyParticipation(bytes proof, bytes32 pollId) → bool` on IZkPoll
- **For M1 (anonymous):** Receipt = ZK proof of "I am a member of the voter group AND my nullifier was used in this poll." Verifier calls contract, contract confirms nullifier exists. Voter identity stays hidden.
- **For M2 (identity-visible):** Receipt = signed message from voter's address + on-chain event log of their `commitVote` / `castVote` transaction. Verifier checks event log.
- **Off-chain receipt format:**
  ```json
  {
    "pollId": "0x...",
    "moduleType": "M1|M2a|M2b",
    "voterProof": "...",
    "nullifierHash": "0x...",
    "timestamp": 1234567890,
    "registryAddress": "0x...",
    "chainId": 31337
  }
  ```
- **Verification page:** Standalone page in frontend -- paste/upload receipt JSON, page calls `verifyParticipation()` on-chain and shows result.

---

## 5. Integration Design

### For other student projects (Phase 5+)

**Option A: UI-as-service**
- Other project links to our frontend URL with query params: `/create?title=...&mode=blind-sealed&options=...`
- User votes on our UI, gets redirected back with receipt
- Simplest integration, no code changes needed in their project

**Option B: JS SDK**
- `npm install @zk-poll/sdk`
- SDK wraps ethers.js contract calls: `createPoll()`, `castVote()`, `getResults()`, `verifyReceipt()`
- Other project builds their own UI but uses our contracts

**Both options go through PollRegistry** as the single on-chain entry point.

---

## 6. Phased Roadmap

Each phase has a **stability gate** that must pass before the next begins.

### Phase 0: Foundation & Documentation
- Restructure repo from `codes/` to proper monorepo layout
- Write `docs/framework/` (privacy dimensions, module comparison)
- Write `docs/architecture/` (system overview, module specs)
- Define and compile `IZkPoll` interface and `PollRegistry` contract skeleton
- Set up code quality tooling (linting, test framework, CI)
- **Gate:** Docs complete, interface compiles, test harness runs green

### Phase 1: Stabilize M1 (Anonymous Token Voting)
- Refactor `ZkVoting.sol` → implement `IZkPoll`
- Integrate with `PollRegistry` factory + minimal proxy
- Harden test suite (edge cases, reentrancy guards, gas snapshots)
- Refactor frontend to use Registry + IZkPoll abstraction
- **Gate:** 90%+ test coverage, clean Slither report, frontend E2E passes

### Phase 2: Build M2a (Blind Voting -- Live Tally)
- Implement `ZkBlindLiveVoting.sol`
- Register as new module type in PollRegistry
- Frontend: poll creation flow with mode selection
- May use simplified (non-homomorphic) crypto initially
- **Gate:** Full test suite, professor's "handsome vote" scenario works E2E

### Phase 3: Build M2b (Blind Voting -- Sealed)
- Implement `ZkBlindSealedVoting.sol` with commit-reveal
- Threshold trigger + time-lock trigger
- Handle voter-no-reveal timeout
- Frontend: sealed mode UI with reveal phase indicator
- **Gate:** Both triggers work, timeout handling tested, E2E passes

### Phase 4: Participation Receipts (M3)
- Add `verifyParticipation()` to IZkPoll, implement in all modules
- Frontend: receipt generation (exportable JSON) after voting
- Frontend: standalone receipt verifier page
- **Gate:** Receipt round-trip works for M1 and M2 variants

### Phase 5: Integration Layer
- Build JS SDK (`@zk-poll/sdk`)
- Write integration guide
- Build example integration (minimal "other project" that creates a poll)
- **Gate:** Fresh project can `npm install` SDK and complete full flow

### Phase 6: Testnet Deployment
- Deploy Registry + all modules to Sepolia or Amoy
- Frontend network switching (local ↔ testnet)
- Gas optimization pass
- **Gate:** Full flow works on public testnet

---

## 7. Code Quality Standards

### Smart Contracts
- Solidity ^0.8.20, Hardhat toolchain
- 90%+ line coverage via `hardhat-coverage`
- NatSpec documentation on all public/external functions
- Slither static analysis: zero high/medium findings
- Gas snapshots tracked per PR (regression detection)

### Frontend
- TypeScript strict mode, React 19, Vite
- Component tests for critical user flows
- Playwright E2E tests for each module's happy path
- No `any` types in new code

### Git Conventions
- Conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`
- One PR per logical change
- Squash-merge to main
- No merge without passing CI (when CI is set up)

### Security
- Threat model document per module (in `docs/architecture/`)
- Known limitations explicitly documented
- `MockSemaphoreVerifier` used in tests only -- never in deploy scripts targeting testnet/mainnet
- No hardcoded private keys in committed code

---

## 8. Technology Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Smart Contracts | Solidity ^0.8.20 + Hardhat | Existing PoC uses this, mature tooling |
| ZK Proofs | Semaphore v4 | Already integrated, well-documented |
| Encryption (M2a) | ElGamal / simplified fallback | Additive homomorphism for tallying |
| Commit-Reveal (M2b) | keccak256 | Simple, battle-tested, no external deps |
| Frontend | React 19 + Vite + Wagmi v3 | Existing stack, modern |
| Testing | Hardhat + Chai + Playwright | Existing setup, contract + E2E |
| Static Analysis | Slither | Industry standard for Solidity |
| Deployment | Hardhat scripts → Sepolia/Amoy | Hardhat ignition or scripts |

---

## 9. Open Questions & Future Work

- **M2a crypto complexity:** Full homomorphic ElGamal may be too complex for course timeline. Decision point: evaluate during Phase 2 whether to use simplified approach.
- **Relayer network for gasless:** Deferred. Would upgrade M1 from "pseudonymous" to truly "permissionless anonymous." Tracked as future phase.
- **Weighted voting, delegation:** Described in whitepaper but out of scope. Can be added as new modules implementing IZkPoll.
- **Cross-chain receipts:** Receipts currently tied to one chain. Future work could make them chain-agnostic.
