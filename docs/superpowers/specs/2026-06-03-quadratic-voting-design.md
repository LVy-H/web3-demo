# Phase 12c — Quadratic Voting (uniform-budget, packed-allocation module)

Status: backend slice (contract + relayer). Flutter UI is a **separate
follow-up PR**.
Date: 2026-06-03
Module string (canonical): `quadratic-vote`

## Summary

Quadratic voting (QV) lets a voter express **intensity of preference**: instead
of a single index (M1 `ZkAnonVoting`), a set (M3 `ZkApprovalVoting`), or a
ranking (M2 `ZkRankedVoting`), the voter spends a fixed budget of vote *credits*
across the options, where casting `vᵢ` votes for option `i` costs `vᵢ²`. The
square cost is what makes it "quadratic": doubling your votes for an option
costs four times as many credits, so concentrating all your weight on one option
is expensive and spreading it is cheap. This dampens tyranny-of-the-majority and
surfaces minority intensity.

`ZkQuadraticVoting` is a **structural copy** of M3 `ZkApprovalVoting`: identical
Semaphore membership / registration / nullifier model and the same
relayer-submitted anonymity. It is cloned + initialized through the existing
`PollRegistry` exactly like M1/M2/M3.

### Why a UNIFORM budget (the honest scope boundary)

True QV with **per-voter** budgets (different voters get different numbers of
credits, e.g. token-weighted) **cannot be done anonymously with the stock
Semaphore circuit**. Semaphore proves "I am *some* registered member" and emits
a nullifier; it does **not** carry a per-member attribute (a credit balance) that
the contract could trust, and binding one would require a custom circuit that
proves `the hidden member's budget == B` without revealing the member. That is a
separate, much larger piece of work (custom circuit + trusted artifacts) and is
explicitly out of scope.

So v1 fixes the design at the only point that *is* anonymously provable: **every
voter gets the SAME budget.** `CREDITS = 100` for everyone. The anonymity set is
"all registered members", each member is interchangeable, and the only thing the
contract must check per ballot is `Σ vᵢ² ≤ CREDITS` — which is computable purely
from the public ballot, needs no per-voter secret, and therefore composes
cleanly with the anonymous-membership proof. Uniform-budget QV is the maximal QV
variant that keeps M1/M2/M3's anonymity model intact.

## Ballot encoding (packed allocation in `message`)

`MAX_OPTIONS = 8`, `CREDITS = 100`. The ballot is a single `uint256 packedAlloc`
whose low 32 bits hold up to 8 allocation slots, **4 bits each**:

- slot `i` occupies bits `[4*i, 4*i+4)`; `vᵢ = (packedAlloc >> (4*i)) & 0xF`.
- `vᵢ` is the **number of votes** the voter casts for option `i`; its range is
  therefore `[0, 15]` (4 bits).
- cost of option `i` is `vᵢ²`; total cost `Σ vᵢ²` must be `≤ CREDITS`.

Note this is a *direct* encoding (slot `i` ⇒ option `i`), unlike the ranked
module where the slot value was `optionIndex + 1`. Here `0` is a perfectly valid
allocation (spend nothing on option `i`); a ballot is empty only when **every**
slot is `0`.

`vᵢ ∈ [0,15]` is loose enough to never be the binding constraint: the budget caps
a single option at `v=10` (10² = 100 = `CREDITS`), well under 15, so the 4-bit
field never clips a legal ballot. 8 slots × 4 bits = **32 bits**, so
`packedAlloc < 2^32`. This keeps `Number(message)` in the web prover
(`codes/mobile/web_prover/entry.js`) exact: a JS `Number` is an IEEE-754 double
with 53 bits of integer precision, so a 32-bit packed value round-trips safely —
identical reasoning to M2/M3.

**`MAX_OPTIONS = 8` rationale:** 8 × 4 = 32-bit packed value (one comfortable
word, well under the `Number()` precision limit), and matches M2's cap. QV with
more than 8 options is rare and the per-slot encoding gets heavy; 8 is the
conservative cap, enforced at `initialize` (`> MAX_OPTIONS` ⇒ `TooManyOptions`).

`CREDITS = 100` rationale: 100 credits gives a clean intensity ladder — a voter
can put up to 10 votes on a single option (10²=100), or spread (e.g. 6+8 → 36+64
= 100, or seven options at 3 each + leftover → 7·9 = 63 ≤ 100). It is a round,
demo-legible budget; the exact number is policy, not a correctness boundary.

Examples (a 3-option poll `[A, B, C]`, slots least-significant-first; `vC vB vA`):

| allocation (vA,vB,vC) | slots (s2 s1 s0) | cost Σvᵢ²        | packed hex | packed dec | result        |
|-----------------------|------------------|------------------|------------|------------|---------------|
| (10, 0, 0)            | `0 0 A`          | 100              | `0x00A`    | 10         | ok (exactly 100) |
| (6, 8, 0)             | `0 8 6`          | 36+64 = 100      | `0x086`    | 134        | ok (exactly 100) |
| (5, 5, 5)             | `5 5 5`          | 25·3 = 75        | `0x555`    | 1365       | ok            |
| (11, 0, 0)            | —                | —                | —          | —          | v=11 unreachable (4-bit max 15 but cost 121 > 100 ⇒ OverBudget) |
| (0, 0, 0)             | `0 0 0`          | 0                | `0x000`    | 0          | rejected `EmptyBallot` |

The packed allocation is bound into the Semaphore proof as the `message` field
(`proof.message == packedAlloc`), exactly the way M1 binds the option index, M3
binds the bitmask, and M2 binds the packed ranking. The ballot is therefore
non-malleable: nobody (not even the relayer) can re-weight the allocation without
invalidating the SNARK, which signs over `message`. The web prover passes the
signal through `generateProof(id, group, Number(message), scope)` unchanged — no
prover change is needed; the caller passes the packed allocation as the message.

## Contract validation (`castVote(packedAlloc, proof)`)

All checks below run, **in this order, BEFORE the nullifier is marked used**, so
a rejected ballot never locks a voter out (they may retry with a valid ballot
using the same identity / same nullifier). This is the identical no-lockout
discipline of M1/M2/M3.

1. `state == Voting`                                       → else `NotInVoting`
2. **Ghost-slot rule** — for every `i ≥ options.length`, require `vᵢ == 0`
                                                           → else `InvalidBallot`
3. `sumSq = Σ vᵢ²` over `i < options.length`; require `sumSq ≤ CREDITS`
                                                           → else `OverBudget`
4. `sumV = Σ vᵢ` over `i < options.length`; require `sumV ≥ 1`
                                                           → else `EmptyBallot`
5. **High-bits guard** — `packedAlloc < (1 << (4 * MAX_OPTIONS))`
                                                           → else `InvalidBallot`
6. `!isNullifierUsed[proof.nullifier]`                     → else `AlreadyVoted`
7. `proof.scope == uint256(uint160(address(this)))`        → else `InvalidScope`
8. `proof.message == packedAlloc`                          → else `TamperedVoteSignal`
9. `semaphore.verifyProof(groupId, proof)`                 → else `InvalidProof`

Only after all checks pass:

```solidity
isNullifierUsed[proof.nullifier] = true;
for (uint256 i = 0; i < options.length; i++) {
    voteCounts[i] += (packedAlloc >> (4 * i)) & 0xF;   // add the VOTES, not the cost
}
emit VoteCast(packedAlloc);
```

The tally adds **votes** `vᵢ` (not the cost `vᵢ²`) to each option's running sum.

### The ghost-slot rule is load-bearing

`vᵢ` is decoded for every slot `i = 0..7`, but a poll has only `options.length`
options. Both the budget loop and the tally loop are bounded by `options.length`
(slots beyond it are never summed and never tallied). Without an explicit check,
a voter could pack a nonzero value into a slot `i ≥ options.length` — an
allocation to an option that does not exist — and it would be **silently
ignored**: it costs nothing against the budget, contributes nothing to any
tally, and the ballot is accepted. That is a malformed ballot masquerading as
valid (and, if any future code path iterated over all 8 slots instead of
`options.length`, it would index a non-existent option → OOB revert / lockout).
So we reject it up front: **every slot at index `≥ options.length` must be 0**,
else `InvalidBallot`. This is the QV analogue of M2's gap/out-of-range checks.

### The high-bits guard is a SEPARATE guard

The ghost-slot loop and the budget/tally loops only inspect slots `0..7` (bits
`0..31`). When `options.length == MAX_OPTIONS (8)`, the ghost-slot loop runs
**zero** iterations (there is no `i ≥ 8` below the `MAX_OPTIONS` bound), so a
value with a valid low-32 allocation **plus garbage above bit 32** would sail
through every other check. The explicit `packedAlloc < (1 << (4 * MAX_OPTIONS))`
guard is therefore not redundant with the ghost-slot rule — it is the only thing
that rejects bits ≥ 32. It reverts `InvalidBallot`. (Same separation rationale as
M2's high-bits guard.)

## `getResults()` IS the authoritative tally (on-chain, per-option vote sum)

Unlike M2 ranked-choice — where `getResults()` is only a round-1 first-preference
count and the *real* winner is computed off-chain by replaying IRV —
**`ZkQuadraticVoting.getResults()` IS the final, authoritative outcome.** It
returns, per option, the **on-chain sum of the votes `vᵢ` allocated to that
option across all ballots**. There is **no off-chain replay, no second tally
rule.** The option with the highest `getResults()` entry is the winner, full
stop. The QV nonlinearity lives entirely in the *cost* function (`vᵢ²` against a
fixed budget) enforced at cast time; once a ballot is accepted, the votes it
allocated are summed linearly on-chain, and that sum is the result.

(`VoteCast(packedAlloc)` is still emitted with the full ballot for auditability /
re-derivation, but nothing needs to replay it to learn the outcome — the
on-chain `voteCounts` already is the outcome.)

## Privacy model

Same as M1 / M2 / M3:

- The **voter is anonymous**: Semaphore proves membership in the registered
  group and produces a one-time nullifier without revealing which member voted;
  relayer-mediated submission keeps the voter's wallet/IP unlinked.
- The **ballot content (the allocation) is PUBLIC on-chain**: the full packed
  allocation is emitted in `VoteCast(packedAlloc)` and folded into the public
  `voteCounts`. QV does NOT hide *how* the credits were spent, only *who* spent
  them.

## HONESTY BAR

Local Hardhat tests run against `MockSemaphoreVerifier`, whose `verifyProof`
**always returns `true`**. So the suite proves the **storage / validation /
tally LOGIC** — packed-allocation decode, the ghost-slot rule, the
`Σ vᵢ² ≤ CREDITS` budget check, the empty-vs-over-budget-vs-invalid boundaries,
the high-bits guard, nullifier single-use, scope/message binding, the no-lockout
retry on the OverBudget AND ghost-slot paths, the `VoteCast` ballot emission, and
the per-option vote-sum tally — but it does **NOT** prove real SNARK validity.
Identical honesty bound to M1/M2/M3. Real Groth16 verification is gated behind
`USE_REAL_VERIFIER` (P4-23/P4-24) and is out of scope for this slice.

Unlike M2, there is **no** separate off-chain winner to prove: `getResults()` is
the authoritative tally, and these contract tests exercise it directly (the
3-voter `getResults` case asserts the exact per-option sums).

## Canonical module string: `quadratic-vote`

Used **identically** in:

- `scripts/deploy.ts` — `registerModule("quadratic-vote", impl)`
- `test/ZkQuadraticVoting.test.ts` — `registerModule` / `createPoll`
- the relayer (the `/api/relay/quadratic-vote` route + validator)
- and is the canonical string the Flutter UI follow-up PR MUST reuse — the
  create-poll flow dispatches `?module=quadratic-vote` and renders a
  credit-allocation ballot screen.

We do not repeat M1's `anon-vote`/`zk-anon-voting` inconsistency.

## Layers in THIS PR (backend slice)

1. `codes/contracts/contracts/ZkQuadraticVoting.sol` — the module (structural
   copy of M3; `MAX_OPTIONS = 8`, `CREDITS = 100`,
   `castVote(packedAlloc, proof)`, ghost-slot + budget + empty + high-bits
   validation, per-option vote-sum tally + `VoteCast(packedAlloc)`). New error
   `OverBudget`; the rest reuse the sibling error set.
2. `codes/contracts/test/ZkQuadraticVoting.test.ts` — clone-deploy harness
   against `MockSemaphoreVerifier` with executable boundary vectors
   (`Σvᵢ²==100` ok / `==101` OverBudget; single `v=10` ok / `v=11` OverBudget;
   ghost-slot `InvalidBallot`; empty `EmptyBallot`; no-lockout retry on the
   OverBudget AND ghost-slot paths; double-vote `AlreadyVoted`; tampered message
   `TamperedVoteSignal` + no-lockout; `>8` options `TooManyOptions`; 3-voter
   `getResults` exact sums; IZkPoll compliance).
3. `codes/contracts/scripts/deploy.ts` — deploy impl + `registerModule("quadratic-vote", …)`,
   add `QUADRATIC_VOTING_IMPL` to the persisted address entry.
4. `codes/contracts/scripts/copyAbis.ts` + `codes/mobile/assets/abi/ZkQuadraticVoting.json`
   — ABI export. The Flutter app keeps its own committed copy under
   `codes/mobile/assets/abi/`; `pubspec.yaml` globs `assets/abi/` as a directory,
   so no pubspec change is needed.
5. `codes/relayer/` — `validateQuadraticVoteRequest` + `relayQuadraticVote` +
   `POST /api/relay/quadratic-vote`, mirroring the approval/ranked relay paths.
   The existing `/vote`, `/approval-vote`, and `/ranked-vote` paths are
   untouched. The relayer does **not** reimplement the quadratic budget — the
   contract owns it; the relayer only checks `packedAlloc ∈ [1, 2^32)`,
   `message == String(packedAlloc)`, and `scope == BigInt(pollAddress).toString()`.

## Out of scope (follow-up PR)

- The Flutter UI: a credit-allocation ballot screen (per-option steppers, a live
  `spent = Σ vᵢ²` / `remaining` budget meter that disables increments once they
  would exceed `CREDITS`), results rendering (the authoritative per-option vote
  sums), and the create-poll dispatch on `?module=quadratic-vote`.
- Per-voter / token-weighted budgets (needs a custom circuit; see "Why a UNIFORM
  budget" above).
