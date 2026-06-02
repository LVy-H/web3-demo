# Phase 12b — Ranked-Choice (IRV) Voting (packed-ranking module)

Status: backend slice (contract + relayer). Flutter UI + the off-chain Dart IRV
tally (with vector tests) are a **separate follow-up PR**.
Date: 2026-06-02
Module string (canonical): `ranked-vote`

## Summary

Ranked-choice voting (a.k.a. instant-runoff voting, IRV) lets a voter rank a
**prefix of the options** in order of preference (rank your top-k; leave the
rest empty) instead of picking exactly one (M1 `ZkAnonVoting`) or approving a
set (M3 `ZkApprovalVoting`).

`ZkRankedVoting` is a **structural copy** of `ZkApprovalVoting`: identical
Semaphore membership / registration / nullifier model and the same
relayer-submitted anonymity. The differences are exactly two:

1. **The ballot encoding** — a *packed ranking* in the Semaphore `message` field
   (described below), not a single index and not a bitmask.
2. **The winner is computed OFF-CHAIN.** The contract is **storage + a
   first-preference tally only.** It does NOT run IRV. The full ranking of every
   ballot is emitted on-chain (`VoteCast(packedRanking)`) so any verifier can
   read every ballot and replay the canonical IRV rule below to a deterministic
   winner.

It is cloned + initialized through the existing `PollRegistry` exactly like
M1/M2/M3.

## Ballot encoding (packed ranking in `message`)

`MAX_OPTIONS = 8`. The ballot is a single `uint256 packedRanking` whose low 32
bits hold up to 8 rank slots, **4 bits each**:

- slot `i` occupies bits `[4*i, 4*i+4)`; `slot = (packedRanking >> (4*i)) & 0xF`.
- slot value `0` = empty (no candidate at this rank).
- slot value `1..8` = **(option index + 1)** — i.e. option `0` is encoded as `1`.

A valid ballot is a **prefix of distinct, in-range options**: you rank your
top-k from most-preferred (slot 0) downward; every later slot is empty. Formally:

- slot 0 must be nonzero (at least one ranked option — else `EmptyBallot`),
- the nonzero slots form a contiguous prefix (no gaps: once a `0` slot appears,
  all higher slots must be `0`),
- every nonzero slot is in `[1, options.length]` (in range),
- no option appears twice (distinct).

Up to 8 slots × 4 bits = **32 bits**, so `packedRanking < 2^32`. This keeps
`Number(message)` in the web prover (`codes/mobile/web_prover/entry.js`) exact:
a JS `Number` is an IEEE-754 double with 53 bits of integer precision, so a
32-bit packed value round-trips safely.

**`MAX_OPTIONS = 8` rationale:** 8 × 4 = 32-bit packed value (one comfortable
word, well under the `Number()` precision limit). Ranked-choice with more than 8
options is rare and the per-slot encoding gets heavy; 8 is the conservative cap.

Examples (a 3-option poll `[A, B, C]`, encoded least-significant-slot-first):

| ranking      | slots (s2 s1 s0) | packed hex | packed dec |
|--------------|------------------|------------|------------|
| A            | `0 0 1`          | `0x001`    | 1          |
| B            | `0 0 2`          | `0x002`    | 2          |
| B > A        | `0 1 2`          | `0x012`    | 18         |
| C > A > B    | `2 1 3`          | `0x213`    | 531        |
| (empty)      | `0 0 0`          | `0x000`    | 0 (rejected) |

The packed ranking is bound into the Semaphore proof as the `message` field
(`proof.message == packedRanking`), exactly the way M1 binds the option index
and M3 binds the bitmask. The ballot is therefore non-malleable: nobody (not
even the relayer) can reorder or alter a ranking without invalidating the SNARK,
which signs over `message`. The web prover passes the signal through
`generateProof(id, group, Number(message), scope)` unchanged — no prover change
is needed; the caller passes the packed ranking as the message.

## Contract validation (`castVote(packedRanking, proof)`)

All checks below run, **in this order, BEFORE the nullifier is marked used**, so
a rejected ballot never locks a voter out (they may retry with a valid ballot
using the same identity / same nullifier). This is the identical no-lockout
discipline of M1/M3.

1. `state == Voting`                                 → else `NotInVoting`
2. `_validateRanking(packedRanking)`:
   - `packedRanking < (1 << (4 * MAX_OPTIONS))` (no bits above bit 32) → else `InvalidBallot`
   - slot 0 nonzero                                  → else `EmptyBallot`
   - prefix-of-distinct-in-range (gap / dupe / out-of-range) → else `InvalidBallot`
3. `!isNullifierUsed[proof.nullifier]`               → else `AlreadyVoted`
4. `proof.scope == uint256(uint160(address(this)))`  → else `InvalidScope`
5. `proof.message == packedRanking`                  → else `TamperedVoteSignal` (bind ballot to proof)
6. `semaphore.verifyProof(groupId, proof)`           → else `InvalidProof`

`_validateRanking` algorithm (≤8 iterations, gas trivial):

```
require packedRanking < (1 << 32)              // else InvalidBallot — high bits
require (packedRanking & 0xF) != 0             // else EmptyBallot — slot0 empty
seen = 0                                        // bitset of used option indices
ended = false                                   // have we hit the first empty slot?
for i in 0..7:
    slot = (packedRanking >> (4*i)) & 0xF
    if slot == 0:
        ended = true                            // empty slot ⇒ rest must be empty
        continue
    if ended:        revert InvalidBallot       // gap: nonzero after an empty slot
    if slot > options.length:  revert InvalidBallot   // out of range
    bit = 1 << (slot - 1)
    if seen & bit != 0:  revert InvalidBallot   // duplicate option
    seen |= bit
```

> **Note — the high-bits check is its own guard.** The slot loop only inspects
> bits 0..31. A value with a valid low-32 prefix *plus* garbage above bit 32
> sails through the loop, so the `packedRanking < (1 << 32)` guard is explicit
> and separate, and it reverts `InvalidBallot` (not `EmptyBallot`).

Only after all checks pass:

```solidity
isNullifierUsed[proof.nullifier] = true;
uint256 firstChoice = (packedRanking & 0xF) - 1;   // slot0 ≥ 1 guaranteed by validation
voteCounts[firstChoice]++;                          // FIRST-PREFERENCE tally ONLY
emit VoteCast(packedRanking);                        // full ballot on-chain for off-chain IRV
```

The `- 1` is underflow-safe **only because** `_validateRanking` guarantees slot 0
≥ 1. Keep `_validateRanking` strictly before the tally, same ordering discipline
as the nullifier write.

`voteCounts` is incremented for the **first preference only** — lower ranks are
NOT counted on-chain. The contract never runs IRV; it stores ballots and tallies
round-1 first preferences.

## Canonical off-chain IRV (the app + ANY verifier MUST implement exactly this)

This is load-bearing: without a single pinned rule, "verifiable by replay" is
false. The off-chain tally is **deterministic** given the public ballots (read
from `VoteCast` events) + this rule:

1. Candidates = all options; ballots = the decoded rankings from every
   `VoteCast`.
2. Each round, every **non-exhausted** ballot counts for its highest-ranked
   **not-yet-eliminated** candidate. A ballot whose every ranked candidate has
   been eliminated is **exhausted** and drops out of the count.
3. Let `C` = number of non-exhausted ballots **this round**. If some candidate
   has **strictly more than `C/2`** votes (strict majority of *continuing*
   ballots), they **WIN**.
4. Otherwise eliminate the candidate with the **fewest** votes this round;
   **tie-break: lowest option index** among those tied for fewest. Repeat.
5. Terminate when one candidate remains (winner) or a candidate reaches a strict
   majority of continuing ballots.

### Required test vectors (the 12b UI PR implements this in Dart)

The follow-up UI PR implements this rule in Dart and MUST test it against fixed
vectors that include at least:

- **(a) a normal transfer** — a candidate is eliminated and their ballots'
  next-ranked continuing candidate gains those votes, changing the leader.
- **(b) an elimination tie resolved by lowest index** — two candidates tied for
  fewest votes in a round; the one with the lower option index is eliminated.
- **(c) an exhausted-ballot case** — a ballot whose ranked candidates are all
  eliminated drops out; the continuing-ballot count `C` shrinks and the
  strict-majority threshold `C/2` is recomputed against the smaller `C`.

## `getResults()` is round-1 first preferences ONLY — NOT the winner

`getResults()` returns the per-option **round-1 first-preference counts** and
NOTHING ELSE. **The first-preference leader is frequently NOT the IRV winner**
(that is the entire point of instant-runoff). Nothing — not the UI, not a
verifier, not a chart — may treat `max(getResults())` as the outcome. The
winner is **only** the result of replaying the canonical IRV rule above over the
full ballots emitted in `VoteCast`.

## Privacy model

Same as M1 / M3:

- The **voter is anonymous**: Semaphore proves membership in the registered
  group and produces a one-time nullifier without revealing which member voted;
  relayer-mediated submission keeps the voter's wallet/IP unlinked.
- The **ballot content (the ranking) is PUBLIC on-chain**: the full packed
  ranking is emitted in `VoteCast(packedRanking)`. Ranked-choice does NOT hide
  *what* was ranked, only *who* ranked it. (It must be public — the off-chain
  IRV needs every ballot to compute the winner.)

## HONESTY BAR

Local Hardhat tests run against `MockSemaphoreVerifier`, whose `verifyProof`
**always returns `true`**. So the suite proves the **storage / validation /
first-preference LOGIC** — packed-ranking decode, the prefix/distinct/in-range/
no-gap/no-high-bits checks, empty-vs-invalid boundaries, nullifier single-use,
scope/message binding, the no-lockout retry, the `VoteCast` ballot emission, and
the round-1 tally — but it does **NOT** prove real SNARK validity. Identical
honesty bound to M1/M3. Real Groth16 verification is gated behind
`USE_REAL_VERIFIER` (P4-23/P4-24) and is out of scope for this slice.

The off-chain IRV winner is likewise **not** proven by these contract tests — it
is proven by the Dart vector tests in the follow-up UI PR. This contract slice
proves only that every ballot is faithfully stored and emitted, so that replay
is *possible*.

## Canonical module string: `ranked-vote`

Used **identically** in:

- `scripts/deploy.ts` — `registerModule("ranked-vote", impl)`
- `test/ZkRankedVoting.test.ts` — `registerModule` / `createPoll`
- the relayer (the `/api/relay/ranked-vote` route + validator)
- and is the canonical string the Flutter UI follow-up PR MUST reuse — the
  create-poll flow dispatches `?module=ranked-vote` and renders a drag-to-rank
  ballot screen.

We do not repeat M1's `anon-vote`/`zk-anon-voting` inconsistency.

## Layers in THIS PR (backend slice)

1. `codes/contracts/contracts/ZkRankedVoting.sol` — the module (structural copy
   of M3; `MAX_OPTIONS = 8`, `castVote(packedRanking, proof)`, `_validateRanking`,
   first-pref tally + `VoteCast(packedRanking)`).
2. `codes/contracts/test/ZkRankedVoting.test.ts` — clone-deploy harness against
   `MockSemaphoreVerifier`.
3. `codes/contracts/scripts/deploy.ts` — deploy impl + `registerModule("ranked-vote", …)`.
4. `codes/contracts/scripts/copyAbis.ts` + `codes/mobile/assets/abi/ZkRankedVoting.json`
   — ABI export. `pubspec.yaml` globs `assets/abi/` as a directory, so no
   pubspec change is needed.
5. `codes/relayer/` — `validateRankedVoteRequest` + `relayRankedVote` +
   `POST /api/relay/ranked-vote`, mirroring the approval-vote relay path. The
   existing `/vote` and `/approval-vote` paths are untouched. The relayer does
   **not** reimplement IRV or per-slot validation — the contract owns that; the
   relayer only checks `packedRanking ∈ [1, 2^32)`, `message == String(packedRanking)`,
   and `scope == BigInt(pollAddress).toString()`.

## Out of scope (follow-up PR)

- The Flutter UI: a drag-to-rank ballot screen (ordered list → packed ranking),
  results rendering (round-1 first-prefs, clearly labelled NOT the winner), and
  the create-poll dispatch on `?module=ranked-vote`.
- The **Dart off-chain IRV tally** implementing the canonical rule above, with
  the (a)/(b)/(c) vector tests.
