# Module: Multi-question Survey Voting (ZkSurveyVoting)

> Phase 12d. Design spec: [`docs/superpowers/specs/2026-06-03-survey-voting-design.md`](../superpowers/specs/2026-06-03-survey-voting-design.md)
> (the architecture below realizes that spec — Decision A1 "one survey contract,
> one ballot, one nullifier" + Decision B1 "`message = keccak256(abi.encode(answers)) >> 8`").

## Privacy Dimensions
- **Identity:** anonymous (Semaphore ZK proof, no address link — same as M1)
- **Content:** public-aggregate (the full answer vector is on-chain; per-question
  tallies are live — the survey hides *who* answered, not *what*)
- **Temporality:** immediate

> The survey generalizes M1 "one poll = one question" to "one survey = an ordered
> **list** of questions" while keeping the anonymity model identical: **one
> ballot, one Semaphore proof, one nullifier per voter per survey** ⇒ one
> submission per voter covering every question. Answering question-by-question
> leaks nothing — the ballot is atomic.

## How It Works

A **survey** is an ordered `Question[]`. Each question has a **type** and its
**own** option list and **own** tally. v1 question types:

- **single-choice** — pick exactly one option (the M1 encoding: an option index).
- **multi-select** — approve any non-empty subset (the M3 encoding: a bitmask,
  bit *i* ⇒ option *i*).

1. **Creation:** A creator initializes the survey clone with the ordered question
   list. Per-question options live on-chain (consistency with every shipped
   module; survey sizes are modest).

2. **Registration:** Admin registers voter identity commitments into the
   survey's Semaphore group (identical to M1).

3. **Voting:** The voter assembles the **full answer vector** (one word per
   question, in order), computes the ballot commitment
   `message = keccak256(abi.encode(answers)) >> 8` locally, generates **one** ZK
   proof binding that `message`, and submits `castVote(answers, proof)` — the
   answer vector travels in calldata, the proof binds it.

4. **Verification & tally:** The contract recomputes the commitment from
   calldata, requires `proof.message ==` it (non-malleable), verifies the
   Semaphore membership proof, checks the nullifier is fresh, then folds each
   answer into its question's per-option tally.

5. **Results:** Per-question tallies are read via `getSurveyResults()` (one inner
   array per question). The Flutter side renders **N `ResultsBars`** — one per
   question.

## The question model

```solidity
enum QType { SingleChoice, MultiSelect }   // v1; extend (Rating, Ranked, Quadratic) later

struct Question {
    QType qType;
    string[] options;        // this question's own option labels (on-chain, v1)
    // tally held separately in voteCounts[q][option] (a mapping can't live in a
    // memory-returned struct)
}
```

The survey is an ordered `Question[]`, fixed at `initialize()`. The encoding is
deliberately **extensible** to rating / ranked / quadratic per-question types
later — each is already a single ≤32-bit word in the shipped modules, so it slots
into the same `uint256[]` answer vector with no change to the commitment scheme;
only the per-question validation switch (`_validateAnswer`) grows. **v1 ships
single-choice + multi-select only.**

## The hash-commitment ballot

The ballot is bound to the proof by a **hash commitment**. The client serializes
the whole answer vector and computes:

```
message = keccak256(abi.encode(uint256[] answers)) >> 8
```

The answer vector is a flat `uint256[] answers`, one word per question, in
question order. For each question `q`, `answers[q]` reuses that question's type
encoding: a **single-choice** answer is the chosen **option index**; a
**multi-select** answer is a **bitmask** (bit *i* set ⇒ option *i* approved).

The serialization is **canonical `abi.encode`**, NOT `abi.encodePacked`:

```
abi.encode(uint256[] answers) =
    [ 0x20 ]                  // 32-byte offset to the array data
    [ answers.length = n ]    // 32-byte length
    [ answers[0] ]…[ answers[n-1] ]   // n × 32-byte big-endian words
```

i.e. `32 * (2 + n)` bytes. The `>> 8` drops the low byte of the 256-bit keccak
digest, yielding a 248-bit value that is **always** `< BN254 r`, so the
commitment is always a valid in-field Semaphore signal — byte-identical to
Semaphore's bundled `hash()` helper, except the survey hashes the abi-encoded
**byte string** of the whole vector, not a single numeric message.

The full answer vector travels in **calldata**; the contract **recomputes**
`uint256(keccak256(abi.encode(answers))) >> 8` on-chain (`ZkSurveyVoting.sol`
`castVote` check 4) and requires `proof.message == recomputed`. This is
non-malleable — nobody, not even the relayer, can re-weight an answer without
invalidating the SNARK.

### The serialization is the load-bearing cross-impl detail (Gate 2)

The client (Dart on mobile, JS on web/desktop) computes `message` **before**
proving; the contract recomputes it from calldata. If the client's byte
serialization does not match Solidity's `keccak256(abi.encode(...))` **exactly**,
`proof.message != recomputed` and **every survey cast reverts**
(`TamperedVoteSignal`). The cross-impl match is therefore pinned by a fixed-vector
test that asserts **Dart-keccak ≡ JS-keccak ≡ Solidity `keccak256(abi.encode(...))`**
for the worked vector `answers = [2, 5]` (and single-choice-only, multi-select,
mixed, and boundary vectors). The trap: `blind_commit.dart` proves keccak parity
is achievable in Dart but uses `abi.encodePacked` (the **wrong** layout); the
survey encoder reproduces `abi.encode`'s offset+length+word header.

## Contract: ZkSurveyVoting.sol

### State Machine
```
Registration ──startVoting()──> Voting ──endVoting()──> Ended
     │                            │
     ├── registerVoter() (owner)  └── castVote() (anyone, one ballot/voter)
     ├── registerVoters() (owner)
     └── startVoting() (owner)
```

### Initialization (Minimal Proxy Pattern)
```solidity
function initialize(
    address _semaphoreAddress,
    address _owner,
    bytes calldata initData,   // abi.encode((QType qType, string[] options)[])
    uint8 _resultsPolicy          // R4: 0 = sealed-until-close (default), 1 = live-public
) external initializer
```
`initData` decodes into the ordered `Question[]` and is validated: **≥1 question**
(else `NoQuestions`) and **≤ MAX_QUESTIONS** (else `TooManyQuestions`); each
question **≥2 options** (else `NeedAtLeastTwoOptions`) and **≤ MAX_OPTIONS** (else
`TooManyOptions`). `initialize()` (not a constructor) + `_disableInitializers()`
in the real constructor make the bare implementation un-initializable — only
EIP-1167 clones produced by `PollRegistry` are usable. Through the registry clone
path these init reverts surface as `PollRegistry.InitFailed`.

- **`MAX_OPTIONS` per question = 32** — matches M3's approval cap; a multi-select
  bitmask over ≤32 options fits one word, and `1 << optionCount` never overflows.
- **`MAX_QUESTIONS` per survey = 16** — bounds `castVote` gas. The worst case
  (first voter, 16 multi-select questions × 32 options, full-width mask) is
  ≈512 fresh SSTOREs ≈ ~12M gas (≈40% of a 30M block), with headroom; 32 questions
  would approach the block limit, so 16 is chosen.

### Validation & no-lockout discipline

`castVote(uint256[] calldata answers, ISemaphore.SemaphoreProof calldata proof)`
runs all reject-checks **in order, BEFORE the nullifier is marked used**, so a
rejected ballot never locks a voter out (they retry with a valid ballot using the
same identity / nullifier — the identical discipline of M1/M2/M3/QV):

1. `state == Voting` → else `NotInVoting`
2. `answers.length == questions.length` → else `WrongQuestionCount`
3. **Per-question validation** (`_validateAnswer(q, answers[q])`):
   - **single-choice:** `answers[q] < options.length` → else `InvalidAnswer`
     (out-of-range index)
   - **multi-select:** `answers[q] != 0` (non-empty) **and**
     `answers[q] < (1 << options.length)` (no out-of-range/high bits) → else
     `InvalidAnswer` (mirrors M3's high-bit guard + no-empty rule)
4. **Commitment recompute:** `uint256(keccak256(abi.encode(answers))) >> 8 ==
   proof.message` → else `TamperedVoteSignal`
5. `!isNullifierUsed[proof.nullifier]` → else `AlreadyVoted`
6. `proof.scope == uint256(uint160(address(this)))` → else `InvalidScope`
7. `semaphore.verifyProof(groupId, proof)` → else `InvalidProof`

Only then is the nullifier consumed and the per-question tally folded:
single-choice increments exactly one option (`voteCounts[q][answers[q]]++`);
multi-select increments **every set bit** of the mask. `SurveyVoteCast(answers)`
emits the full ballot on-chain (the answer content is public — auditability).

> **Every question is mandatory** (a call this module makes): `answers.length ==
> questions.length` and each `answers[q]` must be a valid non-empty answer. There
> is no "no answer" sentinel in v1 — a future "Abstain" can be modelled as an
> explicit per-question option without changing the encoding.

### Per-question results without changing `IZkPoll` (Gate 3)

`IZkPoll.getResults() → uint256[]` is **flat / single-question** and is shared by
every module. `IZkPoll` is **frozen** — the survey does **not** touch it. Instead
it exposes per-question results through survey-specific views and implements the
flat interface only for compliance:

| Function | Returns |
|---|---|
| `getQuestionCount()` | number of questions |
| `getQuestionResults(q)` | question `q`'s `[option] => count` |
| `getSurveyResults()` | the full `[q][option] => count` (the authoritative surface) |
| `getQuestionOptions(q)` | question `q`'s labels |
| `getQuestionType(q)` | question `q`'s `QType` |
| `getResults()` | **documented degenerate** — question 0's tally (IZkPoll compat) |
| `getOptions()` | **documented degenerate** — question 0's labels (IZkPoll compat) |

`getResults()`/`getOptions()` return **question 0**'s tally/labels — a deliberate,
stated degenerate so a generic `IZkPoll` consumer (e.g. the registry's flat reads)
never reverts, while the **authoritative survey surface is `getSurveyResults()` /
`getQuestionResults(q)`**. No existing module's interface or read surface changes.

### Key Functions

| Function | Access | Phase | Description |
|----------|--------|-------|-------------|
| `initialize()` | Once only | -- | Decode + validate `Question[]`, create the Semaphore group |
| `registerVoter()` | Owner | Registration | Add one identity commitment |
| `registerVoters()` | Owner | Registration | Batch register commitments |
| `startVoting()` | Owner | Registration | Transition to Voting (requires ≥1 voter) |
| `endVoting()` | Owner | Voting | Transition to Ended |
| `castVote(answers, proof)` | Anyone | Voting | One hash-commitment survey ballot |
| `getState()` | Anyone | Any | Current lifecycle state |
| `getSurveyResults()` | Anyone | Any | Full per-question `[q][option]` tallies |
| `getQuestionResults(q)` / `getQuestionOptions(q)` / `getQuestionType(q)` | Anyone | Any | Per-question views |
| `getResults()` / `getOptions()` | Anyone | Any | IZkPoll-compat question-0 degenerate |
| `getParticipantCount()` | Anyone | Any | Number of registered voters |
| `verifyParticipation()` | Anyone | Any | Check if nullifier was used |

### Security Properties
- **Anonymity:** Semaphore proves group membership and emits **one nullifier per
  survey** (scope = survey address) without revealing who voted; relayer-mediated
  submission keeps the voter's wallet/IP unlinked. One nullifier per voter per
  survey ⇒ one atomic submission covering all questions.
- **Double-vote prevention:** each nullifier can only be used once.
- **Scope binding:** `proof.scope == uint256(uint160(address(this)))` prevents
  replay across polls/surveys.
- **Ballot integrity (non-malleable):** `proof.message == keccak256(abi.encode(
  answers)) >> 8` binds the **entire** answer vector to the SNARK — no single
  answer can be altered without invalidating the proof.
- **No lockout:** every reject-check precedes the nullifier write, so a malformed
  or tampered ballot is always retryable with the same identity.

### Prover-widening note (the wide-message path)

The survey commitment is a **full field-element `message`** that cannot survive
`Number(message)`. The shared web prover was widened
`Number(message) → BigInt(message)` (`codes/mobile/web_prover/entry.js`),
re-bundled, and re-synced into `assets/zk/zkprover.js` (the
`zkprover_bundle_parity_test` sha256-guards byte-identity). The `message` travels
as a **decimal string** end-to-end (no `int.parse` narrowing on the Dart side).
This widening was regression-verified against all four shipped SNARK-message
modules (anon / approval / ranked / quadratic) — their real-vkey proofs still
verify and their contracts still accept. `ZkBlindVoting` is commit-reveal (no
`message` signal) and is unaffected.

### Known Limitations
- Admin must register voters (centralized registration — same as M1).
- Small-group deanonymization: per-question answer sets are public, so a tiny
  group can be deanonymized by elimination (same bound as M1).
- Per-question **ranked / quadratic** answer types are out of scope for v1 (the
  encoding hosts them; only the validation switch grows).
- Questions/options are fixed at `initialize()` (no post-creation edit).
- `MockSemaphoreVerifier` used in local tests — real Groth16 verifier required
  for production (see honesty bound below).

## Honesty bound (verified vs fenced)

The survey is **verified** at four layers; the on-device mobile UI cast is the
same **device-gated / fenced** bound as every other module's on-device proving.

| Layer | What is verified | Against |
|---|---|---|
| **Contract** | serialization / commitment-recompute / per-question validation + tally / nullifier single-use / scope+message binding / no-lockout retry / `SurveyVoteCast` emission | hardhat suite (45 tests) vs `MockSemaphoreVerifier` |
| **Relayer** | survey-vote request validation — wide non-zero commitment `message`, `scope == pollAddress`, answer-array shape/range, proof shape; does NOT recompute the commitment (the contract owns that) | relayer survey-validation tests (14) |
| **Dart crypto** | `surveyCommitment` (`abi.encode(uint256[]) >> 8`) ≡ ethers/Solidity; init-encoding `(uint8,string[])[]` ≡ ethers `abi.encode` | `survey_commit_test` (8, Gate 2 cross-impl) + `survey_init_encoding_test` (2) |
| **Stack e2e** | real `createPoll("survey-vote", …)` → `registerVoter` → `castVote([2,5])` → `getSurveyResults()` non-empty per-question tallies, on a local Hardhat chain (no emulator, no Flutter) | `scripts/demo-poll.ts` survey seed |

> **Honesty bar.** The contract suite and the stack-e2e seed run against
> `MockSemaphoreVerifier`, whose `verifyProof` always returns `true` (Semaphore's
> merkle-root membership check still runs — the seed reconstructs the group root
> off-chain). So they prove the **serialization / commitment-recompute /
> per-question tally / validation LOGIC** — NOT real SNARK validity. This is the
> identical honesty bound as M1/M2/M3/QV; real Groth16 verification is gated
> behind `USE_REAL_VERIFIER` (P4-23/P4-24). The **cross-impl serialization** (the
> one thing that, if wrong, bricks every cast) is proven independent of the mock
> by the Dart ≡ JS ≡ Solidity fixed-vector test.

### Fenced (device-gated, not a regression risk)

The **on-device mobile UI survey cast** (answer → WebView-prove → relay) is the
same device-gated path as every other module's on-device proving: it cannot be
verified on a headless CI box and is a **named follow-up gate**, not a regression
risk. The **verified** cast paths are paste / desktop sidecar / web. A real-device
survey cast (browse → survey detail → answer → prove → relay → per-question
results) is the outstanding device-only verification, consistent with the
"Mobile WebView prover" row in `docs/project/TEST-COVERAGE.md`.
