# Tessera Phase 2 — The Server (open-ballot, end-to-end)

> **Parent plan:** [`2026-06-19-tessera-1.0-implementation-plan.md`](2026-06-19-tessera-1.0-implementation-plan.md) §"Phase 2".
> **Design source of truth:** [`../specs/2026-06-19-tessera-system-design.md`](../specs/2026-06-19-tessera-system-design.md) — §9 data model, §10 API, §11 verification, §12 deep-dives.
> **Branch:** `redesign/phase2-server` (stacked on `redesign/phase1-dismantle`).
> **Execution method:** parallel background subagents, each in its **own worktree** scoped to a **disjoint module directory** (zero merge conflict), merged back into `redesign/phase2-server`; worktrees deleted on merge.

## Goal

Stand up the self-hosted server so an **open-ballot** decision runs end-to-end:
`create → open → cast (idempotent) → close → publish`, with a public read API, a
self-contained receipt, and a recomputable tally+verdict. One-command broadcast/casual
deploy. **No crypto wallet, no blind signatures, no chain** in Phase 2.

### In scope (Phase 2)
- SQLite storage (WAL, single-writer, append-only ballots) for the §9 entities Phase 2 needs.
- Convener auth (bootstrap admin token + per-convener bearer tokens).
- Decision lifecycle state machine + signed `LifecycleEvent`s + `setupCommitment`.
- Open-mode eligibility: `open` · `passcode` · `domain` (+ `maxParticipants`, rate-limit).
- Cast (open ballot) with `idempotencyKey`, single-txn ballot+receipt commit.
- Running **hash-chained** receipts + a `/root` head (a simple chain; RFC 6962 Merkle + anchoring is Phase 3).
- The shared **tally oracle** (six methods + verdict) — reused by the Phase 3 verifier.
- Public read API (`/decisions/:id`, `/ballots`, `/root`, `/results`, `/anchor`).

### Deferred to Phase 3 (do NOT build here)
- Blind-signature credentials / `POST /register` / `IssuedCredential` ledger / `SigningKey`.
- RFC 6962 Merkle log + interim/final **checkpoints** + the **anchor adapter** (broadcast/chain).
- The independent **public verifier** + root-binding + challenge window.
- Secret-mode privacy mechanics. (Phase 2 `anchorMode` is recorded but only `casual`/`broadcast-head` is served.)

## Tech decisions
- **better-sqlite3** (synchronous → natural single-writer discipline; §12.6 `synchronous=FULL`, WAL, `busy_timeout`).
- **zod** for request/payload validation (stable error codes).
- Node built-in `crypto` for sha256 + **Ed25519** server signing key (no extra dep).
- IDs: `crypto.randomUUID()`. No ORM — thin typed repositories over prepared statements.
- Keep `createApp()` factory shape (Phase 1); add routers; `index.ts` wires the DB path from env.

---

## Module decomposition (the parallelization contract)

Four **independent** foundation modules (no cross-imports among them) fan out first.
Each exports the signatures below; downstream layers import them. Agents create ONLY files
under their module dir + their own test files. **No agent touches `package.json`,
`tsconfig.json`, `src/app.ts`, or `src/index.ts`** — those are pre-seeded / integrated by the
orchestrator.

### Module A — `src/db/`  (storage core)  ·  agent: phase2-db
Responsibility: SQLite connection + migrations + typed repositories.
```ts
// src/db/index.ts
export function openDb(path: string): Database            // PRAGMA: journal_mode=WAL, synchronous=FULL, busy_timeout=5000, foreign_keys=ON
export function migrate(db: Database): void               // idempotent; runs ordered migrations in src/db/migrations/
// src/db/repos.ts  — thin typed repos (prepared statements)
export interface AccountRepo { create(a): Account; findByTokenHash(h: string): Account | null; ... }
export interface DecisionRepo { insert(d): Decision; get(id): Decision | null; setState(id, state, at): void; list(...): Decision[] }
export interface BallotRepo  { append(b): Ballot /* throws on duplicate idempotencyKey */; byDecision(id, after?, limit?): Ballot[]; count(id): number; head(id): string }
export interface ReceiptRepo { put(r): Receipt; byBallot(h): Receipt | null }
export interface LifecycleRepo { append(e): LifecycleEvent; byDecision(id): LifecycleEvent[] }
export interface EligibilityRepo { ... passcode hash+counter; domain rule; mark used ... }
export function makeRepos(db: Database): { accounts, decisions, ballots, receipts, lifecycle, eligibility }
```
Schema (Phase-2 active tables): `accounts`, `sessions`, `decisions`, `ballots`
(append-only — enforce via `BEFORE UPDATE/DELETE` triggers that RAISE), `receipts`,
`lifecycle_events`, `eligibility_records`, `decision_head` (running root). Create Phase 3
tables later via new migrations (migrations are append-only, numbered).
TDD: migration creates every table; WAL pragma asserted; `ballots` UPDATE/DELETE rejected;
`append` twice with same `idempotencyKey` throws a typed `DuplicateBallotError`.

### Module B — `src/tally/`  (the shared oracle)  ·  agent: phase2-tally
Responsibility: pure, dependency-free tally + verdict. **Port the algorithms** from the Dart
sources `codes/app/packages/core_domain/lib/voting/ranked_irv.dart` and
`quadratic_alloc.dart` (read them; reimplement in TS; match their results).
```ts
export type Method = 'single'|'approval'|'ranked'|'quadratic'|'survey';
export interface Rule { threshold: {kind:'plurality'|'majority'|'supermajority', percent?:number}; quorum?: number; tieBreak: 'declare'|'runoff'|'casting'|'random-seed' }
export function tally(method: Method, ballots: BallotPayload[], optionCount: number): Tally   // counts, incl. abstain bucket
export function verdict(t: Tally, rule: Rule, eligibleOrCast: number): Verdict  // 'carried'|'failed'|'tie'|'quorum-not-met'
```
TDD: golden fixtures per method (incl. IRV elimination rounds, quadratic credit allocation,
abstain handling) + verdict edge cases (exact threshold, quorum boundary, ties → each tieBreak).

### Module C — `src/crypto/`  (commitment + signing)  ·  agent: phase2-crypto
Responsibility: canonical serialization, hashing, server signing key, receipt hash-chain.
```ts
export function canonicalize(v: unknown): string          // deterministic JSON: sorted keys, no insignificant whitespace
export function sha256hex(s: string | Buffer): string
export function computeSetupCommitment(parts: SetupParts): string  // H(canonical(options‖method‖rule‖ballotMode‖resultsPolicy‖rosterCommitment‖issuerPubKeyHash?‖schedule))  — issuerPubKeyHash null in Phase 2
export function loadOrCreateServerKey(dir: string): {publicKeyPem: string; sign(msg: string): string; }   // Ed25519
export function verifySig(publicKeyPem: string, msg: string, sigB64: string): boolean
export function chainNext(prevHead: string, ballotHash: string): string   // domain-separated sha256(prevHead‖ballotHash); genesis = sha256('tessera:genesis:'+decisionId)
```
TDD: canonicalize key-order/whitespace invariance; commitment stability across field reorder;
Ed25519 sign/verify roundtrip + tamper-detection; chain determinism + order-sensitivity.

### Module D — `src/domain/`  (entities + lifecycle)  ·  agent: phase2-domain
Responsibility: TS types for §9 entities + the lifecycle state machine + ballot-payload schemas.
```ts
export enum DecisionState { draft, open, closed, challenge, published, cancelled }   // open mode skips 'registration' (Phase 3 secret-mode only)
export type BallotMode = 'open'|'secret'; export type ResultsPolicy = 'sealed'|'live';
export function canTransition(from: DecisionState, to: DecisionState): boolean        // draft→open→closed→challenge→published; any pre-publish→cancelled; open→open = 'extend'
export const DecisionCreate: ZodSchema; export const BallotPayloadSchema: (method) => ZodSchema   // validates per-method payloads the tally oracle consumes
```
TDD: every legal transition allowed; representative illegal ones rejected; payload validation
per method (well-formed pass, malformed reject); abstain encoded distinctly (P4).

### Layer 1 — `src/auth/`  ·  agent: phase2-auth  (depends on Module A's `AccountRepo`/`sessions`)
Bootstrap admin token: generated on first run, **printed once to logs**, stored **hashed**.
Per-convener bearer tokens. `requireConvener` Express middleware. Builds against A's repo
interface (contract above) → can start in parallel, integrates after A merges.
TDD (supertest): no/invalid token → 401 (signed error); valid bootstrap token → mints a
convener token; convener routes gated.

### Layer 2 — `src/routes/` + integration  ·  orchestrator (or single agent), AFTER A–E merged
- `routes/convener.ts`: `POST /decisions` (compute `setupCommitment`, state=draft) ·
  `/decisions/:id/{open,close,publish,extend,cancel}` (guarded by `canTransition`, each writes a
  **signed** `LifecycleEvent`) · `GET /decisions/:id/turnout` (count only; coarse buckets if secret — Phase 2 open).
- `routes/participant.ts`: `GET /d/:id` · `POST /ballots` (zod-validate payload; check eligibility;
  `idempotencyKey` required; ballot+receipt commit in ONE txn; retry → same receipt; late cast → signed "closed").
- `routes/public.ts`: `GET /decisions/:id` (metadata+commitment+trust level) · `GET /ballots?after=&limit=`
  (cursor, page hash + leaf count) · `GET /root` (current head) · `GET /results` (recompute via tally oracle;
  non-authoritative) · `GET /anchor` (Phase 2: `{mode, head}`; full status Phase 3).
- Wire routers + a `db` singleton into `createApp(db)`; `index.ts` opens the DB from `DATA_DIR`,
  runs `migrate`, prints the bootstrap token. **Error model:** stable codes; `decision-closed` /
  `ineligible` rejections are server-**signed** (exhibitable; §10).

## Exit criteria (Phase 2)
- e2e (supertest): create → open → cast×N (one duplicate idempotencyKey → same receipt) → close →
  publish; `GET /results` verdict matches an independent hand-tally; receipt resolves under `/root`.
- `npm run typecheck` clean; `npm test` green; `dev-stack.sh up` serves the flow; one-command deploy.
- No blind-sig / anchor / verifier code present (those are Phase 3).

## Parallel execution strategy
1. **Orchestrator seeds `redesign/phase2-server`**: add deps (`better-sqlite3`, `@types/better-sqlite3`,
   `zod`) to `package.json` + install + commit; commit this plan. (Agents never touch `package.json`.)
2. **Fan out (background, worktree each):** A `phase2-db`, B `phase2-tally`, C `phase2-crypto`,
   D `phase2-domain`, E `phase2-auth` — all branched from the seeded commit. Each: TDD its module to
   green (`npm test` for its files), commit on its branch. Disjoint dirs → conflict-free.
3. **Integrate (orchestrator):** merge A–E into `redesign/phase2-server`; build `src/routes/*` + wire
   `app.ts`/`index.ts`; write the e2e; `typecheck` + `test` green.
4. **Verify + PR:** full server suite green; open the Phase 2 PR stacked on #133. Delete module worktrees.
