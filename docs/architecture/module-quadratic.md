# Module: Quadratic Voting (ZkQuadraticVoting)

> Phase 12c. Design spec: [`docs/superpowers/specs/2026-06-03-quadratic-voting-design.md`](../superpowers/specs/2026-06-03-quadratic-voting-design.md)

## Privacy Dimensions
- **Identity:** anonymous (Semaphore ZK proof, no address link — same as M1)
- **Content:** public-aggregate (the packed allocation is on-chain; per-option vote sums are live — quadratic voting hides *who* spent credits, not *how* they were spent)
- **Temporality:** immediate

> Quadratic voting (QV) is a structural sibling of M3 `ZkApprovalVoting`:
> identical Semaphore membership / registration / nullifier model and
> relayer-submitted anonymity. The ballot is a **packed allocation** — a voter
> spends a fixed budget of credits across the options, where casting `vᵢ` votes
> for option `i` costs `vᵢ²`. The square cost dampens majority tyranny and
> surfaces minority intensity. Module string: `quadratic-vote`.

## Why a uniform budget

True QV with per-voter budgets cannot be done anonymously with the stock
Semaphore circuit: Semaphore proves "I am *some* registered member" and emits a
nullifier, but carries no per-member attribute (a credit balance) that the
contract could trust. Binding one would require a custom circuit. So v1 fixes
the budget at `CREDITS = 100` for every voter — uniform budget is the maximal
QV variant that keeps the M1/M2/M3 anonymity model intact.

## The packed-allocation ballot

`MAX_OPTIONS = 8`, `CREDITS = 100`. The ballot is a single `uint256 packedAlloc`
whose low 32 bits hold up to 8 allocation slots, **4 bits each**:

- Slot `i` occupies bits `[4*i, 4*i+4)`; `vᵢ = (packedAlloc >> (4*i)) & 0xF`.
- `vᵢ` is the **number of votes** for option `i` (range `[0, 15]`).
- Cost of option `i` is `vᵢ²`; total cost `Σ vᵢ²` must be `≤ CREDITS`.
- Slot value `0` is a valid allocation (spend nothing on that option); a ballot
  is empty only when **every** slot is `0`.

`vᵢ ∈ [0,15]` never clips a legal ballot: the budget caps any single option at
`v = 10` (10² = 100 = `CREDITS`), well under 15. 8 slots × 4 bits = **32 bits**,
so `packedAlloc < 2^32`, keeping `Number(message)` in the web prover exact
(IEEE-754 double has 53-bit integer precision).

Examples (a 3-option poll `[A, B, C]`, slots least-significant-first; `vC vB vA`):

| allocation (vA, vB, vC) | cost Σvᵢ² | packed hex | result |
|-------------------------|-----------|------------|--------|
| (10, 0, 0)              | 100       | `0x00A`    | ok (exactly 100) |
| (6, 8, 0)               | 36+64=100 | `0x086`    | ok (exactly 100) |
| (5, 5, 5)               | 75        | `0x555`    | ok |
| (0, 0, 0)               | 0         | `0x000`    | rejected — EmptyBallot |

The packed allocation is bound into the Semaphore proof as the `message` field
(`proof.message == packedAlloc`), exactly the way M1 binds the option index and
M3 binds the bitmask. The ballot is non-malleable: nobody — not even the relayer
— can re-weight the allocation without invalidating the SNARK.

## Contract: ZkQuadraticVoting.sol

### State Machine
```
Registration ──startVoting()──> Voting ──endVoting()──> Ended
     │                            │
     ├── registerVoter() (owner)  └── castVote() (anyone, one ballot/voter)
     └── registerVoters() (owner)
```

### Initialization (Minimal Proxy Pattern)
```solidity
function initialize(
    address _semaphoreAddress,
    address _owner,
    string[] calldata _initialOptions,
    uint8 _resultsPolicy          // R4: 0 = sealed-until-close (default), 1 = live-public
) external initializer
```
`_disableInitializers()` in the implementation constructor makes the bare
implementation non-initializable — only EIP-1167 clones produced by
`PollRegistry` are usable.

### Validation & no-lockout discipline

`castVote(uint256 packedAlloc, ISemaphore.SemaphoreProof calldata proof)` runs
all reject-checks **in order, BEFORE the nullifier is marked used**, so a
rejected ballot never locks a voter out. The validation order is fixed and
load-bearing:

1. `state == Voting`                                → else `NotInVoting`
2. `_validateAllocation(packedAlloc)`:
   - **Ghost-slot rule:** every slot at index `i ≥ options.length` must be `0`
     → else `InvalidBallot` *(runs first so a "ghost-only" ballot surfaces as
     `InvalidBallot`, not `EmptyBallot`)*
   - `Σ vᵢ²` over `i < options.length` `≤ CREDITS`  → else `OverBudget`
   - `Σ vᵢ` over `i < options.length` `≥ 1`          → else `EmptyBallot`
   - `packedAlloc < (1 << (4 * MAX_OPTIONS))` (no bits above bit 32)
                                                     → else `InvalidBallot`
3. `!isNullifierUsed[proof.nullifier]`              → else `AlreadyVoted`
4. `proof.scope == uint256(uint160(address(this)))` → else `InvalidScope`
5. `proof.message == packedAlloc`                   → else `TamperedVoteSignal`
6. `semaphore.verifyProof(groupId, proof)`          → else `InvalidProof`

**Ghost-slot rule:** slots beyond `options.length` are never summed or tallied.
Without an explicit check, a nonzero ghost slot would be silently ignored, making
a malformed ballot appear valid. The ghost-slot check rejects it as
`InvalidBallot` up front.

**High-bits guard is separate:** when `options.length == MAX_OPTIONS (8)` the
ghost-slot loop runs zero iterations, so only this explicit guard catches bits at
or above bit 32.

Only after all checks pass, the nullifier is consumed and the tally folded:

```solidity
for (uint256 i = 0; i < options.length; i++) {
    voteCounts[i] += (packedAlloc >> (4 * i)) & 0xF;   // add VOTES, not cost
}
emit VoteCast(packedAlloc);
```

The tally adds **votes `vᵢ`** (not cost `vᵢ²`) to each option's running sum.

### Key Functions

| Function | Access | Phase | Description |
|----------|--------|-------|-------------|
| `initialize()` | Once only | -- | Validate options, create Semaphore group |
| `registerVoter()` | Owner | Registration | Add one identity commitment |
| `registerVoters()` | Owner | Registration | Batch register commitments |
| `startVoting()` | Owner | Registration | Transition to Voting (requires ≥2 options, ≥1 voter) |
| `endVoting()` | Owner | Voting | Transition to Ended |
| `castVote(packedAlloc, proof)` | Anyone | Voting | One anonymous quadratic ballot |
| `getState()` | Anyone | Any | Current lifecycle state |
| `getResults()` | Anyone | Any | Per-option vote sums (authoritative) |
| `getOptions()` | Anyone | Any | Option labels array |
| `getParticipantCount()` | Anyone | Any | Number of registered voters |
| `verifyParticipation()` | Anyone | Any | Check if nullifier was used |

## Tally and results semantics

`getResults()` returns the per-option **on-chain sum of the votes `vᵢ`** allocated
to each option across all accepted ballots. This IS the authoritative outcome:
the option with the highest entry wins. There is **no off-chain replay** (contrast
M4 ranked-choice). The QV nonlinearity lives entirely in the cost function
(`vᵢ²` against `CREDITS`) enforced at cast time; once a ballot is accepted the
votes it allocated are summed linearly on-chain.

`VoteCast(packedAlloc)` emits the full ballot for auditability and re-derivation,
but no replay is needed to learn the outcome.

## Privacy model

- **Voter anonymous:** Semaphore proves group membership and emits a one-time
  nullifier (scope = poll address) without revealing which member voted.
  Relayer-mediated submission keeps the voter's wallet/IP unlinked.
- **Ballot content public on-chain:** the packed allocation is emitted in
  `VoteCast(packedAlloc)` and folded into public `voteCounts`. Quadratic voting
  hides *who* spent credits, not *how* they were spent.
- **Double-vote prevention:** each nullifier can only be used once.
- **Scope binding:** `proof.scope == uint256(uint160(address(this)))` prevents
  replay across polls.

### Known Limitations
- Admin must register voters (centralized registration — same as M1).
- Uniform budget only: per-voter / token-weighted budgets require a custom
  circuit and are explicitly out of scope for v1.
- `MockSemaphoreVerifier` used in local tests — real Groth16 verifier required
  for production (see honesty bound below).

## Honesty bound

Local Hardhat tests run against `MockSemaphoreVerifier`, whose `verifyProof`
**always returns `true`**. The suite proves the **storage / validation / tally
LOGIC** — packed-allocation decode, the ghost-slot rule, the `Σ vᵢ² ≤ CREDITS`
budget check, the empty-vs-over-budget-vs-invalid boundaries, the high-bits
guard, nullifier single-use, scope/message binding, the no-lockout retry on the
`OverBudget` and ghost-slot paths, the `VoteCast` ballot emission, and the
per-option vote-sum tally — but does **not** prove real SNARK validity. This is
the identical honesty bound as M1/M2/M3. Unlike the ranked module, there is no
separate off-chain winner to prove: `getResults()` is the authoritative tally,
and the contract tests exercise it directly. Real Groth16 verification is gated
behind `USE_REAL_VERIFIER` (P4-23/P4-24) and is out of scope for this slice.
