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

## Phase 2.5: Stabilization — **IN PROGRESS**

> *Inserted between original Phase 2 and 3 to address P0/P1 debt before adding more modules.*

- Fix all P0 bugs (`improvements/findings.md`) — **DONE**
- Set up CI (`.github/workflows/ci.yml`: contracts / relayer / mobile jobs) — **DONE**
- Land P1 contract hardening (OZ Initializable / Ownable / custom errors / pragma unify / airdrop ReentrancyGuard + escape hatch / anon-vote invariants) — **DONE** (verified 2026-06-03; P1-13 closed by lowering the `registerVoters` cap to 50)
- Real-Groth16 deploy variant + nightly integration test (P3-19 / P4-23) — PLANNED (the **only** remaining 2.5 item; rolls into Phase 10)
- ~~Refactor `Poll.tsx` and `BlindPoll.tsx` (P2)~~ — **MOOT** (React frontend deleted; the Flutter client `codes/mobile/` supersedes it)

**Exit criteria:** zero open P0 (met), zero open P1 (met), CI green (met), real-verifier path exercised (→ Phase 10).

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
> codebase (`codes/mobile/`) is now the canonical client across mobile, desktop,
> AND web. See `docs/superpowers/specs/2026-06-02-tessera-unify-flutter-design.md`.

- Linux/desktop launch; Identity management; **M2 blind-vote** UI (commit-reveal);
  Receipts via Verify; live-meeting **host + voter**; **desktop ZK proving** (Node
  sidecar, real-vkey-verified); local **dev-signer**; **BLE/NFC** proximity seam.
- React frontend **deprecated** (Flutter-web canonical).

## Phase 9: Release readiness & product polish — **PARTIAL**

- Cut **v0.2.0** (the Tessera milestone) per `RELEASING.md` once guardrails pass.
- App polish: **Settings** (network/relayer/theme), browse **search/filter/
  pagination**, responsive desktop layouts, onboarding/empty states, **results
  charts** on poll detail — **DONE** (themed tally bars `ResultsBars` on M1/M2,
  reused by M3 approval; spec:
  `docs/superpowers/specs/2026-06-02-results-charts-design.md`), a11y.
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

## Phase 10: Public testnet (Sepolia) + real verifier — **PLANNED**

- Deploy Registry + modules to Sepolia with a **real Groth16 SemaphoreVerifier**
  (replace the local Mock). Per-network `deployed-addresses.<net>.json`.
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

## Out of scope (explicit)

- DAO governance over the Registry — owner-only is intentional for v1
- Cross-chain support — single-chain deployment per release
- On-chain identity systems beyond Semaphore

## How to update this file

- Phase status changes happen here, not in STATUS.md.
- Phases can be split, merged, or renumbered; record the rationale in CHANGELOG.md when you do.
- New phases get appended; don't reuse phase numbers.
