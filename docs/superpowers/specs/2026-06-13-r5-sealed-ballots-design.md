# R5 / Phase 14 — Sealed ballots: one ballot box, real cryptographic sealing

> **Status:** draft for owner review · 2026-06-13
> **Builds on:** `2026-06-11-tessera-revolution-design.md` §5 (privacy model v1) + §7 (R5).
> **Owner prompts (2026-06-13):** "reduce the contracts while keeping voting diversity — unify into one contract, reduce gas"; "native encryption / native hash on chain? like some ZK?"

## 1. Problem

After R4, privacy defaults are **policy, not physics**: `resultsPolicy=sealedUntilClose`
is metadata that compliant clients honor, while ballots remain plaintext in calldata
and events, and per-option tallies are public storage anyone can read mid-vote.
Separately, we maintain **six near-identical module contracts** whose only real
differences are (a) how one `uint256` message is interpreted and (b) on-chain tally
shape — six audit surfaces, six ABI sets, six initialize encodings (the R4 migration
touched all of them).

## 2. Two facts that shape the design

1. **Vote gas is dominated by the Groth16 pairing check** (~200–300k via the EVM
   pairing precompile — the only "native ZK" the EVM has). Per-option tally SSTOREs
   are the variable cost — and they are exactly the live-results leak.
2. **The EVM cannot encrypt natively.** Hashing is native (keccak opcode, SHA-256
   precompile; Poseidon only in-circuit). But a public VM has no secrets: encryption
   must happen client-side; the chain stores ciphertexts; decryption capability comes
   from outside (time or a committee).

## 3. Design — convergence of unification and sealing

### 3.1 `ZkBallotBox` — one contract, all modules (M-A)

One implementation (EIP-1167-cloned per poll, as today) replacing all six modules:

```solidity
struct Ballot { uint256 nullifier; bytes payload; }   // payload: plaintext word today, ciphertext in M-B
castBallot(SemaphoreProof proof, bytes payload)
  - verifyProof(proof)                  // scope = poll, message = keccak(payload) >> 8 (survey precedent)
  - nullifier unused → mark used
  - emit BallotCast(nullifier, payload) // NO per-option storage. Ever.
```

- **Diversity moves to the type layer we already built:** `kind` (pick-one / approval /
  ranked / quadratic / survey / sealed-until-reveal semantics) is init metadata;
  `core_domain.BallotSpec` already validates every kind client-side; tallying is
  **verifiable event replay** (ranked/IRV already works exactly this way — we
  generalize the precedent, not invent one).
- **What we gain:** one audit surface; one ABI; one initialize encoding; ~20–60k gas
  saved per multi-option vote (no tally SSTOREs); **no on-chain live tally to leak**
  (sealing stops being a fight against our own storage); registry unchanged
  (visibility/resultsPolicy stay).
- **What we give up:** on-chain `getResults()` for anon/approval/quadratic/survey.
  Replay is publicly verifiable (events are consensus data), and the relayer/client
  ship a deterministic tally function per kind with golden tests. Blind-vote's
  commit-reveal becomes a `kind` whose payload is the commit hash (reveal = second
  `castBallot`-like call) — its address-linkage flaw is then fixed by M-B, not
  patched in M-A.

### 3.2 Sealing M-B — timelock encryption (tlock/drand): the default

Ballot payload = tlock ciphertext encrypted to the **drand round at poll close**.

- During voting: chain holds ciphertexts; nobody (organizer, relayer, us) can read
  them. After close: the drand round signature exists; **anyone** can decrypt all
  ballots and replay the tally — same post-close transparency as today, zero
  mid-vote leak, **no committee to operate**.
- ZK's role here stays what it is today: Semaphore proves membership + binds the
  nullifier and the ciphertext hash (proof message = hash of ciphertext, so the
  relayer can't swap payloads).
- Trust added: drand's threshold network (League of Entropy) and client clock vs
  round mapping. Failure mode is graceful: a missed round only delays decryption.
- Client cost: tlock encrypt is milliseconds; decrypt-and-tally happens in the
  organizer/any client after close (results "publish" step the organizer journey
  already has).

### 3.3 Sealing M-C — threshold ElGamal + homomorphic tally: the upgrade path (documented, not built now)

Vocdoni-DAVINCI-shaped: ballots encrypted to a committee key (DKG across organizer +
relayer + volunteers); homomorphic aggregation means **only the sum is ever
decrypted — individual ballots stay sealed forever**; requires new circuits proving
ballot validity (legal option / quadratic budget) over the ciphertext. This is the
only scheme that also delivers everlasting ballot privacy and kills bandwagon +
post-close coercion simultaneously. Big lift (DKG ops, new trusted setup or PLONK,
per-kind validity circuits) — deliberately **after** M-A+M-B prove the pipeline.

### 3.4 Explicitly rejected

- On-chain "encryption" of tallies (security theater — R4 NatSpec already says why).
- Poseidon-in-Solidity hashing (50k+ gas for zero privacy gain at this layer).
- FHE/fhEVM (wrong chain, wrong decade for this project's scope).
- Per-module sealing retrofits (six times the work, keeps six audit surfaces).

## 4. Migration & compatibility

- `PollRegistry` keeps working: `ZkBallotBox` registers as new module type
  `ballot-box-v1` per kind alias; old module types remain deployable until cutover,
  then are de-registered (pre-Sepolia, local-only — no live polls to migrate).
- Relayer: one `/api/relay/ballot` route replaces five vote routes (kept as thin
  aliases for one release); the R4 initData shim retires with the old modules.
- Client: `VoterJourneyPort.relayBallot` implementations collapse into one; ballot
  kinds and journeys unchanged (the machines never knew about six contracts).
- Verify/receipts: nullifier semantics identical; `verifyParticipation` preserved.

## 5. Plan (phased, parallel-agent-sized)

- **P14a — ZkBallotBox contract + registry wiring + event-replay tally lib**
  (contracts + relayer route + golden tally tests per kind; old modules untouched).
- **P14b — client switch** (core_chain/core_relay adapters + journeys' ports to the
  unified route; replay-tally in core_domain with cross-checks vs the legacy
  on-chain tallies on seeded polls).
- **P14c — tlock sealing** (ciphertext payloads behind `resultsPolicy=sealed`,
  drand round mapping from poll close, decrypt+tally in the organizer publish step
  + any-client verification; plaintext path remains for `livePublic`).
- **P14d — legacy module retirement + Sepolia readiness** (merges Phase 10 gate).
- **P14e (parked):** threshold/homomorphic upgrade — own spec when wanted.

## 6. Open questions for the owner

1. **Post-close ballot publicity** (M-B): after close, individual ballots become
   public (anonymous via Semaphore, but contents visible — today's status quo).
   Acceptable until M-C, or does any context (boards?) need M-C first?
2. **drand dependency** acceptable as the timelock root of trust?
3. Tally canonicalization: replay rules live in `core_domain` (Dart) — do we also
   want a reference TypeScript replayer in the relayer for independent verification
   (two implementations, golden-vector locked, like the ticket lib precedent)?
