# Module: Ranked-Choice (IRV) Voting (ZkRankedVoting)

> Phase 12b. Design spec: [`docs/superpowers/specs/2026-06-02-ranked-choice-design.md`](../superpowers/specs/2026-06-02-ranked-choice-design.md)

## Privacy Dimensions
- **Identity:** anonymous (Semaphore ZK proof, no address link — same as M1)
- **Content:** public-aggregate (the full packed ranking is on-chain; individual ballots are visible — ranked-choice hides *who* ranked, not *how* they ranked)
- **Temporality:** immediate

> Ranked-choice voting (instant-runoff, IRV) is a structural sibling of M3
> `ZkApprovalVoting`: identical Semaphore membership / registration / nullifier
> model and relayer-submitted anonymity. Two differences: (1) the ballot is a
> **packed ranking** in the Semaphore `message` field rather than a bitmask, and
> (2) the **winner is computed OFF-CHAIN** — the contract stores ballots and
> tallies only round-1 first preferences. Module string: `ranked-vote`.

## How It Works

1. **Registration:** Admin registers voter identity commitments into the
   poll's Semaphore group (identical to M1/M3).

2. **Voting:** The voter ranks a prefix of the options in preference order,
   encodes the ranking as a packed `uint256 packedRanking`, passes it as the
   Semaphore `message`, generates a ZK proof, and submits
   `castVote(packedRanking, proof)`.

3. **Verification & tally:** The contract validates the packed ranking
   (non-empty prefix, no gaps, no duplicates, in-range, no high bits), checks
   the nullifier is fresh, verifies the Semaphore proof, then increments
   `voteCounts[firstChoice]` for the first-preference option only. The full
   `packedRanking` is emitted in `VoteCast(packedRanking)`.

4. **IRV winner (off-chain):** Any verifier reads all `VoteCast` events and
   replays the canonical IRV rule (see below) to a deterministic winner.
   `getResults()` returns round-1 first-preference counts and is **not** the
   winner.

## The packed-ranking ballot

`MAX_OPTIONS = 8`. The ballot is a single `uint256 packedRanking` whose low
32 bits hold up to 8 rank slots, **4 bits each**:

- Slot `i` occupies bits `[4*i, 4*i+4)`; `slot = (packedRanking >> (4*i)) & 0xF`.
- Slot value `0` = empty (no candidate at this rank).
- Slot value `1..8` = **(option index + 1)** — option `0` is encoded as `1`.

A valid ballot is a **prefix of distinct, in-range options**: rank your top-k
from most-preferred (slot 0) down; every later slot must be empty.

Examples (a 3-option poll `[A, B, C]`, slots least-significant-first):

| ranking   | slots (s2 s1 s0) | packed hex | packed dec |
|-----------|------------------|------------|------------|
| A         | `0 0 1`          | `0x001`    | 1          |
| B > A     | `0 1 2`          | `0x012`    | 18         |
| C > A > B | `2 1 3`          | `0x213`    | 531        |
| (empty)   | `0 0 0`          | `0x000`    | 0 (rejected — EmptyBallot) |

8 slots × 4 bits = **32 bits**, so `packedRanking < 2^32`, which keeps
`Number(message)` in the web prover exact (IEEE-754 double has 53-bit integer
precision).

The packed ranking is bound into the Semaphore proof as the `message` field
(`proof.message == packedRanking`). The ballot is non-malleable: nobody — not
even the relayer — can reorder or alter a ranking without invalidating the SNARK.

## Contract: ZkRankedVoting.sol

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

`castVote(uint256 packedRanking, ISemaphore.SemaphoreProof calldata proof)`
runs all reject-checks **in order, BEFORE the nullifier is marked used**, so a
rejected ballot never locks a voter out:

1. `state == Voting`                                → else `NotInVoting`
2. `_validateRanking(packedRanking)`:
   - `packedRanking < (1 << (4 * MAX_OPTIONS))` (no bits above bit 32)  → else `InvalidBallot`
   - slot 0 nonzero                                → else `EmptyBallot`
   - prefix-of-distinct-in-range (gap / dupe / out-of-range)             → else `InvalidBallot`
3. `!isNullifierUsed[proof.nullifier]`              → else `AlreadyVoted`
4. `proof.scope == uint256(uint160(address(this)))` → else `InvalidScope`
5. `proof.message == packedRanking`                 → else `TamperedVoteSignal`
6. `semaphore.verifyProof(groupId, proof)`          → else `InvalidProof`

The high-bits guard is explicit and separate: the slot loop only inspects bits
0..31, so a valid low-32 prefix plus garbage above bit 32 would otherwise
pass. After all checks pass, the nullifier is consumed, the first-preference
option `(packedRanking & 0xF) - 1` is tallied (`voteCounts[firstChoice]++`),
and `VoteCast(packedRanking)` emits the full ballot on-chain.

### Key Functions

| Function | Access | Phase | Description |
|----------|--------|-------|-------------|
| `initialize()` | Once only | -- | Validate options, create Semaphore group |
| `registerVoter()` | Owner | Registration | Add one identity commitment |
| `registerVoters()` | Owner | Registration | Batch register commitments |
| `startVoting()` | Owner | Registration | Transition to Voting (requires ≥2 options, ≥1 voter) |
| `endVoting()` | Owner | Voting | Transition to Ended |
| `castVote(packedRanking, proof)` | Anyone | Voting | One anonymous ranked ballot |
| `getState()` | Anyone | Any | Current lifecycle state |
| `getResults()` | Anyone | Any | Round-1 first-preference counts (NOT the IRV winner) |
| `getOptions()` | Anyone | Any | Option labels array |
| `getParticipantCount()` | Anyone | Any | Number of registered voters |
| `verifyParticipation()` | Anyone | Any | Check if nullifier was used |

## Tally and results semantics

`voteCounts` is incremented for the **first preference only**. Lower ranks are
not counted on-chain. `getResults()` returns round-1 first-preference counts
**and nothing else**. The first-preference leader is frequently NOT the IRV
winner — that is the entire point of instant-runoff voting. Nothing — not the
UI, not a chart — may treat `max(getResults())` as the outcome.

### Canonical off-chain IRV rule (pinned)

The winner is the result of replaying this rule over the full ballots emitted
in `VoteCast`. Every verifier MUST implement exactly this rule:

1. **Candidates** = all options; **ballots** = decoded rankings from every
   `VoteCast` event.
2. Each round, every **non-exhausted** ballot counts for its highest-ranked
   **not-yet-eliminated** candidate. A ballot whose every ranked candidate has
   been eliminated is **exhausted** and drops from the count.
3. Let `C` = number of non-exhausted ballots **this round**. If some candidate
   has **strictly more than `C/2`** votes (strict majority of continuing
   ballots, i.e. `2 * votes > C`), that candidate **wins**.
4. Otherwise eliminate the candidate with the **fewest** votes this round;
   **tie-break: lowest option index** among those tied for fewest. Repeat from
   step 2.
5. Terminate when one candidate remains (last-standing winner) or a candidate
   reaches a strict majority of continuing ballots.

`C` is re-derived each round from the non-exhausted ballot count, not the
total cast count.

## Privacy model

- **Voter anonymous:** Semaphore proves group membership and emits a one-time
  nullifier (scope = poll address) without revealing which member voted.
  Relayer-mediated submission keeps the voter's wallet/IP unlinked.
- **Ballot content public on-chain:** the full packed ranking is emitted in
  `VoteCast(packedRanking)`. This is required — the off-chain IRV needs every
  ballot to compute the winner. Ranked-choice hides *who* ranked, not *how*
  they ranked.
- **Double-vote prevention:** each nullifier can only be used once.
- **Scope binding:** `proof.scope == uint256(uint160(address(this)))` prevents
  replay across polls.

### Known Limitations
- Admin must register voters (centralized registration — same as M1).
- `getResults()` is round-1 first prefs only; UI must clearly label this and
  not present the first-pref leader as the winner.
- The off-chain IRV Dart implementation is a follow-up PR; these contract tests
  do not prove the off-chain winner, only that ballots are faithfully stored.
- `MockSemaphoreVerifier` used in local tests — real Groth16 verifier required
  for production (see honesty bound below).

## Honesty bound

Local Hardhat tests run against `MockSemaphoreVerifier`, whose `verifyProof`
**always returns `true`**. The suite proves the **storage / validation /
first-preference LOGIC** — packed-ranking decode, the prefix/distinct/in-range/
no-gap/no-high-bits checks, empty-vs-invalid boundaries, nullifier single-use,
scope/message binding, the no-lockout retry, the `VoteCast` ballot emission,
and the round-1 tally — but does **not** prove real SNARK validity. This is
the identical honesty bound as M1/M3.

The off-chain IRV winner is likewise not proven by these contract tests — it is
proven by the Dart vector tests in the follow-up UI PR. This contract slice
proves only that every ballot is faithfully stored and emitted, so that replay
is possible. Real Groth16 verification is gated behind `USE_REAL_VERIFIER`
(P4-23/P4-24) and is out of scope for this slice.
