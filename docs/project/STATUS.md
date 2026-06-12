# Status

> **Snapshot:** 2026-06-13 — keep this date current when editing.

## TL;DR

**The Tessera Revolution (Phase 13, R1–R4) shipped** — PRs #100–#122, merged 2026-06-11→12 (spec: `docs/superpowers/specs/2026-06-11-tessera-revolution-design.md`). The client is now the **`codes/app/` pub workspace** (10 packages + the `apps/tessera` shell): persona-driven three-space IA (**VOTE / ORGANIZE / JOIN / You**) with zero crypto jargon for voters, **journey state machines** in `core_domain` enforced by router guards (no more reachable-but-broken flows), and **privacy by design on-chain** — every poll is **unlisted + sealed-results by default**, listing and live tallies are creation-time opt-ins. The relayer never logs ballot contents. The six voting modules, real Groth16 verifier (proven end-to-end on the live local chain, nightly CI), and the wallet-free sponsored path all carry over. **Legacy `codes/mobile/` cutover is in flight** (parallel PR: delete it, point CI + `dev-stack.sh` at `codes/app/`). **Still no deployment beyond local Hardhat** — the Sepolia testnet deployment (Phase 10) remains the `1.0` gate, now planned to merge with R5 (cryptographic sealing).

## Shipped (works today)

### Contracts (`codes/contracts/`)
- `PollRegistry` — EIP-1167 factory, six modules registered (`anon-vote`,
  `blind-vote`, `approval-vote`, `ranked-vote`, `quadratic-vote`, `survey-vote`)
- **R4 privacy defaults (PR #108):** per-poll `visibility`
  (`0 = unlisted` DEFAULT, `1 = listed` opt-in) captured at `createPoll`; the
  pre-existing 4-arg `createPoll` is kept as an overload that hard-defaults to
  unlisted (defaults live in the contract, not in callers); `getListedPolls()`
  is the public-directory view; `getPollInfo(address)` resolves link access for
  unlisted polls. Per-module `resultsPolicy` (`0 = sealed-until-close` DEFAULT,
  `1 = live-public` opt-in) as a trailing `uint8` on every module's
  `initialize`, exposed via `resultsPolicy()` on `IZkPoll`. NatSpec states the
  honest limits: `visibility` is *discovery* privacy, `resultsPolicy` is
  client/relayer-honored metadata — cryptographic sealing is R5.
- `ZkAnonVoting` (M1), `ZkBlindVoting` (M2), `ZkApprovalVoting`,
  `ZkRankedVoting`, `ZkQuadraticVoting`, `ZkSurveyVoting` — all six modules
  tested ✓; plus the standalone `ZkAirdrop`.
- `MockSemaphoreVerifier` (default, fast) **and the real Groth16
  `SemaphoreVerifier`** (`USE_REAL_VERIFIER=true` / `ZK_REAL_VERIFIER=1
  ./dev-stack.sh up`), proven end-to-end on the live chain
  (`scripts/check-live-verifier.ts`, `scripts/e2e-relayer-real-vote.ts`) with a
  nightly CI job (`.github/workflows/real-verifier.yml`).
- Deploy script wires it all together and writes `deployed-addresses.json`;
  `copyAbis.ts` targets `core_chain`'s package assets.
- **296 hardhat tests passing** (1 pending) — PR #108 `npm test`.

### Client — Tessera (`codes/app/` pub workspace)

The Revolution rebuilt the client as a **pub workspace (melos 7)** — 10
packages + a thin app shell, with an enforced dependency direction
(`apps/tessera → feature_* → core_* + design_system`; `core_domain` depends on
nothing):

- `core_domain` — entities + the **journey state machines** (pure Dart):
  voter, blind commit-reveal, organizer, and live voter + host journeys behind
  a shared journey contract (PRs #102, #104–#107). Flow enforcement lives
  here, testable without widgets: phase gating (no casting outside the open
  phase), the **salt-backup gate** before a blind commit, **reveal-deadline
  client enforcement**, **live-voter pending timeouts**, and organizer phase
  ordering.
- `core_chain` — chain reader/writer + packaged R4 ABIs; overload-aware
  `createPoll` resolution, `getListedPolls` / `getPollInfo` /
  `getResultsPolicy` reads (PR #117).
- `core_crypto` — identity, commitments, and the proof services: browser
  (web), Node sidecar (desktop), and the headless-WebView mobile prover all
  live here now (lifted from `codes/mobile/`); `zkprover.js` is lazy-loaded on
  first prove (PR #115 — which also fixed web proving wiring: the workspace
  shell had never loaded the prover, so web proving was broken before it).
- `core_relay` — relayer client; sponsored path pins the pre-R4 wire format +
  top-level `visibility`/`resultsPolicy` JSON fields (the relayer shim appends
  the policy — documented wire decision, PR #117).
- `core_storage` — secure stores (identity seed, blind salts, created polls,
  network config).
- `design_system` — Dark Bauhaus tokens, shared widgets, the `TesseraMark`
  brand widget.
- `feature_join` — the **JOIN droplet** (notched into the navbar, PR #116):
  scan / paste / typed `TES-XXXXXX` code, typed join-target grammar
  (PR #103) + live-voter flow. Idempotent navigation (duplicate page-key
  crash fixed, PR #121).
- `feature_vote` — VOTE space: directory of *listed* polls only, module
  ballots for all six types, sealed-results presentation (PR #113).
- `feature_organize` — ORGANIZE space: create flow with **private defaults**
  + creation-time opt-ins + small-group warning, run-event console (PR #114).
- `feature_you` — You: voting pass, receipts, verify, settings (PR #111).
- `apps/tessera` — composition root, **guarded router** (go_router
  `redirect` driven by the journey machines), `Capabilities` probe, on-chain
  module resolution for the single poll route (PR #109).

Plus: **web perf** — cold-load payload 12.0 MB → 9.6 MB (**−19.7%** bytes;
computed 10 Mbps load ≈ −22%) via icon tree-shaking, font subsetting,
self-hosted CanvasKit, batched ABI loads, lazy prover (PR #115). **Tessera
brand identity** — tile mark, web/Android icons, splash, titles (PR #122).
CI-gated `melos format:check` + analyze + per-package tests (PR #119).

### Legacy client (`codes/mobile/`)
- The pre-Revolution Flutter app, still on `main` as the working reference
  until cutover (in flight, below). Still what the CI `mobile`/`android` jobs
  and `dev-stack.sh` e2e target today.

### Relayer (`codes/relayer/`)
- Optional Express service: gasless vote / airdrop-claim submission plus the
  sponsored (wallet-free) poll lifecycle. **121 vitest tests passing**
  (2 skipped) — PR #120 `npm test`.
- **Privacy-by-design logging (PR #100):** ballot contents (`vote`, `bitmask`,
  `packedRanking`, `packedAlloc`, `answers`) are never logged — routes log
  only poll + route + status, with a mutation-checked regression suite
  (`test/log-privacy.test.ts`).
- **R4 pass-through (PR #108):** create-poll accepts optional
  `visibility`/`resultsPolicy` (default 0/0 = private) and re-encodes pre-R4
  client `initData` with the policy appended, so R4-unaware clients keep
  working and get sealed-by-default.
- **Env-configurable limits (PRs #118, #120):** `RELAY_RATE_LIMIT_MAX/WINDOW_MS`
  and `RELAY_CREATE_DAILY_MAX` / `RELAY_REGISTER_PER_POLL_MAX`; production
  defaults unchanged, `dev-stack.sh` raises them for local dev.

### Infra
- `docker-compose.yml` — dev-only stack: `contracts` (Hardhat node) +
  `relayer` + `explorer`. The local-dev one-liner is `./dev-stack.sh up`.
- `.github/workflows/ci.yml` — five jobs: `contracts` / `relayer` / `mobile`
  (legacy) / **`app`** (melos `format:check` → analyze → per-package tests,
  PR #119) / `android`.
- Nightly real-verifier job (`.github/workflows/real-verifier.yml`).

## In flight

> Track the current iteration's work in [FOCUS.md](./FOCUS.md). Items here are mid-implementation but not blocked.

- 2026-06-13 — **Legacy `codes/mobile/` cutover** (parallel PR, per the spec's
  one-PR cutover plan): delete `codes/mobile/`, point CI + `dev-stack.sh` +
  README/architecture docs at `codes/app/`. Until it merges, two clients
  coexist on `main` (codes/app is canonical; codes/mobile is the frozen
  reference).

## Blocked / known broken

**No open P0 items** (`improvements/findings.md`; the P0/P1 backlog was closed
2026-06-02/03). The real Groth16 verifier is done + proven (P4-23); the next
release gate is the Phase 10 Sepolia deployment → `1.0`.

Honest gaps in the shipped Revolution (by design, tracked):

- **R5 cryptographic sealing is NOT done** — `resultsPolicy` is honored by
  compliant clients/relayer, but `getResults()` is deliberately not gated
  on-chain (ballots are public calldata; a view gate would be security
  theater). Threshold/timelock sealing + receipt-freeness review = R5.
- **Short-code resolver pending** — `TES-XXXXXX` codes have a typed grammar
  and honest "codes aren't live yet" UI (`feature_join`), but the
  code→address lookup (spec §8 open question 2, relayer-hosted) has not
  shipped. Link/QR join works.
- **iOS proving unsupported** — the WebView prover is Android
  (emulator-verified); iOS remains fenced, tracked outside the Revolution.

## Not started

- Testnet deployment of any kind (Phase 10: Sepolia → `1.0`; merges with R5
  per the spec)
- R5 — cryptographic sealing (separate spec to be written; spec §5/§7)
- Pagination / event-driven poll list (`getAllPolls`/`getListedPolls` won't
  scale past dozens of polls; P4-21/P4-22)
- Web prover zkey self-hosting (P4-24; parked branch
  `origin/feat/web-prover-no-cdn`)
- Phase 5 integration layer (SDK / API for third-party use)

## Health metrics

| Metric | Value | Target | Source |
|---|---|---|---|
| Contracts test count | 296 passing (1 pending) | n/a | `npm test` in `codes/contracts/`, cited in PR #108 |
| Relayer test count | 121 passing (2 skipped) | n/a | `npm test` in `codes/relayer/`, cited in PR #120 |
| App workspace (codes/app) | format:check + analyze + per-package tests green | green | CI `app` job (PR #119) |
| Legacy client (codes/mobile) | analyze clean, tests green | green until cutover | CI `mobile` job |
| Web cold-load payload | 9.6 MB (was 12.0 MB, −19.7%) | n/a | PR #115 waterfall measurements |
| `npm run deploy:local` reproducible | yes | yes | deterministic Hardhat addresses |
| CI status | 5 jobs (contracts / relayer / mobile / app / android) | green on every PR | `.github/workflows/ci.yml` |
| Open P0 items | 0 | 0 | `improvements/findings.md` |
| Open P1 items | 0 | 0 before any deploy | `improvements/findings.md` |

## How to update this file

- Move items between sections as work progresses.
- Add a dated entry at the top of "In flight" when work starts (`YYYY-MM-DD - what + who`).
- When something ships, **delete the in-flight entry** and update "Shipped". Don't accumulate a history here — that's CHANGELOG's job.
