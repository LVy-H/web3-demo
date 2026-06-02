# Roadmap

> **Phases inherited from the original 2026-04-10 design spec** (see `archive/specs/`), updated with current status. The spec's roadmap remains broadly valid — we've completed Phase 0–2 and are between Phase 2 and 3.

## Phase status legend

- **DONE** — shipped and tested
- **PARTIAL** — some scope shipped, more remains
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

## Phase 2.5: Stabilization — **NEXT**

> *Inserted between original Phase 2 and 3 to address P0/P1 debt before adding more modules.*

- Fix all P0 bugs (`improvements/findings.md`)
- Land P1 contract hardening (OZ Initializable / Ownable / pragma unify)
- Set up CI
- Real-Groth16 deploy variant + nightly integration test
- Refactor `Poll.tsx` and `BlindPoll.tsx` (P2)

**Exit criteria:** zero open P0, zero open P1, CI green, frontend pages under 250 LOC each.

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
  charts** on poll detail (spec:
  `docs/superpowers/specs/2026-06-02-results-charts-design.md`), a11y.
- ~~**Mobile WebView prover** (so phones vote natively)~~ — promoted to a dedicated
  effort: **Phase 11** (and reframed as emulator-verifiable, not device-pending).
- ~~Decouple `codes/frontend`~~ — **DONE** (React removed; prover self-contained).

## Phase 11: Close the loop on mobile — scan + native proving — **NEXT**

> Spec: `docs/superpowers/specs/2026-06-02-mobile-scan-and-native-proving-design.md`.
> Makes the live-meeting flow complete device-to-device on a phone.

- **In-app QR scanner** (`mobile_scanner`) on the live-vote `needsTicket` stage —
  scan the host's rotating QR instead of pasting; paste stays as the fallback.
- **Native on-device proving** (`ProofServiceMobile`): a headless `webview_flutter`
  hosting the same `zkprover.js`, with the Semaphore depth-16 artifacts **bundled**
  (~5.2 MB). `entry.js` gets an *additive* artifact-override arg — **web/desktop
  provers untouched** (LeanIMT root is member-derived, so depth need not match
  across clients).
- **Milestone gate:** M1 is a WebView-proving **go/no-go spike** (blob-URL artifact
  injection; loopback-server fallback; native FFI is out of scope) before the rest.
- **Verified-or-fenced:** proving is **emulator-verified** against the real Groth16
  vkey; the **camera** is the only real-device/fenced piece (paste = verified
  fallback). Real-device confirmation is a follow-up gate.

## Phase 10: Public testnet (Sepolia) + real verifier — **PLANNED**

- Deploy Registry + modules to Sepolia with a **real Groth16 SemaphoreVerifier**
  (replace the local Mock). Per-network `deployed-addresses.<net>.json`.
- This + "no open P0/P1" is the bar to move from `0.x` to **`1.0.0`**.

## Phase 12: Richer voting types — **PLANNED (epic — own design per sub-module)**

> User-requested (2026-06-02): all four. Each is a **new on-chain module** (new
> Solidity + tests + ABIs + `PollRegistry` registration + deploy wiring) behind
> the existing `IZkPoll`/module-type dispatch, plus a Flutter repository + screen.
> Contracts are audit-sensitive → designed carefully, built **serially-ish** (not
> rushed into parallel worktrees), each with `architecture/module-*.md` + tests
> before `main`. Recommended order is smallest→largest:

- **12a — Approval voting** — voters select any number of options; highest-approved
  wins. Smallest contract delta (closest to current single-choice). **First.**
- **12b — Ranked-choice (IRV)** — voters rank options; instant-runoff elimination.
  Heavier tally (decide on-chain vs verifiable off-chain).
- **12c — Weighted / quadratic** — votes carry weight (token-weighted or quadratic
  cost); needs a weight/credit source. Governance-oriented.
- **12d — Multi-question survey ("Google-Forms")** — a poll = several questions,
  each single-choice / multi-select / rating. **Redefines the poll data model**;
  largest scope; depends on lessons from 12a–12c.

Each sub-module gets its own design spec before implementation.

## Out of scope (explicit)

- DAO governance over the Registry — owner-only is intentional for v1
- Cross-chain support — single-chain deployment per release
- On-chain identity systems beyond Semaphore

## How to update this file

- Phase status changes happen here, not in STATUS.md.
- Phases can be split, merged, or renumbered; record the rationale in CHANGELOG.md when you do.
- New phases get appended; don't reuse phase numbers.
