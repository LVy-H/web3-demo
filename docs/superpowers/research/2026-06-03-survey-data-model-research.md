# Phase 12d — Multi-question survey ("Google-Forms") — design-research brief

> **Read-only research.** No code, no contract/Dart, no PR. This brief feeds a
> design spec + a human decision on the data-model approach. It maps the current
> single-question model, lays out the architectural forks, surveys prior art,
> states the crux decisions, and gives a clearly-labelled recommendation.
>
> Date: 2026-06-03 · Scope: Phase 12d (largest item in the Phase 12 epic;
> roadmap says it "redefines the poll data model").

---

## 0. TL;DR

- The whole stack is **single-question by construction**: `IZkPoll` returns one
  `options[]` and one flat `results[]`; every module packs **one ballot into the
  single Semaphore `message` signal**; the Flutter read surface, repositories,
  and `ResultsBars` all assume one question.
- A survey = N questions, each of an existing **per-question type** (single-choice
  = M1 index, multi-select = approval bitmask, rating = small int, ranked = M2
  packed slots, quadratic = QV packed-alloc). **The per-question encodings already
  exist** — 12d is mostly *composition*, not new ballot math.
- **The crux is the `message` field.** At the protocol level it is **one BN254
  field element (~254 bits)**. The practical ceiling is **~53 bits**, imposed
  *only* by `Number(message)` at `codes/mobile/web_prover/entry.js:34` — an
  implementation artifact, not a Semaphore limit. **Verified:** the installed
  `@semaphore-protocol/proof@4.14.2` `generateProof` takes
  `message: BigNumberish | Uint8Array | string` and converts via `toBigInt`, so a
  full-field-element message (a hash) is natively supported the moment that one
  `Number→BigInt` cast is widened.
- **Two human decisions** (Part 4): (A) the **data-model fork** — one survey
  contract / one ballot / one nullifier, vs. an orchestrator over N child-poll
  clones; and (B) the **message-encoding fork** — bit-pack the whole answer
  vector into ≤53 bits (no prover change, small surveys only) vs.
  `message = hash(answer vector)` with answers in calldata (any size; **forces the
  one-line `entry.js` widening that touches shared M1/M2/M3/QV proving infra**).
- **Recommendation (labelled, not a unilateral pick):** one survey contract, one
  ballot, one nullifier, **`message = keccak256(answer vector) >> 8`** (reduced to
  the BN254 field — exactly Semaphore's own bundled `hash()` helper; **keccak, not
  Poseidon**, because the commitment is hashed off-chain and **recomputed on-chain**,
  never in-circuit, so Poseidon's only advantage doesn't apply and keccak is the
  cheap native EVM opcode), with **bit-packing as a fallback only if we choose to
  forbid the `entry.js` change**. This is the smallest correct thing that reuses
  the modules and preserves the anonymity model. It is also exactly the shape MACI
  uses (SHA256-packs many values into one field element).

---

## Part 1 — The CURRENT poll data model (end-to-end, with cites)

### 1.1 Contracts

**`IZkPoll` — the single-question chokepoint.**
`codes/contracts/contracts/interfaces/IZkPoll.sol`
- `getResults() → uint256[]` (`:13`) and `getOptions() → string[]` (`:14`) bake in
  **exactly one question**: one option list, one flat tally. There is no notion of
  "question". This interface — not the registry — is what makes the model
  single-question.
- Lifecycle is a single `PollState { Registration, Voting, Ended }` (`:5–9`) plus
  `getState` / `getParticipantCount` / `owner` / `verifyParticipation(nullifierHash)`.

**The module pattern (M1 and its siblings).**
All five voting modules are structural twins. Reading `ZkAnonVoting.sol` (M1) as
the archetype:
- Storage is single-question: `string[] options` (`:36`),
  `mapping(uint256 => uint256) voteCounts` (`:40`), one `groupId` (`:32`), one
  `isNullifierUsed` set (`:38`). `ZkAnonVoting.sol:86–92` (`getResults`) just copies
  `voteCounts[i]` into a flat array sized to `options.length`.
- `initialize(semaphore, owner, string[] initialOptions)` (`:58–73`) — **no
  constructor** (EIP-1167 clone compatibility; `_disableInitializers()` in the real
  constructor at `:50–52`).
- **The `message` binding is the heart of it.** `castVote(uint256 vote, SemaphoreProof proof)`
  (`ZkAnonVoting.sol:164–179`): `proof.scope == uint256(uint160(address(this)))`
  (`:169`, binds the proof to *this poll*); `proof.message == vote` (`:170`, binds
  the proof to *this ballot*); `semaphore.verifyProof(groupId, proof)` (`:172`);
  then `voteCounts[vote]++` (`:176`). **One `message` = one ballot** is the
  invariant the whole epic is built on.

**How the four ballot types already pack structure into the single `message`:**

| Module | File | Ballot in `message` | Tally |
|---|---|---|---|
| M1 anon (single-choice) | `ZkAnonVoting.sol:164–179` | option **index** | `voteCounts[vote]++` |
| Approval (multi-select) | `ZkApprovalVoting.sol:191–212` | **bitmask** (bit *i* = option *i*), `MAX_OPTIONS=32` (`:47`) | every set bit `voteCounts[i]++` (`:207–209`) |
| Ranked (IRV) | `ZkRankedVoting.sol:245–269` | **packed 4-bit rank slots**, `MAX_OPTIONS=8` (`:61`), value = `optionIndex+1` | round-1 first-pref only (`:265–266`); **winner off-chain** by replaying `VoteCast(packedRanking)` (`:268`) |
| Quadratic | `ZkQuadraticVoting.sol:263–288` | **packed 4-bit alloc slots**, `MAX_OPTIONS=8`, `CREDITS=100` (`:62,68`); `vᵢ=(packed>>4i)&0xF` | per-option vote sum (`:283–285`); `getResults()` authoritative |

**The 32-bit / `Number(message)` self-imposed ceiling.** Every module comments
that it keeps the packed value ≤32 bits *specifically* so the web prover's
`Number(message)` round-trips exactly (IEEE-754 double, 53-bit integer precision):
`ZkApprovalVoting.sol:42–47`, `ZkRankedVoting.sol:55–61`, `ZkQuadraticVoting.sol:56–61`.
This is **the single most important fact for 12d** — it is the ceiling a survey
will hit first, and it is an *implementation* ceiling, not a Semaphore one.

**`PollRegistry` — survey-agnostic, reusable as-is.**
`codes/contracts/contracts/PollRegistry.sol`
- `createPoll(moduleType, title, description, initData)` (`:46–74`): clones the
  registered impl via EIP-1167 (`impl.clone()`, `:55`) and calls the clone's
  `initialize` with opaque `initData` (`:58`). It stores only flat metadata
  (`PollInfo { pollAddress, moduleType, title, description, creator, createdAt }`,
  `:17–24`). **The registry never inspects question structure** — `initData` is a
  blob and `moduleType` is a free string. A `"survey"` module drops in with **zero
  registry changes**.

**Inherently single-question in this design:** `IZkPoll.getOptions/getResults`
(one list each), one `voteCounts` map per module, one `message`=one ballot, one
nullifier per poll. **Not** single-question: `PollRegistry` (pure factory), the
Semaphore membership/registration/nullifier machinery (it proves "some member +
one nullifier per scope" — orthogonal to how many questions a ballot answers).

### 1.2 Relayer

`codes/relayer/src/` — one relay route + one validator per module, all identical
in shape:
- Routes: `POST /api/relay/vote | /approval-vote | /ranked-vote | /quadratic-vote`
  (`app.ts:31–171`); each calls a `relay*Vote` in `relay.ts` (`:22,58,98,139`).
- Each `relay*Vote` loads the module ABI, pre-checks `getState()==1`,
  range-checks the ballot, checks `isNullifierUsed`, then submits `castVote(ballot, proofStruct)`.
- The **binding is enforced twice**: validators in `validation.ts` assert
  `proof.message === String(ballot)` and `proof.scope === BigInt(pollAddress)`
  (e.g. `validateApprovalVoteRequest` at `:158–171`; ranked `:230–243`; quadratic
  `:304–315`). `message`/`scope` are decimal strings on the wire; `toProofStruct`
  (`relay.ts:11–20`) `BigInt`-izes them — **so the relayer already handles
  full-width `message` values; only `entry.js` narrows.**

A survey needs **one new route + validator + relay fn** in this exact mold.

### 1.3 Flutter (`codes/mobile/lib/`)

- **`PollInfo`** (`data/models/poll_info.dart:6–33`): mirrors the registry tuple;
  carries `moduleType` — the dispatch key. Survey-agnostic.
- **`ChainReader`** (`data/services/chain_reader.dart`): `getOptions` (`:70–73`)
  and `getResults` (`:76–79`) each return **one flat list** via the `IZkPoll` ABI.
  `getRegisteredCommitments` (`:108–128`) rebuilds the Semaphore group from
  `VoterRegistered` events. A survey extends the read surface (per-question options
  + per-question results, or one flat list + an offsets descriptor).
- **Repositories** (`data/repositories/*_repository.dart`): one per module; they
  fetch a `PollSnapshot` (state, options, results, owner, participantCount). The
  approval repo (`approval_repository.dart:30–57`) literally reuses `ChainReader`
  unchanged because approval's *read* surface == M1's. A survey repo aggregates N
  questions.
- **Router dispatch** (`router.dart:47–101`): `buildPollDetail` switches on
  `?module=` — `blind-vote` / `approval-vote` / `ranked-vote` each route to a
  dedicated screen + view-model; default = M1 anon. The comments stress this MUST
  route correctly or it casts the wrong ballot (`:44–46,69–72`). A survey adds a
  `survey` branch → new screen + view-model. (Note: ranked/quadratic detail
  branches are wired in the relayer/contract but the router only shows
  blind/approval/ranked branches today — quadratic UI is an open follow-up; same
  pattern applies.)
- **`ResultsBars`** (`ui/widgets/results_bars.dart:19–108`): presentational —
  `(label, count)` rows + optional total + strict-leader trophy
  (`highlightLeader`, `:42`, which ranked sets `false`). **Per-question reusable**:
  a survey renders **N `ResultsBars`, one per question**, with no widget change.

### 1.4 Create flow

- **`deploy.ts`** deploys each impl bare + `registerModule("anon-vote"|...)`
  (`:88–145`) and persists impl addresses (`:172–181`). A survey adds one
  deploy+register block + a `SURVEY_VOTING_IMPL` entry.
- **`PollCreator`** (`data/services/poll_creator.dart`): `createAnonPoll` /
  `createApprovalPoll` (`:30–82`) ABI-encode `initialize(semaphore, owner, options)`
  and forward it as `initData` to `PollRegistry.createPoll(moduleType, …)`. The
  two differ *only* in the module string (`:50` vs `:80`). A survey needs a richer
  `initData` (the question/type/options structure).
- **`CreateScreen`** (`ui/features/create/create_screen.dart`): a `_ModuleType`
  enum picker (`:27`) + a flat title/desc/options form. Today it collects **one**
  option list. A survey requires a **repeating question builder** (add question →
  pick type → add that question's options) — the **biggest single new UI surface**
  in 12d.

### 1.5 Reuse-vs-rewrite ledger (the bridge into Part 2)

| Layer | Reused as-is | Extended | New |
|---|---|---|---|
| `PollRegistry` | ✅ entire factory + metadata | — | — |
| `IZkPoll` | events/state/owner/participant/verifyParticipation | `getOptions`/`getResults` (one→many) | per-question read fns *or* flat+offsets |
| Module contract | Semaphore membership / registration / nullifier / no-lockout discipline | — | survey storage + `castVote(answers, proof)` + per-question tally |
| Per-question ballot math | ✅ **all of it** (index / bitmask / packed slots / packed alloc) | — | composition of them |
| Relayer | route/validator/relay *shape*; `toProofStruct` BigInt path | — | one `survey` route+validator+relay fn |
| Web prover | proof generation | **`Number→BigInt` at `entry.js:34`** (only if hash-encoding) | — |
| `ChainReader` | group rebuild, generic reads | `getResults` flat→per-question | — |
| Repositories | the pattern | a survey repo aggregating N questions | — |
| `ResultsBars` | ✅ **per-question, N instances** | — | — |
| Router | `?module=` dispatch | a `survey` branch | survey detail screen + VM |
| Create | deploy/register pattern, `createPoll` plumbing | `initData` shape | repeating **question-builder** UI |

---

## Part 2 — Design approaches

A survey ballot is, in every approach, a **vector of per-question answers** where
each entry uses an *existing* encoding (index / bitmask / small int / packed
slots). The approaches differ in **where the vector lives** and **how the proof
binds to it**.

### Approach 1 — One contract, array of questions, one ballot, one nullifier
A single `ZkSurveyVoting` clone holds `Question[]` (each: type + own options +
own tally) and `nullifier per voter per survey`. The voter submits **one proof**;
the full answer vector is bound to the single `message`.

### Approach 2 — Orchestrator over N child single-question clones
A parent "survey" contract references N children (reuse M1/approval/ranked/QV
per question). The voter proves **once per child** (N nullifiers, N `message`s,
N proofs/txs). Maximizes *contract-code* reuse (children are the shipped modules
verbatim).

### Approach 3 — Off-chain question metadata + on-chain answer commitments
Question structure lives off-chain (IPFS / events / `description` JSON); the chain
stores only per-question tallies (or only answer commitments). `message = hash`
of the answer vector; answers revealed in calldata; contract recomputes.
*(In practice this is a property of Approach 1's encoding, not a separate
contract topology — see the encoding fork.)*

### Approach 4 — Hybrid
Approach 1's single-ballot/single-nullifier topology, with Approach 3's
hash-commitment `message` encoding and off-chain question *labels* (only the
type/optionCount structure needed for validation lives on-chain). **This is the
recommendation** — it is "Approach 1 done with the scalable encoding."

### Comparison table

| Dimension | A1: one contract / one ballot | A2: orchestrator / N children | A3/A4: hash-commitment (on A1's topology) |
|---|---|---|---|
| **Nullifier / anonymity** | **1 nullifier per voter per survey, 1 proof.** Cleanest — identical to today's model. Answering Q-by-Q leaks nothing (atomic). | **N nullifiers** (different scopes ⇒ unlinkable *by nullifier*). **BUT**: (i) children must share the **same Semaphore group** or membership-set diffs leak linkage; (ii) **submission correlation** (one relayer batch / timing window) re-links the voter across questions; (iii) partial completion is observable. | Same as A1 (single ballot/nullifier). Hash hides nothing extra — answers are public in calldata, like every current module. |
| **`message` encoding** | Must fit the **whole vector** in `message`. Bit-pack ⇒ **≤53-bit budget for the entire survey** (see §2.x). Dies on multi-select. | Each child binds its own ballot to its own `message` — **today's encoding works per question, unchanged**. The encoding problem **disappears** (paid for in N proofs). | `message = keccak256(answers) >> 8` (BN254-reduced), answers in calldata, contract recomputes. **Arbitrary survey size.** Non-malleable. **Forces `entry.js` `Number→BigInt`.** (keccak, not Poseidon: recomputed on-chain, not in-circuit.) |
| **Prover change** | **None** if bit-packed. | **None** (per-question is current math). | **One-line widening** at `entry.js:34`, shared by M1/M2/M3/QV ⇒ **must regression-test all four**. (Widening: small ints round-trip through `BigInt` unchanged.) |
| **Proving cost / UX** | **1 SNARK, 1 tx.** Best UX. | **N SNARKs, N txs.** N× WASM proving (heavy on mobile WebView prover) + N relayer round-trips. Worst UX/perf. | **1 SNARK, 1 tx.** Best UX. |
| **Gas / storage** | One clone; one `castVote`; per-question tallies in nested storage. Moderate. | N clones (N× deploy + N× create tx) + parent; N casts. Highest deploy & per-vote gas. | Same as A1 + a hash recompute (cheap). One clone. |
| **Contract count / deploy** | **1 new module.** Drops into `deploy.ts`/registry like 12a–c. | Parent + reuse N child impls; parent must orchestrate group sharing + lifecycle across children. Most moving parts. | **1 new module.** |
| **Results rendering** | N × `ResultsBars` from per-question tallies. Trivial. | N × `ResultsBars`, read from N child addresses. More reads, more failure modes. | N × `ResultsBars`; complex per-question tallies (ranked) follow M2's off-chain `VoteCast`-replay. |
| **Code reuse** | High at every layer *except* the contract's `castVote`/tally (new composition). | **Maximal contract reuse** (children = shipped modules). But parent orchestration + N-proof client flow is genuinely new and not trivial. | Same as A1; plus the strongest "it's just the existing encodings concatenated + hashed" story. |
| **Migration / regression risk to shipped modules** | **Zero** — additive new module; M1/M2/M3/QV untouched. | **Zero to contracts**, but a shared-group requirement may pressure the registration model. | **The only approach that touches shared infra**: the `entry.js` `Number→BigInt` change is used by every existing module's proving path ⇒ **regression-test M1/M2/M3/QV proofs** before/after. Low-risk (widening) but must be proven. |

### 2.x The `message`-field constraint — the crux, made concrete

`message` is **one Semaphore signal = one BN254 field element (~254 bits)** at the
protocol level. The repo voluntarily caps every ballot at **≤32 bits** so
`Number(message)` (`entry.js:34`) stays exact (≤53-bit IEEE-754 integer). So the
encoding fork is:

- **Bit-pack the whole survey into ≤53 bits (no prover change).**
  Budget arithmetic: a single-choice-of-≤8 question = 3 bits ⇒ ~**17 such
  questions** max. But **multi-select eats bits as fast as it has options** (an
  approval question over *k* options = *k* bits), and a single ranked/QV question
  already spends up to 32 bits by itself. So bit-packing only serves **small,
  mostly single-choice surveys** and **cannot host even one multi-select-over-many
  or one ranked/QV sub-question** alongside others. Verdict: a real dead-end for
  "Google-Forms".

- **`message = keccak256(answer vector) >> 8`, answers in calldata, contract
  recomputes & compares (no prover change *except one cast*).** keccak (reduced to
  the BN254 scalar field) — **not** Poseidon: the hash is computed off-chain in JS
  and **recomputed on-chain in Solidity**, never inside the SNARK circuit (we use
  the stock Semaphore circuit, no custom artifacts), so Poseidon's only edge
  (in-circuit cost) never applies; on the EVM keccak is a cheap native opcode while
  Poseidon-in-Solidity is expensive and the repo ships only an arity-2 `PoseidonT3`
  (Semaphore IMT nodes), with no vector-hash primitive. This is exactly Semaphore's
  own bundled `hash()` helper (*"a keccak256 hash of a message compatible with the
  SNARK scalar modulus"*) and the same shape as MACI's SHA256 `packedVals`.
  Arbitrary number/size of questions and types; non-malleable (the SNARK signs over
  `message`, so neither relayer nor anyone can re-weight answers without
  invalidating the proof — same guarantee M1/M3 get from `message==ballot`). The
  hash output is a **full field element** that **cannot survive `Number(message)`**.
  **This is the one change that touches already-shipped modules:** widening
  `entry.js:34` `Number(message)` → `BigInt(message)` is used by M1/M2/M3/QV's
  proving path. **Verified load-bearing fact:** `@semaphore-protocol/proof@4.14.2`
  `generateProof(message: BigNumberish | Uint8Array | string, …)` internally
  `toBigInt`s the message
  (`codes/mobile/web_prover/node_modules/@semaphore-protocol/proof/dist/types/generate-proof.d.ts:27`,
  `…/to-bigint.d.ts:7`), so a full-width hash message is **natively supported** the
  moment the cast is widened. The change is *widening* (small integer ballots
  round-trip through `BigInt` unchanged), so the regression surface is bounded —
  but it **must** be re-run against all four existing modules' proofs.

**A2 sidesteps the fork entirely** (each question keeps its own ≤32-bit `message`),
trading the encoding problem for N proofs + the linkage/orchestration costs above.

---

## Part 3 — Prior art (each lensed on single-signal binding)

1. **MACI (PSE) — the direct precedent.** A MACI "command" bundles
   `(pubkey, voteOptionIndex, voteAmount, …)`, is signed, encrypted into a
   "message", and submitted to a single coordinator. Crucially, to save
   verification gas MACI **hashes multiple values with SHA256 into a single field
   element (`packedVals`)** and uses that hash as the bound signal; a field element
   is ~253 bits. **Implication:** the canonical ZK-voting system **already commits
   a multi-value ballot to one field element by hashing it** — this *is* our
   recommended A4 encoding, validated in production. It confirms the hash-commitment
   path is the standard answer to "many answers, one signal," and that ~253 bits
   (not 53) is the real field-element budget.
   ([maci.pse.dev primitives/circuits](https://maci.pse.dev/docs/v1.2/primitives))

2. **Snapshot — per-type choice encoding (the per-question type catalog).** One
   proposal = one question, but Snapshot's **voting types map 1:1 onto our
   per-question types**: single-choice = a 1-based index; approval = an **array of
   indices**; weighted = **per-option fractions** (a map); ranked-choice = an
   **ordered array**; quadratic = quadratic tally. **Implication:** a survey
   question's answer is exactly one Snapshot-style encoding; a survey ballot is a
   **vector of these**. Snapshot binds the whole `vote` payload with one signature
   over the JSON — the off-chain analogue of "one `message` commits the vector."
   ([docs.snapshot.box voting-types](https://docs.snapshot.box/proposals/voting-types))

3. **Real-world "multiple contests on one ballot."** A physical ballot routinely
   carries president + senate + several measures; **each contest is defined and
   tallied independently**, but they live on **one sheet cast in one act** (one
   voter, one envelope). The US NIST **Cast Vote Record (CVR)** common data format
   models exactly this: a CVR is one ballot containing many `CVRContest` entries,
   each with its own selections. **Implication:** the established model is **one
   atomic ballot, N independent per-contest tallies** — precisely A1's
   one-ballot/one-nullifier topology with per-question `voteCounts`. It argues
   *against* A2's "N separate ballots."
   ([NIST SP 1500-103 CVR CDF](https://www.govinfo.gov/content/pkg/GOVPUB-C13-5ece0a87c83a2a7d2ba2072e7420c584/pdf/GOVPUB-C13-5ece0a87c83a2a7d2ba2072e7420c584.pdf))

4. **Commit-a-hash / reveal-in-calldata (generic).** A widely used pattern: commit
   `H(payload)` on-chain as the bound value, submit the full `payload` in calldata,
   contract recomputes `H` and checks equality. Our existing modules are a
   degenerate case (`message == ballot` *is* the trivial commitment for ≤32-bit
   ballots). **Implication:** generalizing to `message == hash(answer vector)` is a
   **continuous extension of what M1/M3/M2/QV already do** — same non-malleability
   property, just a wider committed value. It is the minimal conceptual leap.

5. **Vector / Merkle commitments (for very large surveys).** If answers were ever
   too large even for calldata, the standard escalation is a **Merkle root (or
   vector commitment) of per-question answers** as the `message`, revealing
   individual answers with inclusion proofs. **Implication:** unnecessary for
   realistic survey sizes (calldata easily holds tens of small answers), but it is
   the clean scaling path if a future survey needs lazy/partial answer reveal — and
   it reuses the *same* "hash → one field element → one signal" shape.

**Net:** every relevant system that puts many answers behind one signal **hashes
the answer vector into one field element** (MACI explicitly; the generic
commit-reveal pattern; Merkle for scale), and every real multi-question ballot is
**one atomic cast with N independent tallies** (NIST CVR). Both point at
**A1-topology + hash-commitment encoding (= A4)**.

---

## Part 4 — Deliverable: crux decisions, recommendation, milestones

### The two crux decisions (each a crisp either/or)

**Decision A — Data-model topology.**
> **One survey contract, one ballot, one nullifier (A1/A4)** *vs.* **an
> orchestrator over N child single-question clones (A2).**
>
> - A1/A4 ⇒ 1 proof, 1 tx, 1 nullifier; cleanest anonymity (atomic ballot, nothing
>   leaks per-question); a genuinely new `castVote`/tally to write.
> - A2 ⇒ maximal *contract-code* reuse (children = shipped modules verbatim), but
>   **N nullifiers, N proofs, N txs**, a **shared-group requirement** (or membership
>   diffs leak linkage), **submission-correlation** re-linking, and the worst mobile
>   proving UX.
>
> **The tension the roadmap's scoping creates:** "reuse existing modules" pulls
> toward A2; "preserve the anonymity model + usable UX" pulls toward A1. They point
> opposite ways. Prior art (NIST CVR, MACI) and the mobile WebView prover's cost
> both favor **A1**.

**Decision B — `message` encoding (only bites if A1/A4 is chosen).**
> **Bit-pack the whole answer vector into ≤53 bits (no prover change)** *vs.*
> **`message = keccak256(answer vector) >> 8`, answers in calldata, contract
> recomputes (forces a one-line `entry.js` `Number→BigInt` widening shared across
> M1/M2/M3/QV).** (keccak, not Poseidon — the commitment is hashed off-chain and
> recomputed on-chain via the native `keccak256` opcode, never inside the SNARK
> circuit, so Poseidon's in-circuit cheapness is irrelevant and it would be *more*
> expensive on-chain; the repo only ships an arity-2 `PoseidonT3` for Semaphore's
> IMT, with no vector-hash primitive.)
>
> - Bit-pack ⇒ zero shared-infra change, but **caps the whole survey at ~53 bits**
>   (~17 single-choice-of-8 questions; **breaks on multi-select / ranked / QV
>   sub-questions**). Small-survey-only.
> - Hash ⇒ **any survey size & any mix of question types**, non-malleable, but
>   widens the shared prover cast ⇒ **must regression-test the four shipped
>   modules' proofs** (low risk: widening, BigInt round-trips small ints; and
>   Semaphore 4.14.2 natively accepts a BigNumberish message — **verified**).

### Recommendation (clearly labelled; resolves the tension, does not pre-empt the human)

**Build A4: one `ZkSurveyVoting` module — one ballot, one nullifier per voter per
survey — with `message = keccak256(answer vector) >> 8`** (BN254-reduced, exactly
Semaphore's bundled `hash()`; keccak rather than Poseidon because the commitment is
recomputed **on-chain** via the native `keccak256` opcode, never in-circuit) **and
answers in calldata; keep bit-packing as a documented fallback used *only* if we
decide to forbid the `entry.js` change.** Reasoning, scoped to "smallest correct
thing that reuses the modules and preserves the anonymity model":

- **Preserves the anonymity model exactly.** One nullifier per voter per survey,
  one scope = the survey address — identical to every shipped module. No
  shared-group puzzle, no submission-correlation, no per-question leakage. (A2's
  multiplicity is where anonymity gets *harder*, not easier.)
- **Reuses the per-question encodings wholesale.** Each question's answer is an
  existing encoding (M1 index / approval bitmask / rating small-int / M2 packed
  ranking / QV packed alloc); the survey `castVote` validates each per its type
  (the 12a–c validators are the template) and tallies per question into nested
  `voteCounts`. Complex per-question outcomes (a ranked sub-question) reuse M2's
  **off-chain `VoteCast`-replay** discipline; simple ones are authoritative
  on-chain like M1/M3/QV. This *is* the "lessons from 12a–c" the roadmap says 12d
  depends on.
- **Reuses the whole client stack:** `ResultsBars` ×N (no change), the `?module=`
  router pattern, the relayer route/validator/relay shape, the registry, the deploy
  pattern. New surfaces are confined to: the survey contract's `castVote`/tally, a
  survey read surface, a survey repo, a survey detail screen, and the
  **question-builder** create UI (the biggest new piece).
- **Matches prior art:** MACI hashes a multi-value ballot into one field element;
  NIST CVR is one atomic ballot with N independent tallies. A4 is both.

**Explicit flag — the ONLY change that touches already-shipped single-question
modules:** widening `Number(message)` → `BigInt(message)` at
`codes/mobile/web_prover/entry.js:34`. It is shared by M1/M2/M3/QV's proving path.
It is a *widening* (verified: Semaphore 4.14.2 `generateProof` already accepts a
`BigNumberish` message and `toBigInt`s it; small-integer ballots round-trip
unchanged), so risk is bounded — **but the 12d spec must mandate a regression run
of all four existing modules' proof-generation + on-chain verify before/after this
change.** If the user wants **zero** shared-infra change, fall back to Decision B's
bit-pack and accept the small-survey-only ceiling (and document it loudly). No
other layer (contracts M1/M2/M3/QV, relayer existing routes, registry) is touched
by 12d.

**Open question to settle in the spec (not blocking the topology choice):** whether
question *labels/option-strings* live fully on-chain (like today's `options[]`,
simplest, more gas) or off-chain with only `(type, optionCount)` structure on-chain
for validation (cheaper, adds an availability dependency). Recommend **on-chain
labels for v1** (consistency with every shipped module; survey sizes are modest),
revisit if gas bites.

### Rough milestone breakdown (spec → implementation sequence)

1. **M0 — Spec.** Pin the survey data model: `Question { QType, options[], … }`,
   the **canonical answer-vector serialization** and the **keccak256 commitment
   preimage** (exact byte layout — load-bearing, like M2's canonical IRV rule; the
   off-chain JS encoder and the on-chain Solidity recompute MUST agree byte-for-byte,
   reduced `>> 8` to the BN254 field per Semaphore's `hash()`), the
   per-question validation rules (reuse 12a–c), the tally model (on-chain vs
   off-chain-replay per type), `message` binding, and the **HONESTY BAR**
   (Mock verifier proves logic, not SNARK validity — same bound as M1–QV). Decide
   A/B forks here. Module string: `survey-vote`.
2. **M1 — `entry.js` widening + regression gate (if hash-encoding).** Change the one
   cast (`Number(message)`→`BigInt(message)`); **re-run M1/M2/M3/QV proof gen +
   verify** (the go/no-go gate for the hash path). At the same time audit the Dart
   proof plumbing for any `int`-narrowing parse of `message` (it travels as a
   decimal string end-to-end today; confirm nothing does `int.parse` on it) — the
   runtime re-test mostly covers this but the static check is cheap. If the gate
   fails, fall back to bit-pack.
3. **M2 — `ZkSurveyVoting` contract + tests.** Nested question storage,
   `castVote(bytes answers, proof)` recomputing the commitment and validating each
   question by type, per-question tally, `VoteCast` emission for replay-typed
   questions. Tests against `MockSemaphoreVerifier` with boundary vectors per
   question type + no-lockout discipline.
4. **M3 — ABIs + relayer.** `copyAbis` + `assets/abi/ZkSurveyVoting.json`; one
   `validateSurveyVoteRequest` + `relaySurveyVote` + `POST /api/relay/survey-vote`;
   existing routes untouched. `deploy.ts` register + persist `SURVEY_VOTING_IMPL`.
5. **M4 — Flutter read + results.** Survey read surface in `ChainReader`, a survey
   repo, survey detail screen rendering **N `ResultsBars`** (off-chain replay for
   ranked sub-questions).
6. **M5 — Flutter create (largest UI).** The repeating **question-builder**
   (add question → pick type → its options), `initData` encoding, `?module=survey-vote`
   dispatch in `router.dart` + create screen.
7. **M6 — e2e + docs.** Browse→survey detail→vote→results through the mobile e2e
   harness; `architecture/module-survey.md`; roadmap/CHANGELOG.

### Honesty / uncertainty

- **Verified empirically (read in-repo):** the single-question chokepoints
  (`IZkPoll`, per-module `voteCounts`/`message` binding); the four existing
  `message` encodings; the ≤32-bit/`Number(message)` self-cap; the registry being
  survey-agnostic; the relayer's BigInt `message` handling; that
  `@semaphore-protocol/proof@4.14.2` `generateProof` accepts a `BigNumberish`
  message and `toBigInt`s it (so a hash message is natively supported once
  `entry.js` is widened).
- **Not yet built/measured (flag for the spec, not blockers):** the *exact* gas of
  nested per-question storage; whether the WebView prover has any practical issue
  with a full-width hash message in *runtime* (the typedef supports it — runtime
  re-test is the M1 gate); the precise question-builder UX. These are
  implementation-phase items, deliberately out of scope for a research brief.
- **Recommendation is labelled, not mandated.** Decisions A and B are the human's;
  this brief argues A4 is the smallest correct option and isolates the single
  shared-infra change it costs.

---

### Sources
- Codebase (read in-repo): `codes/contracts/contracts/{interfaces/IZkPoll.sol,PollRegistry.sol,ZkAnonVoting.sol,ZkApprovalVoting.sol,ZkRankedVoting.sol,ZkQuadraticVoting.sol}`; `codes/contracts/scripts/deploy.ts`; `codes/relayer/src/{app.ts,relay.ts,validation.ts}`; `codes/mobile/lib/{router.dart,data/models/poll_info.dart,data/services/{chain_reader.dart,poll_creator.dart},data/repositories/approval_repository.dart,ui/features/create/create_screen.dart,ui/widgets/results_bars.dart}`; `codes/mobile/web_prover/entry.js`; `…/@semaphore-protocol/proof@4.14.2/dist/types/{generate-proof.d.ts,to-bigint.d.ts}`; existing specs under `docs/superpowers/specs/` (ranked-choice, quadratic-voting, approval-voting).
- [MACI primitives/circuits — maci.pse.dev](https://maci.pse.dev/docs/v1.2/primitives)
- [Snapshot voting types — docs.snapshot.box](https://docs.snapshot.box/proposals/voting-types)
- [NIST SP 1500-103 Cast Vote Records Common Data Format](https://www.govinfo.gov/content/pkg/GOVPUB-C13-5ece0a87c83a2a7d2ba2072e7420c584/pdf/GOVPUB-C13-5ece0a87c83a2a7d2ba2072e7420c584.pdf)
