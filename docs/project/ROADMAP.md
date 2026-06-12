# Roadmap

> **Phases inherited from the original 2026-04-10 design spec** (see `archive/specs/`), updated with current status. The spec's roadmap remains broadly valid — we've completed Phase 0–2 and are between Phase 2 and 3.

## Phase status legend

- **DONE** — shipped and tested
- **PARTIAL** — some scope shipped, more remains
- **IN PROGRESS** — actively being built (some milestones merged, more open)
- **NEXT** — the immediate next phase
- **PLANNED** — committed but not started
- **DEFERRED** — was on the list, may not happen

## Phase 0: Foundation & Documentation — **DONE**
- Modular contract architecture with `IZkPoll` interface
- `PollRegistry` factory using EIP-1167 minimal proxies
- Documentation framework (`architecture/`, `framework/`, `standards/`)

## Phase 1: M1 — Anonymous Token Voting — **DONE**
- `ZkAnonVoting` contract with Semaphore integration
- Owner-curated invite-token registration
- ZK-proof-based vote casting with nullifier double-vote protection
- Frontend page with admin panel + voter flow
- Test suite covering happy path + edge cases

## Phase 2: M2 — Blind Voting (commit-reveal) — **PARTIAL**
- `ZkBlindVoting` contract — DONE
- Commit-reveal flow with reveal-deadline window — DONE
- Permissionless `register()` (any address can join) — DONE
- Frontend page with countdown + reveal UI — DONE
- **Original spec split this into M2a (live tally) and M2b (sealed); we shipped a single hybrid called `blind-vote`.** Decide: do we keep one module, or split into two for stronger guarantees?

## Phase 2.5: Stabilization — **DONE**

> *Inserted between original Phase 2 and 3 to address P0/P1 debt before adding more modules.*

- Fix all P0 bugs (`improvements/findings.md`) — **DONE**
- Set up CI (`.github/workflows/ci.yml`: contracts / relayer / mobile jobs) — **DONE**
- Land P1 contract hardening (OZ Initializable / Ownable / custom errors / pragma unify / airdrop ReentrancyGuard + escape hatch / anon-vote invariants) — **DONE** (verified 2026-06-03; P1-13 closed by lowering the `registerVoters` cap to 50)
- Real-Groth16 deploy variant + nightly integration test (P3-19 / P4-23) — **DONE**. `deploy.ts` deploys the real `SemaphoreVerifier` under `USE_REAL_VERIFIER=true` (loud warning + refusal-on-public-network for the mock); `RealVerifier.test.ts` proves the real verifier accepts a valid proof and rejects a tampered one, now wired to a nightly + manual-dispatch CI job (`.github/workflows/real-verifier.yml`). The full wallet-free vote path (proof → relayer → on-chain real verifier) was additionally proven on the live chain via `scripts/e2e-relayer-real-vote.ts` + `scripts/check-live-verifier.ts`.
- ~~Refactor `Poll.tsx` and `BlindPoll.tsx` (P2)~~ — **MOOT** (React frontend deleted; the Flutter client `codes/mobile/` supersedes it)

**Exit criteria:** zero open P0 (met), zero open P1 (met), CI green (met), real-verifier path exercised (met — nightly CI + live-chain e2e).

## Phase 3: M3 — Participation Receipts — **PLANNED**
- `verifyParticipation(nullifierHash)` already exists on `IZkPoll` — UI surface missing
- Add a `/receipt/:nullifier` page that lets any third party verify a vote was cast
- Document the receipt format so it can be used as a proof outside the dApp
- Integrate into both M1 and M2

## Phase 4: M2b — Sealed Blind Voting — **DEFERRED**
- Original spec called for fully sealed results until reveal deadline
- Current `blind-vote` exposes per-reveal counts during the reveal window
- Decision: ship as a separate module (`blind-sealed`)? Or out of scope for v1?

## Phase 5: Integration Layer — **PLANNED**
- TypeScript SDK so third-party projects (e.g. other student projects) can embed polls
- REST/GraphQL gateway? Or pure on-chain reads?
- Documented contract addresses on each supported network

## Phase 6: Testnet Deployment — **PLANNED**
- Deploy Registry + all module impls to Sepolia
- Real `SemaphoreVerifier`, real SNARK artifacts
- ENS subdomain for the dApp
- Public `deployed-addresses.json` per network

## Phase 7: Mainnet — **NOT COMMITTED**
- Requires an external audit
- Multisig owner on Registry
- Documented threat model per module
- Bug bounty

## Cross-cutting concerns (always-on)

These ride alongside every phase:

- **Security audits** — informal pre-release review for each phase ≥3, formal audit before mainnet
- **Documentation** — every shipped module gets an `architecture/module-*.md` doc
- **Tests** — no untested contract reaches `main`
- **Standards drift** — review `standards/` quarterly; if reality has moved, update them

## Phase 8: Tessera — Unified Flutter Client — **DONE**

> Supersedes "Mobile-native client — responsive web only" below. One Flutter
> codebase (`codes/mobile/`) became the canonical client across mobile, desktop,
> AND web. See `docs/superpowers/specs/2026-06-02-tessera-unify-flutter-design.md`.
> **Since superseded in turn by the Phase 13 `codes/app/` workspace** —
> `codes/mobile/` is the frozen reference until the cutover PR lands.

- Linux/desktop launch; Identity management; **M2 blind-vote** UI (commit-reveal);
  Receipts via Verify; live-meeting **host + voter**; **desktop ZK proving** (Node
  sidecar, real-vkey-verified); local **dev-signer**; **BLE/NFC** proximity seam.
- React frontend **deprecated** (Flutter-web canonical).

## Phase 9: Release readiness & product polish — **PARTIAL (largely superseded by Phase 13)**

- Cut **v0.2.0** (the Tessera milestone) per `RELEASING.md` once guardrails
  pass — **DONE** (CHANGELOG `[0.2.0] — 2026-06-02`). The next release cut
  should follow the Phase 13 cutover.
- App polish (Settings, results charts `ResultsBars`, layouts, empty states)
  — **DONE in `codes/mobile/`**, and the surfaces themselves were since
  rebuilt in the Phase 13 three-space IA (`codes/app/`); `ResultsBars` and
  the design tokens were lifted into `design_system`. Browse
  **pagination** never shipped and remains open debt (P4-21/P4-22 — applies
  to `getListedPolls` too).
- ~~**Mobile WebView prover** (so phones vote natively)~~ — promoted to a dedicated
  effort: **Phase 11** (and reframed as emulator-verifiable, not device-pending).
- ~~Decouple `codes/frontend`~~ — **DONE** (React removed; prover self-contained).

## Phase 11: Close the loop on mobile — scan + native proving — **DONE**

> Spec: `docs/superpowers/specs/2026-06-02-mobile-scan-and-native-proving-design.md`.
> Makes the live-meeting flow complete device-to-device on a phone.

- **M1 — WebView-proving go/no-go spike** (blob-URL artifact injection;
  loopback-server fallback; native FFI is out of scope). **DONE — spike returned
  GO**: a Groth16 proof generated inside a headless `webview_flutter` on the
  API-31 emulator, verified against the real vkey (PR #48).
- **M2 — Native on-device proving** (`ProofServiceMobile`): a headless
  `webview_flutter` hosting the same `zkprover.js`, with the Semaphore depth-16
  artifacts **bundled** (~5.2 MB). `entry.js` gets an *additive* artifact-override
  arg — **web/desktop provers untouched** (LeanIMT root is member-derived, so depth
  need not match across clients). Factory-selected on Android; iOS fenced. **DONE**
  (emulator-verified against the real Groth16 vkey, PR #48).
- **M3 — In-app QR scanner** (`mobile_scanner`) on the live-vote `needsTicket`
  stage — scan the host's rotating QR instead of pasting; paste stays as the
  fallback. **DONE** (PR #61). Camera capability-gated; paste is the verified
  fallback route. Live camera scan is real-device-pending — a follow-up gate.
- **Verified-or-fenced:** proving is **emulator-verified** against the real Groth16
  vkey; the **camera** is the only real-device/fenced piece (paste = verified
  fallback). Real-device confirmation is a follow-up gate.
- **Post-Phase-13 note:** the WebView mobile prover (`ProofServiceMobile`) and
  its platform siblings now live in the workspace's `core_crypto` package
  (`codes/app/packages/core_crypto/lib/proof/`), lifted verbatim in R1. iOS
  proving remains unsupported/fenced.

## Phase 10: Public testnet (Sepolia) + real verifier — **PLANNED**

- Deploy Registry + modules to Sepolia with a **real Groth16 SemaphoreVerifier**
  (replace the local Mock). Per-network `deployed-addresses.<net>.json`.
- The real verifier is already **done + proven on the live local chain**
  (P4-23, nightly CI) — what remains is the Sepolia deployment itself.
- Per the Revolution spec (§7), this gate **merges with Phase 14 (R5
  cryptographic sealing)**: R5 + Sepolia together are the path to `1.0`.
- This + "no open P0/P1" is the bar to move from `0.x` to **`1.0.0`**.

## Phase 12: Richer voting types — **COMPLETE (epic — 12a/12b/12c/12d all shipped)**

> User-requested (2026-06-02): all four. Each is a **new on-chain module** (new
> Solidity + tests + ABIs + `PollRegistry` registration + deploy wiring) behind
> the existing `IZkPoll`/module-type dispatch, plus a Flutter repository + screen.
> Contracts are audit-sensitive → designed carefully, built **serially-ish** (not
> rushed into parallel worktrees), each with `architecture/module-*.md` + tests
> before `main`. Recommended order is smallest→largest:

- **12a — Approval voting** — voters select any number of options; the tally
  counts per-option approvals. **DONE / SHIPPED** — backend (`ZkApprovalVoting`
  bitmask-ballot module + `approval-vote` relayer route, spec:
  `docs/superpowers/specs/2026-06-02-approval-voting-design.md`) **and** the
  Flutter UI (module-type picker in Create, `?module=approval-vote` router
  dispatch → multi-select checkbox `ApprovalPollScreen` → bitmask cast, results
  as per-option approvals over the voter count).
- **12b — Ranked-choice (IRV)** — voters rank options; instant-runoff elimination.
  Off-chain Dart IRV tally with the pinned canonical elimination rule. **DONE** —
  contract + relayer (#49) and Flutter UI + off-chain Dart IRV tally (#53).
- **12c — Weighted / quadratic** — votes carry weight (token-weighted or quadratic
  cost); uniform `CREDITS=100` budget, `Σvᵢ²≤100`. **DONE** — backend (#51) and
  Flutter UI (#53); ranked-choice and quadratic polls are now **creatable from the
  mobile Create screen** (dev-signer-gated, ≤8-option guard, #57).
- **12d — Multi-question survey ("Google-Forms")** — a poll = several questions,
  each single-choice / multi-select. **Redefines the poll data model**; largest
  scope; depended on lessons from 12a–12c. **DONE / SHIPPED FULL-STACK** — one
  `ZkSurveyVoting` module, one ballot/nullifier per survey, hash-commitment
  `message = keccak256(abi.encode(answers)) >> 8`. Shipped across the whole stack:
  - **Contract** — `ZkSurveyVoting` with nested per-question storage, the
    commitment recompute, per-question validation + no-lockout, and per-question
    results (`getSurveyResults`); 45 hardhat tests (#60).
  - **Relayer** — `POST /api/relay/survey-vote` route + `validateSurveyVoteRequest`
    (14 tests); ABIs + `deploy.ts` register + `SURVEY_VOTING_IMPL` persist.
  - **Flutter** — survey read/answer/cast/results (N `ResultsBars`, one per
    question) (#65) **and** the question-builder create flow
    (`?module=survey-vote` dispatch) (#66).
  - **Prover** — Gate 1 widened the shared web prover signal `Number→BigInt` in
    `entry.js`, regression-verified against all four shipped SNARK-message modules'
    real-vkey proofs (#59), unblocking the wide keccak-commitment message.
  - **Gate 2 (cross-impl)** — Dart `surveyCommitment` ≡ ethers ≡ Solidity
    `keccak256(abi.encode(answers)) >> 8` (the load-bearing serialization match),
    plus the init-encoding cross-check.
  - **Stack e2e** — `scripts/demo-poll.ts` seeds a real survey on the local chain
    (create → register → cast `[2,5]` → per-question `getSurveyResults`), proving
    the full stack end-to-end (no emulator).
  - Design spec: `docs/superpowers/specs/2026-06-03-survey-voting-design.md`;
    architecture: `docs/architecture/module-survey.md`. The on-device mobile UI
    survey cast is the same device-gated/fenced bound as every other module's
    on-device proving (a named follow-up, not a regression risk).

The **Phase 12 voting-types epic is complete**: approval (12a), ranked-choice
(12b), quadratic (12c), and survey (12d) all shipped — contract + relayer +
Flutter — behind the existing `IZkPoll` / module-type dispatch. Each sub-module
has its own design spec and `architecture/module-*.md`.

## Phase 13: Tessera Revolution — persona IA, flow enforcement, by-design defaults — **DONE (R1–R4; R5 split out below)**

> Spec: `docs/superpowers/specs/2026-06-11-tessera-revolution-design.md`.
> Owner mandate (2026-06-11). Ground-up redesign of the client product layer,
> shipped as audited PRs #100–#122 over 2026-06-11→12:

- **R0 — Triage** — **CUT** (owner decision, spec §7): no interim-usability
  work on the old app. The R0 fixes landed once, in their final homes — phase
  gating / reveal-deadline enforcement / live timeouts as R2 journey
  transitions, module-aware routing as the R2/R3 on-chain resolver, screen
  tests against the R3 screens. Only the relayer ballot-log strip shipped
  standalone (#100).
- **R1 — Workspace** — **DONE** (#101): pub workspace + melos 7 at
  `codes/app/`; proven non-UI code lifted verbatim into `core_domain` /
  `core_chain` / `core_crypto` / `core_relay` / `core_storage` +
  `design_system`; per-package CI. Zero behavior change.
- **R2 — Journey engine** — **DONE** (#102–#107): journey contract +
  capabilities/policies/route-guard model, then the voter, blind
  commit-reveal, organizer, and live voter+host state machines in
  `core_domain` (flow enforcement: phase gating, salt-backup gate,
  reveal-deadline client enforcement, live timeouts, organizer phase
  ordering); typed join-target grammar + short-code format (#103); guarded
  go_router + `Capabilities` probe + app skeleton (#109).
- **R3 — Three-space IA** — **DONE** (#110–#114, #116): VOTE / ORGANIZE /
  JOIN-droplet / You shell with zero crypto jargon for voters; organizer
  create flow with private defaults + run-event console; JOIN
  scan/paste/code + live-voter flow; voting pass / receipts / verify /
  settings under You.
- **R4 — Privacy defaults** — **DONE** (#108, #117): `visibility` +
  `resultsPolicy` on registry/modules, **unlisted + sealed-results by
  default** with creation-time opt-ins (defaults live in the contract — the
  4-arg `createPoll` overload hard-defaults to unlisted); `getListedPolls()`
  directory + `getPollInfo` link access; relayer pass-through shim keeps
  pre-R4 clients working (and private); client core migrated (refreshed R4
  ABIs, overload-aware `createPoll`, pinned sponsored wire format);
  small-group warning chip on the organizer dashboard. Contracts at 296 tests.
- Rode along: web perf (−19.7% cold-load bytes, lazy prover — also fixed web
  proving wiring, #115), Tessera brand identity (#122), idempotent JOIN
  navigation (#121), melos `format:check` CI gate (#119), env-configurable
  relayer limits (#118, #120).
- **Remaining from the phase:** the legacy `codes/mobile/` cutover PR
  (in flight) and the short-code resolver (spec §8 open question 2 — the
  grammar + honest UI shipped; the lookup did not).

## Phase 14 (was 13-R5): Cryptographic sealing — **NEXT**

> Spec §5 (privacy model — "cryptographic sealing (threshold/timelock) =
> Phase R5") and §7 (R5 line). Needs its own design spec before
> implementation.

- Threshold or timelock sealed ballots (Shutter-style) so "sealed until
  close" becomes cryptographic, not client-honored metadata — today
  `getResults()` is deliberately ungated on-chain because ballots are public
  calldata.
- Receipt-freeness review.
- Merges with the Phase 10 Sepolia gate: R5 + Sepolia together are the path
  to `1.0`.

## Out of scope (explicit)

- DAO governance over the Registry — owner-only is intentional for v1
- Cross-chain support — single-chain deployment per release
- On-chain identity systems beyond Semaphore

## How to update this file

- Phase status changes happen here, not in STATUS.md.
- Phases can be split, merged, or renumbered; record the rationale in CHANGELOG.md when you do.
- New phases get appended; don't reuse phase numbers.
