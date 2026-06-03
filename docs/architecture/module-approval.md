# Module: Approval Voting (ZkApprovalVoting)

> Phase 12a. Design spec: [`docs/superpowers/specs/2026-06-02-approval-voting-design.md`](../superpowers/specs/2026-06-02-approval-voting-design.md)

## Privacy Dimensions
- **Identity:** anonymous (Semaphore ZK proof, no address link — same as M1)
- **Content:** public-aggregate (the bitmask is on-chain; per-option approval counts are live — approval voting hides *who* approved, not *what*)
- **Temporality:** immediate

> Approval voting is a sibling of M1 `ZkAnonVoting`: identical Semaphore
> membership / registration / nullifier model and relayer-submitted anonymity.
> The only behavioral difference is the ballot: instead of a single option
> index, the voter submits a **bitmask** encoding the set of approved options,
> and the tally increments **every** approved option. Module string: `approval-vote`.

## How It Works

1. **Registration:** Admin registers voter identity commitments into the
   poll's Semaphore group (identical to M1).

2. **Voting:** The voter selects any non-empty subset of options, computes the
   `bitmask` (bit `i` set ⇒ option `i` approved), passes it as the Semaphore
   `message`, generates a ZK proof, and submits `castVote(bitmask, proof)`.

3. **Verification & tally:** The contract validates the bitmask (non-empty,
   no out-of-range bits), checks the nullifier is fresh, verifies the Semaphore
   proof, then increments `voteCounts[i]` for every set bit.

4. **Results:** `getResults()` returns per-option approval counts. Because a
   single voter approves multiple options, the sum of `getResults()` can exceed
   the participant count — this is by design.

## The bitmask ballot

The ballot is a single `uint256 bitmask`. Bit `i` (from LSB) set means "option
`i` is approved":

```
bitmask = Σ over approved options i of (1 << i)
```

Examples (a 3-option poll `[A, B, C]`):

| bitmask (dec) | binary | approves   |
|---------------|--------|------------|
| 1             | 001    | A          |
| 5             | 101    | A and C    |
| 7             | 111    | A, B, C    |
| 0             | 000    | (rejected — EmptyBallot) |

The bitmask is bound into the Semaphore proof as the `message` field
(`proof.message == bitmask`), exactly the way M1 binds the option index.
The ballot is therefore non-malleable: nobody — not even the relayer — can
alter which options were approved without invalidating the SNARK.

The web prover passes the signal through `generateProof(id, group, Number(message), scope)`
unchanged. A bitmask over ≤32 options is at most 32 bits, well under the
IEEE-754 double's 53-bit integer precision, so it round-trips exactly.

### The 32-option cap

`uint256 public constant MAX_OPTIONS = 32;` — `initialize` reverts
(`TooManyOptions`) if `options.length > MAX_OPTIONS`.

The on-chain `bitmask` itself is a full `uint256`; `MAX_OPTIONS = 32` caps
`options.length` as a conservative UI / sanity guardrail (not a correctness
boundary — a bitmask stays exact under `Number()` well past 32 options).

## Contract: ZkApprovalVoting.sol

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
    string[] calldata _initialOptions
) external initializer
```
`_disableInitializers()` in the implementation constructor makes the bare
implementation non-initializable — only EIP-1167 clones produced by
`PollRegistry` are usable.

### Validation & no-lockout discipline

`castVote(uint256 bitmask, ISemaphore.SemaphoreProof calldata proof)` runs
all reject-checks **in order, BEFORE the nullifier is marked used**, so a
rejected ballot never locks a voter out (they retry with a valid ballot using
the same identity / nullifier):

1. `state == Voting`                                → else `NotInVoting`
2. `bitmask != 0`                                   → else `EmptyBallot`
3. `bitmask < (1 << options.length)`                → else `InvalidBallot` (no out-of-range bits)
4. `!isNullifierUsed[proof.nullifier]`              → else `AlreadyVoted`
5. `proof.scope == uint256(uint160(address(this)))` → else `InvalidScope`
6. `proof.message == bitmask`                        → else `TamperedVoteSignal`
7. `semaphore.verifyProof(groupId, proof)`          → else `InvalidProof`

Only then is the nullifier consumed and the tally folded: `voteCounts[i]++`
for every bit `i` set in `bitmask`. `VoteCast(bitmask)` emits the ballot
on-chain.

### Key Functions

| Function | Access | Phase | Description |
|----------|--------|-------|-------------|
| `initialize()` | Once only | -- | Validate options, create Semaphore group |
| `registerVoter()` | Owner | Registration | Add one identity commitment |
| `registerVoters()` | Owner | Registration | Batch register commitments |
| `startVoting()` | Owner | Registration | Transition to Voting (requires ≥2 options, ≥1 voter) |
| `endVoting()` | Owner | Voting | Transition to Ended |
| `castVote(bitmask, proof)` | Anyone | Voting | One anonymous approval ballot |
| `getState()` | Anyone | Any | Current lifecycle state |
| `getResults()` | Anyone | Any | Per-option approval counts (authoritative) |
| `getOptions()` | Anyone | Any | Option labels array |
| `getParticipantCount()` | Anyone | Any | Number of registered voters |
| `verifyParticipation()` | Anyone | Any | Check if nullifier was used |

## Privacy model

- **Voter anonymous:** Semaphore proves group membership and emits a one-time
  nullifier (scope = poll address) without revealing which member voted.
  Relayer-mediated submission keeps the voter's wallet/IP unlinked.
- **Ballot content public on-chain:** the bitmask is emitted in `VoteCast(bitmask)`
  and the per-option approvals are readable via `getResults()`. Approval voting
  hides *who* approved, not *what* was approved.
- **Double-vote prevention:** each nullifier can only be used once.
- **Scope binding:** `proof.scope == uint256(uint160(address(this)))` prevents
  replay across polls.

### Known Limitations
- Admin must register voters (centralized registration — same as M1).
- Small-group deanonymization: with a small registered set, ballot content
  plus who voted can narrow identity by elimination.
- Options and option count are fixed at `startVoting()` for practical purposes
  (options can only be added during Registration).
- `MockSemaphoreVerifier` used in local tests — real Groth16 verifier required
  for production (see honesty bound below).

## Honesty bound

Local Hardhat tests run against `MockSemaphoreVerifier`, whose `verifyProof`
**always returns `true`**. The test suite proves the **tally and validation
LOGIC** — bitmask decoding, range/empty checks, nullifier single-use,
scope/message binding, the no-lockout retry, and the per-option approval
counts — but does **not** prove real SNARK validity. This is exactly the
same honesty bound as M1 `ZkAnonVoting`. Real Groth16 verification is gated
behind `USE_REAL_VERIFIER` (P4-23/P4-24) and is out of scope for this slice.
