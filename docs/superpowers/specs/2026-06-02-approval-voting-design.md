# Phase 12a — Approval Voting (bitmask-ballot module)

Status: backend slice (contract + relayer). Flutter UI is a follow-up PR.
Date: 2026-06-02
Module string (canonical): `approval-vote`

## Summary

Approval voting lets a voter approve **any number** of options in a single
ballot (zero-or-more, not exactly-one). It is a sibling of M1 `ZkAnonVoting`:
same Semaphore membership / registration / nullifier model and the same
relayer-submitted anonymity. The only behavioral difference is the ballot:
instead of a single option index, the voter submits a **bitmask** that encodes
the set of approved options, and the tally increments **every** approved option.

The new contract is `ZkApprovalVoting` (call it M3 for bookkeeping; it is a
structural copy of M1). It is cloned + initialized through the existing
`PollRegistry` exactly like M1/M2.

## Bitmask-in-message encoding

A ballot is a single `uint256 bitmask`. Bit `i` (counting from LSB) set means
"option `i` is approved":

```
bitmask = Σ over approved options i of (1 << i)
```

Examples (a 3-option poll [A, B, C]):

| bitmask (dec) | binary | approves   |
|---------------|--------|------------|
| 1             | 001    | A          |
| 2             | 010    | B          |
| 5             | 101    | A and C    |
| 7             | 111    | A, B, C    |
| 0             | 000    | (rejected) |

The bitmask is bound into the Semaphore proof as the `message` field
(`proof.message == bitmask`), exactly the way M1 binds the option index into
`message`. This makes the ballot non-malleable: the relayer (or anyone) cannot
change which options were approved without invalidating the proof, because the
SNARK signs over `message`.

The web prover (`codes/mobile/web_prover/entry.js`) already passes the vote
signal through `generateProof(id, group, Number(message), scope)`. The bitmask
flows through that same `message` parameter unchanged — no prover change is
needed for approval ballots; the caller simply passes the bitmask as the
message.

## Validation rules (contract `castVote(bitmask, proof)`)

All checks below run, **in this order, BEFORE the nullifier is marked used**, so
a rejected ballot never locks a voter out (they can retry with a valid ballot
using the same identity / same nullifier):

1. `state == Voting`                                 → else `NotInVoting`
2. `bitmask != 0`                                    → else `EmptyBallot`   (no empty ballot)
3. `bitmask < (1 << options.length)`                 → else `InvalidBallot` (no out-of-range bits)
4. `!isNullifierUsed[proof.nullifier]`               → else `AlreadyVoted`
5. `proof.scope == uint256(uint160(address(this)))`  → else `InvalidScope`
6. `proof.message == bitmask`                         → else `TamperedVoteSignal` (bind ballot to proof)
7. `semaphore.verifyProof(groupId, proof)`           → else `InvalidProof`

Only after all seven pass:

```solidity
isNullifierUsed[proof.nullifier] = true;
for (uint i = 0; i < options.length; i++)
    if ((bitmask >> i) & 1 == 1) voteCounts[i]++;
emit VoteCast(bitmask);
```

The per-option `voteCounts` are **approvals**, not exclusive votes — so the sum
of `getResults()` can exceed the participant/voter count (a voter who approves
3 options adds 3 to the total). This is by design and is asserted in the tests.

## The 32-option cap and WHY

`uint256 public constant MAX_OPTIONS = 32;` — `initialize` reverts
(`TooManyOptions`) if `options.length > MAX_OPTIONS`.

Why 32 specifically: the off-chain prover bridge does `Number(message)` in
`codes/mobile/web_prover/entry.js`. A JS `Number` is an IEEE-754 double with 53
bits of integer precision, so a bitmask stays exact well past 32 bits (up to 53
options would still round-trip safely). 32 is therefore a **conservative sanity /
UI cap**, not a correctness boundary: it keeps ballots to a single comfortable
32-bit word, keeps the approval-checkbox UI manageable, and leaves a wide margin
under the `Number()` precision limit. The on-chain `bitmask` itself is a full
`uint256`; the cap is purely a guardrail on `options.length`.

## Privacy model

Same as M1 `ZkAnonVoting`:

- The **voter is anonymous**: Semaphore proves membership in the registered
  group and produces a one-time nullifier, without revealing which member
  voted. Submission is relayer-mediated so the voter's wallet/IP isn't linked.
- The **ballot content is PUBLIC on-chain**: the bitmask is emitted in
  `VoteCast(bitmask)` and the per-option approvals are readable via
  `getResults()`. This is identical to M1, where the chosen option index is
  public. Approval voting does NOT hide *what* was approved, only *who* approved
  it.

If ballot-content privacy is ever required, that is a different module (closer
to M2's commit-reveal), not this one.

## HONESTY BAR

Local Hardhat tests run against `MockSemaphoreVerifier`, whose `verifyProof`
**always returns `true`**. So the test suite proves the **tally and validation
LOGIC** — bitmask decoding, range/empty checks, nullifier single-use,
scope/message binding, the no-lockout retry, and the per-option approval counts
— but it does **NOT** prove real SNARK validity. This is exactly the same
honesty bound as M1 `ZkAnonVoting`. Real Groth16 verification is gated behind
`USE_REAL_VERIFIER` (see P4-23/P4-24) and is out of scope for this slice.

## Canonical module string: `approval-vote`

The repo already has an inconsistency for M1 (`anon-vote` in `deploy.ts` vs
`zk-anon-voting` in the test harness). We do **not** repeat that here. The
string `approval-vote` is used **identically** in:

- `scripts/deploy.ts` — `registerModule("approval-vote", impl)`
- `test/ZkApprovalVoting.test.ts` — `registerModule`/`createPoll`
- the relayer (where applicable)
- and is the canonical string the Flutter UI follow-up PR MUST reuse — the
  create-poll flow dispatches `?module=approval-vote` and renders an approval
  (multi-select checkbox) screen.

## Layers in this PR

1. `codes/contracts/contracts/ZkApprovalVoting.sol` — the module (copy of M1
   structure; `MAX_OPTIONS`, `castVote(bitmask, proof)`).
2. `codes/contracts/test/ZkApprovalVoting.test.ts` — clone-deploy harness
   against `MockSemaphoreVerifier`.
3. `codes/contracts/scripts/deploy.ts` — deploy impl + `registerModule("approval-vote", …)`.
4. `codes/contracts/scripts/copyAbis.ts` + `codes/mobile/assets/abi/ZkApprovalVoting.json`
   — ABI export. `pubspec.yaml` globs `assets/abi/` as a directory, so no
   pubspec change is needed.
5. `codes/relayer/` — `validateApprovalVoteRequest` + `relayApprovalVote` +
   `POST /api/relay/approval-vote`, mirroring the anon-vote relay path. The
   existing anon-vote path is untouched.

## Out of scope (follow-up PR)

The Flutter UI: an approval-ballot screen (multi-select checkboxes → bitmask),
results rendering of per-option approvals, and the create-poll dispatch on
`?module=approval-vote`.
