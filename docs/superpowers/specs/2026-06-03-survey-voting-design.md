# Phase 12d — Multi-question Survey ("Google-Forms") Voting (hash-commitment module)

Status: full-stack plan (contract + relayer + Flutter read/results + create UI).
Sequenced behind a shared-prover regression gate (see M1).
Date: 2026-06-03
Module string (canonical): `survey-vote`

> This spec builds directly on the read-only research brief
> `docs/superpowers/research/2026-06-03-survey-data-model-research.md` (the
> current-model map with file:line cites, the approach comparison, the prior-art
> survey, and the `message`-field analysis). Read that first; this document turns
> its labelled recommendation (Approach 4: one survey contract, one ballot, one
> nullifier, `message = keccak256(answer vector) >> 8`) into an implementable
> plan. The design is **already decided** — this spec specifies it rigorously, it
> does not re-decide it.

---

## Decisions & alternatives (read this first)

Two forks from the research are settled here. Each is a crisp either/or with the
chosen option marked, so a human reviewer can cheaply redirect the whole plan by
flipping a single decision before any code is written.

### Decision A — Data-model topology

> **One survey contract / one ballot / one nullifier (CHOSEN)** vs.
> orchestrator-over-N-child-clones vs. N independent polls.

| Option | What it is | Trade-offs |
|---|---|---|
| **A1 — one `ZkSurveyVoting`, one ballot, one nullifier (CHOSEN)** | A single cloned module holds an ordered `Question[]` (each: type + own options + own tally) and one nullifier set per survey. The voter submits **one** Semaphore proof whose `message` binds the **entire** answer vector. | **1 proof, 1 tx, 1 nullifier per voter per survey.** Cleanest anonymity — the ballot is atomic, so answering question-by-question leaks nothing. Best mobile UX (one WASM proving pass). Cost: a genuinely new `castVote`/tally to write (the per-question encodings are reused, but their composition is new). |
| A2 — orchestrator over N child single-question clones | A parent "survey" contract references N children, each a verbatim shipped module (anon / approval / ranked / quadratic). The voter proves **once per child**. | Maximal *contract-code* reuse, but **N nullifiers, N proofs, N txs**; children must share one Semaphore group or membership-set diffs leak linkage; **submission correlation** (one relayer batch / timing window) re-links the voter across questions; partial completion is observable; worst mobile proving UX. Buys little anonymity — answer sets are public either way. |
| A3 — N independent polls | Just create N separate polls; no survey object at all. | No atomic ballot, no "one submission", no survey identity, no per-question grouping. Not a survey; rejected as not meeting the product goal. |

### Decision B — `message` encoding (only bites once A1 is chosen)

> **keccak-commitment (CHOSEN)** vs. bit-pack the whole survey into ≤53 bits.

| Option | What it is | Trade-offs |
|---|---|---|
| **B1 — `message = keccak256(serialize(answers)) >> 8` (CHOSEN)** | The full answer vector travels in **calldata**; the client computes the commitment before proving and binds it to the single Semaphore `message`; the contract **recomputes** it from calldata and requires `proof.message ==` that. | **Any survey size, any mix of question types.** Non-malleable (the SNARK signs over `message`). The **only** touch to already-shipped code is the prover *widening* in M1. keccak (not Poseidon) because the commitment is recomputed **on-chain** via the native `keccak256` opcode, never in-circuit, so Poseidon's in-circuit edge is irrelevant and it would be *more* expensive on-chain (the repo ships only an arity-2 `PoseidonT3` for Semaphore's IMT, no vector-hash primitive). |
| B2 — bit-pack the whole answer vector into ≤53 bits | Pack every question's answer into the low bits of one `Number`-safe `message`; no prover change. | Zero shared-infra change, but **caps the entire survey at ~53 bits** and **cannot express multi-select** (an approval question over *k* options costs *k* bits; a single ranked/QV sub-question already spends ~32 bits). Small-single-choice-survey-only. A real dead-end for "Google-Forms". Rejected. |

### Why the recommendation is close to forced

The product goal — a Google-Forms-style survey whose questions can be
**multi-select** (and, later, ranked / quadratic) — eliminates B2 directly: the
bit-pack budget cannot host even one multi-select-over-many-options question
alongside others. That forces B1, and B1's hash-commitment makes A1 strictly
better than A2: once answers live in public calldata and are committed by one
hash, the orchestrator's N-nullifier machinery buys **no** extra anonymity (the
answer sets are public either way) while costing N proofs, N txs, a shared-group
puzzle, and submission-correlation re-linking. Prior art agrees: MACI hashes a
multi-value ballot into one field element; the NIST CVR model is one atomic
ballot with N independent per-contest tallies. **A1 + B1** is both.

The single residual cost of this recommendation — the shared-prover widening — is
isolated, bounded, and gated (M1 below). If a reviewer wants **zero** change to
shared proving infra, flip Decision B to B2 and accept the small-single-choice-
only ceiling (and drop multi-select from v1). That is the one decision that
re-shapes the plan; everything else follows from A1 + B1.

---

## Summary

`ZkSurveyVoting` is a new IZkPoll module — a sibling of `ZkAnonVoting` (M1),
`ZkApprovalVoting` (M3), `ZkRankedVoting` (M2), and `ZkQuadraticVoting` (QV) —
cloned + initialized through the existing `PollRegistry` exactly like them. It
generalizes "one poll = one question" to "one survey = an **ordered list of
questions**", while keeping the anonymity model identical: **one ballot, one
Semaphore proof, one nullifier per voter per survey** ⇒ one submission per voter
covering all questions.

A **survey** is an ordered `Question[]`. Each question has a **type** and its
**own** option list and **own** tally. **v1 question types:**

- **single-choice** — pick exactly one option (the M1 encoding: an option index).
- **multi-select / approval** — approve any non-empty subset (the M3 encoding: a
  bitmask, bit *i* ⇒ option *i*).

The answer-vector encoding (below) is deliberately **extensible** to
**rating / ranked / quadratic** per-question types later — each is already a
single ≤32-bit word in the shipped modules, so it slots into the same
`uint256[]` answer vector with no change to the commitment scheme. **v1 ships
single-choice + multi-select only**; the other types are out of scope for this
plan (see Out of scope).

The ballot is bound to the proof by a **hash commitment**: the client serializes
the whole answer vector and computes

```
message = keccak256(serialize(answers)) >> 8
```

— exactly the shape of Semaphore's own bundled `hash()` helper (a keccak digest
reduced into the BN254 scalar field by dropping the low byte). The full answer
vector travels in **calldata**; the contract **recomputes**
`keccak256(serialize(answers)) >> 8` on-chain and requires
`proof.message == that`. This is non-malleable (nobody, not even the relayer, can
re-weight an answer without invalidating the SNARK) and supports any survey size
and any mix of question types.

---

## Ballot encoding (hash commitment over a flat answer vector)

### The serialization is THE load-bearing detail (gate #2 lives here)

The client (Dart on mobile, JS on web/desktop) computes `message` **before**
proving; the contract recomputes it from calldata. If the client's byte
serialization does not match Solidity's `keccak256(abi.encode(...))` **exactly**,
`proof.message != recomputed` and **every survey cast reverts**. The
serialization is therefore pinned here, byte-for-byte, and a cross-impl test is
mandated (gate #2 below).

**The answer vector is a flat `uint256[] answers`, one word per question, in
question order.** For each question `q` (0-indexed), `answers[q]` reuses the
existing per-question encoding for that question's type:

| v1 question type | `answers[q]` encoding | Valid range |
|---|---|---|
| single-choice | the chosen **option index** (M1 encoding) | `[0, questions[q].optionCount)` |
| multi-select / approval | a **bitmask**, bit *i* set ⇒ option *i* chosen (M3 encoding) | `(0, 2^optionCount)` — non-empty, no out-of-range bits |

> Forward-compatibility: ranked (packed 4-bit rank slots, M2) and quadratic
> (packed 4-bit alloc slots, QV) are also single ≤32-bit words, so the **same**
> `uint256[]` vector hosts them when those types are added later — only the
> per-question validation switch grows, never the commitment scheme.

**The serialized preimage is `abi.encode(uint256[] answers)`** — NOT
`abi.encodePacked`. `abi.encode` of a dynamic array of a static type is a
deterministic, unambiguous layout:

```
abi.encode(uint256[] answers) =
    [ 0x20                                ]   // 32-byte offset to the array data
    [ answers.length                      ]   // 32-byte length n
    [ answers[0] ]…[ answers[n-1]         ]   // n × 32-byte big-endian words
```

i.e. `32 * (2 + n)` bytes total: a `0x20` offset word, a length word, then the
`n` answer words in order. Then:

```
message = ( BigInt(keccak256(abi.encode(answers))) >> 8 )
```

The `>> 8` drops the low byte of the 256-bit keccak digest, yielding a 248-bit
value that is **always** `< BN254 r` (~2^254), so the commitment is always a
valid in-field Semaphore signal. This is byte-identical to Semaphore's bundled
helper (`@semaphore-protocol/proof` `hash()`:
`(BigInt(keccak256(toBeHex(message, 32))) >> 8n)`) — **except** the survey hashes
the abi-encoded **byte string** of the whole vector, not a single numeric
message. **Implementer warning:** do NOT call `hash(answers[0])` or `hash(n)` —
that hashes one number and is silently wrong. Replicate the `>> 8` reduction over
`keccak256(abi.encode(answers))`.

### Why `abi.encode`, not `abi.encodePacked`

`abi.encodePacked` is ambiguous for dynamic types and omits the length prefix, so
two different vectors could collide and the client/contract layouts are harder to
keep identical. `abi.encode` is canonical, length-prefixed, and trivially
reproducible off-chain (fixed 32-byte words). Note the existing
`codes/mobile/lib/core/crypto/blind_commit.dart` is prior art for **pointycastle
keccak in Dart**, but it uses `abi.encodePacked(uint256, bytes32)` — a **different
layout**. The survey Dart encoder must replicate `abi.encode`'s
offset+length+word header, which is exactly the thing the fixed-vector test
(gate #2) exists to catch.

### Worked fixed vector (the cross-impl test asserts these exact bytes)

Survey with 2 questions: Q0 single-choice over 3 options, Q1 multi-select over 4
options. Voter answers Q0 = option 2, Q1 = options {0, 2} (bitmask `0b0101 = 5`).

```
answers = [ 2, 5 ]                          // uint256[2]

abi.encode(answers) (4 words = 128 bytes, big-endian):
  word 0 (offset): 0x0000…0020
  word 1 (length): 0x0000…0002
  word 2 (a[0]=2): 0x0000…0002
  word 3 (a[1]=5): 0x0000…0005

keccak256(abi.encode(answers)) = K   (a 32-byte digest)
message = BigInt(K) >> 8             (a 248-bit field element, decimal on the wire)
```

The test pins `abi.encode(answers)` (the 128-byte preimage: offset+length+2
words), `keccak256(...)`, and `>> 8`, and asserts **Dart-keccak === JS-keccak ===
Solidity `keccak256(abi.encode(...))`** for this exact vector.

### `message` is non-malleable

The Semaphore SNARK signs over `message`. Binding `proof.message ==
keccak256(abi.encode(answers)) >> 8` means nobody — not the relayer, not any
observer — can alter a single answer without invalidating the proof. This is the
same guarantee M1 gets from `message == optionIndex`, M3 from `message ==
bitmask`, etc., generalized from a ≤32-bit ballot to a wide hash.

---

## Contract: `ZkSurveyVoting`

### Storage & init

`ZkSurveyVoting` is a structural copy of the sibling modules (same Semaphore
membership / registration / nullifier model, `initialize()` not constructor for
EIP-1167 clone compatibility, `_disableInitializers()` in the real constructor).
The single-question `string[] options` + `mapping voteCounts` is replaced by a
nested per-question model:

```solidity
enum QType { SingleChoice, MultiSelect }   // v1; extend (Rating, Ranked, Quadratic) later

struct Question {
    QType qType;
    string[] options;        // this question's own option labels (on-chain, v1)
    // tally is held separately (mappings can't live in a memory-returned struct)
}

Question[] internal questions;                                  // ordered
mapping(uint256 => mapping(uint256 => uint256)) internal voteCounts; // [q][option] => count
mapping(uint256 => bool) public isNullifierUsed;
mapping(uint256 => bool) public registeredCommitments;
uint256 public participantCount;
```

`initialize(address semaphore, address owner, bytes initData)` decodes
`initData` into the question structure (`(QType qType, string[] options)[]`),
validates it (≥1 question; each question ≥2 options and `optionCount ≤
MAX_OPTIONS`), creates the Semaphore group, and stores it. Per-question option
labels live **on-chain in v1** (consistency with every shipped module; survey
sizes are modest — revisit only if gas bites). `MAX_OPTIONS` per question = 32
(matches M3's approval cap; a multi-select bitmask over ≤32 options fits one
word, and `1 << optionCount` never overflows).

### `castVote(uint256[] calldata answers, ISemaphore.SemaphoreProof calldata proof)`

The voter submits the **full answer vector** in calldata plus one proof. All
reject-checks run **in this order, BEFORE the nullifier is marked used**, so a
rejected ballot never locks a voter out (they may retry with a valid ballot using
the same identity / same nullifier). This is the identical no-lockout discipline
of M1/M2/M3/QV.

1. `state == Voting` → else `NotInVoting`
2. `answers.length == questions.length` → else `WrongQuestionCount`
3. **Per-question validation** — for each `q` (`_validateAnswer(q, answers[q])`):
   - **single-choice:** `answers[q] < questions[q].options.length` → else
     `InvalidAnswer` (an out-of-range option index).
   - **multi-select:** `answers[q] != 0` (non-empty) **and** `answers[q] < (1 <<
     questions[q].options.length)` (no out-of-range/high bits set) → else
     `InvalidAnswer`.
4. **Commitment recompute** —
   `recomputed = uint256(keccak256(abi.encode(answers))) >> 8`;
   require `proof.message == recomputed` → else `TamperedVoteSignal`.
5. `!isNullifierUsed[proof.nullifier]` → else `AlreadyVoted`
6. `proof.scope == uint256(uint160(address(this)))` → else `InvalidScope`
7. `semaphore.verifyProof(groupId, proof)` → else `InvalidProof`

Only after all checks pass:

```solidity
isNullifierUsed[proof.nullifier] = true;
for (uint256 q = 0; q < questions.length; q++) {
    if (questions[q].qType == QType.SingleChoice) {
        voteCounts[q][answers[q]]++;                          // one option
    } else { // MultiSelect
        uint256 m = answers[q];
        uint256 n = questions[q].options.length;
        for (uint256 i = 0; i < n; i++) {
            if ((m >> i) & 1 == 1) voteCounts[q][i]++;        // every set bit
        }
    }
}
emit SurveyVoteCast(answers);   // full ballot on-chain for auditability
```

> **Validation discipline mirrors QV's ghost-slot / high-bits rules.** The
> per-question checks reject (a) wrong-length vectors, (b) single-choice indices
> `≥ optionCount`, and (c) multi-select bitmasks with **any** bit at position
> `≥ optionCount` (the `answers[q] < (1 << optionCount)` guard rejects high bits,
> exactly like M3's `bitmask >= (1 << options.length)` check) and the empty
> bitmask. A malformed answer can never be silently ignored, and — critically —
> it reverts **before** the nullifier write, so a bad ballot is always retryable.

### Per-question results without changing `IZkPoll` (gate #3)

`IZkPoll.getResults() → uint256[]` is **flat / single-question** and is shared by
all four existing modules. **Do NOT change `IZkPoll`** (that would touch every
module). `ZkSurveyVoting` exposes per-question tallies through **survey-specific
views** and implements `getResults()` only for interface compliance:

```solidity
// Survey-specific (the real results surface)
function getQuestionCount() external view returns (uint256);
function getQuestionResults(uint256 q) external view returns (uint256[] memory); // [option] => count, for question q
function getSurveyResults() external view returns (uint256[][] memory);          // [q][option] => count
function getQuestionOptions(uint256 q) external view returns (string[] memory);  // question q's labels
function getQuestionType(uint256 q) external view returns (QType);

// IZkPoll compliance (documented degenerate definition)
function getResults() external view returns (uint256[] memory) { return getQuestionResults(0); } // question-0 tally
function getOptions() external view returns (string[] memory) { return getQuestionOptions(0); }  // question-0 labels
```

`getResults()`/`getOptions()` are **documented to return question 0's** tally and
labels — a deliberate, stated degenerate definition so a generic `IZkPoll`
consumer (e.g. the registry's flat reads) never reverts, while the **authoritative
survey surface is `getSurveyResults()` / `getQuestionResults(q)`**. The Flutter
side renders **N `ResultsBars`** — one per question — from `getSurveyResults()`;
`ResultsBars` already renders N independent `(label, count)` groups, so no widget
change is needed.

### Mandatory questions (a call this spec makes — flagged)

The task says "one submission covering all questions" but does not state whether a
voter may **skip** a question. The shipped modules all reject empty ballots. This
spec pins **every question mandatory**: `answers.length == questions.length`
(check 2) and each `answers[q]` must be a valid non-empty answer (check 3 —
single-choice always names one option; multi-select must be a non-empty subset).
There is no "no answer" sentinel in v1. Rationale: it mirrors the other modules'
no-empty-ballot rule, keeps the commitment unambiguous (no optional-vs-zero
encoding question), and a "skip / abstain" affordance can be added later as an
explicit per-question option (e.g. an "Abstain" choice) without changing the
encoding. (See Open calls.)

### Errors

Reuse the sibling error set (`NotInVoting`, `AlreadyVoted`, `InvalidScope`,
`TamperedVoteSignal`, `InvalidProof`, `TooManyOptions`, `NeedAtLeastTwoOptions`,
…) plus survey-local: `WrongQuestionCount`, `InvalidAnswer`, `NoQuestions`.

---

## The THREE de-risking gates (load-bearing)

### Gate 1 — prover widening + 4-module regression (the go/no-go gate)

The hash commitment produces a **full field-element `message`** that **cannot**
survive `Number(message)`. The widening is changing
`codes/mobile/web_prover/entry.js:34` from:

```js
const proof = await generateProof(id, group, Number(message), scope, depth, artifacts)
```

to `BigInt(message)`. **This is NOT a one-line change in this repo** — it ripples
through the whole prover-artifact chain:

```
entry.js  (the source)
  └─ rebuild via vite ──▶ codes/mobile/web/zkprover.js     (the web IIFE bundle)
        └─ re-sync ─────▶ codes/mobile/assets/zk/zkprover.js (the mobile WebView bundle)
              guarded byte-identical by zkprover_bundle_parity_test
        └─ inherited by ─▶ the desktop Node sidecar          (same bundle)
```

`zkprover_bundle_parity_test` (`codes/mobile/test/data/services/
zkprover_bundle_parity_test.dart`) sha256-compares `web/zkprover.js` against
`assets/zk/zkprover.js` and **fails the moment they drift**, so the rebuild MUST
re-copy the fresh vite output into `assets/zk/`. The desktop Node sidecar loads
the same bundle, so it inherits the change automatically.

**The gate, specified precisely — do ALL of this BEFORE any survey-specific code
is written:**

1. Make the `Number(message)` → `BigInt(message)` widening in `entry.js`.
2. Rebuild `web/zkprover.js` (vite) and **re-sync** `assets/zk/zkprover.js`;
   confirm `zkprover_bundle_parity_test` passes (byte-identical).
3. **Regenerate and verify a Groth16 proof for EACH of the four shipped
   message-signal modules — anon (M1), approval (M3), ranked (M2), quadratic
   (QV) — and confirm their on-chain contracts still ACCEPT those proofs.**
4. If **any** existing module's proof changes shape or fails to verify/accept,
   **STOP and re-plan** (fall back to Decision B's bit-pack, with the
   small-single-choice-only ceiling).

**Rationale to keep the gate honest:** `@semaphore-protocol/proof`'s
`generateProof` already `toBigInt`s the message internally (verified:
`generate-proof.d.ts` takes `message: BigNumberish | Uint8Array | string`), so
`Number()` was an **unnecessary narrowing** and the widening is *expected* to be
safe (small-integer ballots round-trip through `BigInt` unchanged). But the spec
**mandates proving it** via this 4-module regression, not asserting it.

> **Scope note — only FOUR modules, not five.** The repo has five voting modules,
> but `ZkBlindVoting` (commit-reveal blind voting) is **not** SNARK-message based:
> it casts via `commitVote(bytes32 commitHash)` / `revealVote(uint256, bytes32)`
> and uses **no Semaphore proof and no `message` signal** at cast time. It does
> **not** route through `entry.js`/`zkGenerateVoteProof`, so the widening cannot
> affect it. The four SNARK-message modules (anon, approval, ranked, quadratic)
> are exactly the ones that pass a `message` through the shared prover, and they
> are exactly the regression set.

### Gate 2 — keccak serialization cross-implementation match (#1 correctness trap)

The client computes `message = keccak256(serialize(answers)) >> 8` before
proving; the contract recomputes it from calldata. **If the client's byte
serialization does not match Solidity's `keccak256(abi.encode(...))` EXACTLY,
every survey cast reverts** (`TamperedVoteSignal`). The spec mandates:

**(a) The exact serialization is pinned** (see "Ballot encoding" above):
`abi.encode(uint256[] answers)` = `[0x20 offset][length n][answers[0]]…
[answers[n-1]]`, each a 32-byte big-endian word; questions in survey order;
single-choice answer = option index; multi-select answer = bitmask (bit *i* ⇒
option *i*); then `>> 8` drops the low byte of the 256-bit keccak digest.

**(b) A fixed-vector cross-impl test is mandatory:** for the worked vector above
(`answers = [2, 5]`), assert

```
Dart-keccak(abi.encode(answers)) >> 8
  === JS-keccak(abi.encode(answers)) >> 8
  === Solidity keccak256(abi.encode(answers)) >> 8
```

all equal the same pinned decimal `message`. Include at least: a single-choice-
only vector, a multi-select vector (non-empty bitmask), a mixed vector, and a
boundary (max option index; full-width bitmask `(1<<optionCount)-1`).

**The specific footgun:** Dart (pointycastle keccak) and JS (ethers keccak)
matching **Solidity's ABI layout** — the 32-byte-word + offset/length header of
`abi.encode` — is the trap. `blind_commit.dart` proves keccak parity is
achievable in Dart, but it uses `abi.encodePacked`, the **wrong** layout for this
commitment; the survey encoder must reproduce `abi.encode`'s header. This test is
the gate that catches a one-byte divergence before it bricks every cast.

### Gate 3 — per-question results without changing `IZkPoll`

Specified in "Per-question results" above. The gate is a **discipline**: `IZkPoll`
is frozen; the survey adds `getQuestionResults(q)` / `getSurveyResults()` /
`getQuestionOptions(q)` and defines `getResults()`/`getOptions()` as a documented
question-0 degenerate for interface compliance. No existing module's interface or
read surface changes; Flutter renders N `ResultsBars` from the survey-specific
views.

---

## Validation & no-lockout discipline (mirrors the other modules)

Every ballot-reject check — malformed answers, out-of-range option, wrong question
count, message mismatch, scope, nullifier, proof — reverts **BEFORE** the
nullifier is marked used (the ordered check list in `castVote` above). A bad
ballot therefore never consumes the nullifier and never locks a voter out: the
voter retries with a valid ballot using the same identity (same nullifier). This
is the identical no-lockout discipline of M1/M2/M3/QV, and the hardhat tests must
prove it on the `WrongQuestionCount`, `InvalidAnswer`, and `TamperedVoteSignal`
paths (cast a bad ballot, assert revert, then cast a good ballot with the same
identity and assert it succeeds).

## Privacy model (same honesty as the other modules)

- The **voter is anonymous:** Semaphore proves membership in the registered group
  and emits **one nullifier per survey** (scope = the survey address) without
  revealing which member voted; relayer-mediated submission keeps the voter's
  wallet/IP unlinked. One nullifier per voter per survey ⇒ **one submission per
  voter** covering all questions (atomic — nothing leaks per-question).
- The **answer content is PUBLIC on-chain:** the full answer vector is in calldata
  and emitted in `SurveyVoteCast(answers)`, and folded into the public
  per-question `voteCounts`. The survey hides *who* answered, not *what* was
  answered — the same bound as every shipped module.

## HONESTY BAR

Local hardhat tests run against `MockSemaphoreVerifier`, whose `verifyProof`
**always returns `true`**. So the suite proves the **serialization / commitment-
recompute / per-question tally / validation LOGIC** — `abi.encode` layout match,
the `keccak256(...) >> 8` recompute equals the bound `message`, per-question
validation (wrong count, out-of-range index, empty/high-bit bitmask), the
per-question tally (single-choice one option, multi-select every set bit),
nullifier single-use, scope/message binding, the no-lockout retry, and the
`SurveyVoteCast` emission — but it does **NOT** prove real SNARK validity.
Identical honesty bound to M1/M2/M3/QV. Real Groth16 verification is gated behind
`USE_REAL_VERIFIER` (P4-23/P4-24). The **cross-impl serialization** is what Gate 2's
fixed-vector test (Dart === JS === Solidity) proves, independent of the mock.

---

## Canonical module string: `survey-vote`

Used **identically** everywhere — we do not repeat M1's
`anon-vote`/`zk-anon-voting` inconsistency:

- `scripts/deploy.ts` — `registerModule("survey-vote", impl)` + persist
  `SURVEY_VOTING_IMPL`.
- `test/ZkSurveyVoting.test.ts` — `registerModule` / `createPoll`.
- the relayer — the `POST /api/relay/survey-vote` route + validator.
- Flutter — the create flow dispatches `?module=survey-vote`; `router.dart`
  routes `?module=survey-vote` to the survey detail screen + view-model.

## Relayer

One new `POST /api/relay/survey-vote` route mirroring the existing
`/vote` / `/approval-vote` / `/ranked-vote` / `/quadratic-vote` paths:
`validateSurveyVoteRequest` + `relaySurveyVote` + the route in `app.ts`. It
**does NOT recompute the survey commitment** — the contract owns that recompute.
The relayer only fast-checks the `message`/`scope` **shape** (`message` is a
non-zero decimal field element, `scope == BigInt(pollAddress).toString()`), loads
the `ZkSurveyVoting` ABI, pre-checks `getState() == Voting` and
`!isNullifierUsed`, and relays `castVote(answers, proofStruct)`. `toProofStruct`
already `BigInt`-izes `message`/`scope`, so the relayer handles a full-width
`message` with no change. **Existing routes are untouched.**

---

## Milestone sequence (build → verify each)

1. **M1 — Prover widening + 4-module regression gate.** Widen
   `entry.js:34` `Number(message)` → `BigInt(message)`; rebuild `web/zkprover.js`
   (vite) + re-sync `assets/zk/zkprover.js` (parity test green); **regenerate +
   verify Groth16 proofs for anon / approval / ranked / quadratic and confirm
   their contracts still ACCEPT**. Also statically audit the Dart proof plumbing
   for any `int`-narrowing parse of `message` (it travels as a decimal string
   end-to-end; confirm nothing does `int.parse` on it). **Go/no-go:** if any
   existing module's proof changes or fails, STOP and fall back to bit-pack.
2. **M2 — `ZkSurveyVoting.sol` + hardhat tests.** Nested question storage;
   `castVote(uint256[] answers, proof)` recomputing `keccak256(abi.encode(answers))
   >> 8` and validating each question by type; per-question tally; `SurveyVoteCast`
   emission. Tests against `MockSemaphoreVerifier`: the **keccak recompute** equals
   the bound message (the fixed cross-impl vector), per-question validation
   (wrong count / out-of-range index / empty + high-bit bitmask), per-question
   tally (single-choice + multi-select), nullifier single-use, no-lockout retries,
   and boundary vectors (max index, full-width bitmask). IZkPoll compliance
   (`getResults()` == question-0).
3. **M3 — ABIs + relayer route.** `copyAbis` + `assets/abi/ZkSurveyVoting.json`;
   `validateSurveyVoteRequest` + `relaySurveyVote` + `POST /api/relay/survey-vote`
   (existing routes untouched); `deploy.ts` register + persist `SURVEY_VOTING_IMPL`.
4. **M4 — Flutter read model + per-question results.** Survey read surface in
   `ChainReader` (`getSurveyResults` / per-question options + types), a survey
   repository aggregating N questions, a survey detail screen rendering **N
   `ResultsBars`** (one per question) from `getSurveyResults()`. The
   **cross-impl serialization test (gate #2)** lands here on the Dart side
   (Dart-keccak(abi.encode) >> 8 === the pinned JS/Solidity value).
5. **M5 — Question-builder create UI.** Add a survey to the create flow: a
   repeating question builder (add question → pick type → add that question's
   options), the `initData` encoding `(QType, options)[]`, and
   `?module=survey-vote` dispatch in `router.dart` + the create screen. (Largest
   new UI surface.)
6. **M6 — e2e + docs.** Browse → survey detail → vote → per-question results
   through the mobile e2e harness; update `ROADMAP` / `STATUS` / `TEST-COVERAGE`.

---

## Out of scope (explicitly)

- **Per-question ranked / quadratic answer types** — the encoding is designed to
  host them (they are single ≤32-bit words in the same `uint256[]`), but v1 ships
  **single-choice + multi-select only**. Ranked/QV per-question are a later
  iteration (each adds a `QType` arm + its validator + its tally + an off-chain
  replay for ranked, per M2).
- **Per-voter / token-weighted answer weighting** — needs a custom circuit (the
  stock Semaphore circuit carries no per-member attribute; same boundary as QV's
  uniform-budget rationale). Out.
- **Editing a survey after creation** — questions/options are fixed at
  `initialize`, like every other module's options.
- **Off-chain question labels** — v1 stores labels on-chain (consistency, modest
  sizes); an off-chain/IPFS variant is a future gas optimization, not v1.

## Open calls flagged for the reviewer

- **Mandatory questions (decided: all mandatory).** v1 requires an answer to every
  question (no skip / abstain sentinel). A future "Abstain" can be modelled as an
  explicit per-question option without touching the encoding. Flip this only if
  the product needs optional questions in v1 (would require an optional-vs-zero
  sentinel in the encoding).
- **`getResults()` degenerate definition (decided: question 0).** Chosen over a
  flattened concatenation because question-0 is unambiguous and never
  mis-aligns option counts across questions; consumers that need the full survey
  read `getSurveyResults()`. Flip to a documented flatten only if a generic
  `IZkPoll` consumer must see all questions at once (none does today).
