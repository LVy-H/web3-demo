# Live Meeting Vote — Sprint 0 + Sprint 1 Implementation Plan

**Status:** Ready to execute (pending the phase-machine product call — see Findings #2).
**Date:** 2026-05-31.
**Source spec:** [`../specs/2026-05-31-live-meeting-vote-agile-plan.md`](../specs/2026-05-31-live-meeting-vote-agile-plan.md)
**How produced:** multi-agent planning workflow (`wf_42bc343d-368`) — one planner + one adversarial verifier per story, then synthesis. The riskiest stories (S1.4, S1.6) received full structured adversarial verdicts; the remainder were synthesized from direct code-reading. Execute the un-verdicted stories (S0.3, S1.3, S1.5, S1.7) with extra care.

---

## Verification findings (read first)

1. **S0.1 and S0.2 are already implemented** in the now-committed Dark Bauhaus work — treat them as *verify only*, not new code:
   - **S0.2:** `useGroupSync.ts` exists, is imported/used in `Poll.tsx` (lines 9, 156), and explicitly replaces the old module-scope `let group` / `let isGroupSynced`. No module-scope mutable state remains in `Poll.tsx`.
   - **S0.1:** the nullifier key is already per-poll **and** per-commitment: `my-nullifier-${pollAddress}-${commitment}` (Poll.tsx:108, 305, 371), with a legacy-key sweep.

2. **🚩 BLOCKER — Registration/Voting mutual exclusion.** `ZkAnonVoting.registerVoter` reverts unless `state == Registration`; `castVote` reverts unless `state == Voting` (`ZkAnonVoting.sol:123` vs `:172`). The two can never be valid at once. The design's interleaved "confirm voters while the tally moves live" is therefore **infeasible with no contract changes**. The live host is re-modeled as an explicit **sequential phase machine**: *Registration* (Confirm/Reject + register) → **Start Voting** → *Voting* (tally moves) → **End Voting**. Consequence: **no continuous late-join once voting opens.** (This is also the cryptographically sound choice — changing Semaphore group membership mid-vote would disturb the Merkle root that in-flight proofs are built against.)

3. **Lint baseline is already RED.** `npm run lint` (whole-package `eslint .`) in `codes/frontend` already fails on committed files (`useBlindVote.ts`, `useGroupSync.ts`, `Countdown.tsx`, `Home.tsx`, `Poll.tsx`). Every story's lint gate is therefore **scoped to its own new/touched files**, not the whole package.

---

## Prerequisites

> **STOP — read before touching any code.**

### P-0 (was BLOCKING — now SATISFIED): Dark Bauhaus WIP committed

The `dev/lvh` working tree was dirty with in-flight Dark Bauhaus UI work; both Sprint 0 fixes live inside it. **This has been committed** (`b5ae2a2`, `85ddd94`, `c458ad9`) and `git status` is clean. Keep it clean — settle any new WIP before starting a story whose files (`CreatePoll.tsx`, `App.tsx`, `Poll.tsx`) it touches.

### P-1: Lint baseline is already RED — scope every lint gate to touched files

- Every frontend story's lint gate runs against its own files (e.g. `npx eslint src/lib/ticket.ts src/lib/confirmationCode.ts src/lib/orgKeypair.ts`). New files must satisfy `typescript-eslint` recommended + `react-hooks`.
- The **relayer has no lint script.** Either add `"lint": "eslint ."` + config to `codes/relayer`, or treat lint as N/A there and use `npm run build` (`tsc`) as the gate — state the choice, don't swap silently.

### P-2: Runtime prerequisites for live-mode dev / demo / E2E

Bring up in order, in separate terminals:
1. **Hardhat node** — `http://127.0.0.1:8545` (frontend `config.ts` only permits hardhat/localhost chain IDs).
2. **`deploy:local`** — deploy `PollRegistry` + contracts so the frontend has live addresses.
3. **Relayer** (`codes/relayer`) — requires `RELAYER_PRIVATE_KEY` in env (`config.ts` throws at import if unset; tests set a throwaway key). `npm run dev`.
4. **Frontend dev server** (`codes/frontend`) — `npm run dev`.

The mock "Test Account" `0xf39F…2266` is Hardhat account #0 (default deployer/owner), so a poll it deploys passes the owner gate.

### P-3: Architecture invariants (hold across ALL stories)

- **`registerVoter` / `registerVoters` are `onlyOwner`** (`ZkAnonVoting.sol:122/133`). The **organizer's MetaMask wallet owns the poll and is the only thing that can register voters.** The relayer never calls register. The per-poll org **ticket-signing key is a SEPARATE ed25519 key** in localStorage — never conflated with the MetaMask wallet.
- **NO contract changes** in Sprint 0 or Sprint 1.
- **The relayer HTTP API is the cross-client boundary** (spec §2.5). Every relayer endpoint added/changed gets a **versioned API-reference** doc entry. Keep relayer calls inside typed hooks (`useLiveQueue`), not scattered `fetch`es, so a future Flutter client reuses the same contract.
- **Registration and Voting are mutually-exclusive on-chain states** (Finding #2). The live host is a **sequential phase machine**, not an interleaved loop.

---

## Sprint 0 — De-risk & foundation

**Sprint goal:** Confirm the two P0 fixes on the live path are sound, and prove the organizer-owned registration loop on local Hardhat before any UI is built on it.

### 1. S0.1 — Per-poll nullifier scoping (P0-1) — *already implemented — verify only*

- **Goal:** Voting on poll A must not block the vote UI on poll B; the "already voted" flag is keyed per-poll (and per-commitment).
- **Files:** `codes/frontend/src/pages/Poll.tsx` (read-only verify — fix already present).
- **Steps:**
  1. **Verify:** confirm the nullifier key is `my-nullifier-${pollAddress}-${commitment}` (Poll.tsx:108, 305, 371) and the legacy unscoped key is swept (Poll.tsx:107, 183, 461).
  2. **Manual/E2E:** vote on poll A, navigate to poll B → vote UI available on B.
  3. Only if verify fails: write a failing E2E asserting B is votable after A, then fix the key.
- **Acceptance:** Cross-poll independence holds; key is per-poll+per-commitment. (Currently satisfied — record as verified.)
- **Depends on:** P-0.

### 2. S0.2 — Group-sync state inside React (P0-2) — *already implemented — verify only*

- **Goal:** No module-scope mutable state leaks across poll navigation; group-sync lives in a hook.
- **Files:** `codes/frontend/src/hooks/useGroupSync.ts` (exists), `Poll.tsx` (read-only verify).
- **Steps:**
  1. **Verify:** `useGroupSync.ts` exists and replaces module-scope `let group`/`let isGroupSynced`; `Poll.tsx` imports/uses it (9, 156); it exposes `sync`/`reset`, rebuilds the Group from `VoterRegistered` logs, resets on `pollAddress` change; `Poll.tsx` has no module-scope `let`/`var`.
  2. Run existing Playwright E2E → no regression.
- **Acceptance:** No module-scope mutable state in `Poll.tsx`; group logic in `useGroupSync`; existing E2E passes.
- **Depends on:** P-0. (Independent of S0.1, but both read `Poll.tsx`.)

### 3. S0.3 — Spike: prove organizer-owned registration loop on local Hardhat

- **Goal:** Demonstrate end-to-end with **no contract changes**: organizer wallet (owner) `registerVoter` an ephemeral commitment → `startVoting()` → relayer relays that identity's `castVote` → tally updates.
- **Files:** a throwaway `codes/contracts/scripts/spike-live-loop.ts` or a Hardhat test; no production files.
- **Steps:**
  1. `deploy:local`. As owner: `registerVoter(commitment)` for one ephemeral identity → assert `registeredCommitments(commitment) == true`.
  2. `startVoting()` → generate a Semaphore proof → submit `castVote` **through the relayer** (`POST /api/relay/vote`) → assert tally increments via `getResults()`.
  3. **Document the Registration→startVoting→Voting ordering constraint** that S1.4/S1.6 inherit.
- **Acceptance:** full loop runs with no contract changes; the phase-ordering surprise is documented. *(A passing sequential spike does NOT validate an interleaved "confirm while bars move" UX — that interleave is unsupported; document this caveat.)*
- **Depends on:** P-2. Sequence after S0.1/S0.2 verify.

### Review checkpoint (Sprint 0)

Existing async flows still work; vote-on-A then navigate-to-B shows the vote UI on B; `Poll.tsx` has no module-scope mutable state; the S0.3 spike runs register → startVoting → relayed vote → tally green on local Hardhat with zero contract changes; the phase-ordering surprise is captured. No new P0 introduced.

---

## Sprint 1 — Live MVP ("Phase A")

**Sprint goal:** A working end-to-end live vote loop demoable across two browsers, modeled as an explicit **Registration→Voting phase machine** (NOT an interleaved loop), including the live "reject the cheater" moment during Registration.

> **Cross-story contracts locked once here (thread everywhere):**
> - **Signing primitive = ed25519 via `@noble/curves/ed25519`** (the design doc's standalone `@noble/ed25519` is NOT installed; `@noble/curves` exports `./ed25519` with a sync API). S1.2's server-side verify reuses the exact byte format.
> - **Canonical encodings** (S1.1 owns; S1.2 + Flutter reuse byte-for-byte): ticket signed over a **fixed-width deterministic preimage** (never `JSON.stringify`); confirmation code = `SHA-256(nonceBytes ‖ commitment-32-byte-BE)`, first 16 bits, mod 10000, zero-padded to 4.
> - **Relayer endpoint prefix = the existing `/api/relay/*`**, behind the **existing rate-limiter instance** (don't create a second). Define all four ticket endpoints' shapes ONCE in S1.2.
> - **`/tickets/issue` is NOT server-side signing.** The org private key stays in the browser; `issue` **registers the org PUBLIC key** (verification anchor) keyed by pollId; server verify checks tickets against that stored key.
> - **Two distinct gating mechanisms:** the **host** reads the org-authed `GET /api/relay/tickets/queue`; the **wallet-free voter** gates enablement on an **on-chain read of `registeredCommitments(commitment)`** (public getter) — the voter cannot read the org queue.
> - **Vitest** is the new unit-test runner for both `codes/frontend` and `codes/relayer` (neither has one today).

### 1. S1.1 — Client libs: `ticket.ts`, `confirmationCode.ts`, `orgKeypair.ts` (+ Vitest harness)

- **Goal:** Pure, unit-tested libs: sign/verify/encode/decode expiring tickets; derive the deterministic 4-digit code; manage a per-poll ed25519 ticket-signing keypair in localStorage.
- **Files:**
  - `codes/frontend/package.json` — add devDep `vitest` (peer vite ^6||^7||^8; installed is 8.x) + scripts `test`/`test:watch`; add explicit deps `@noble/curves`, `@noble/hashes`, `@scure/base` (pin to resolved transitive versions).
  - `codes/frontend/vitest.config.ts` — NEW. `environment 'node'`, `include ['src/**/*.test.ts']`, `globals: false`.
  - `codes/frontend/tsconfig.app.json` — add `"exclude": ["src/**/*.test.ts"]` so production build doesn't ship tests.
  - `codes/frontend/tsconfig.node.json` — add `vitest.config.ts` to `include`.
  - `src/lib/ticket.ts` — NEW. Side-effect-free. `Ticket = { p: 20-byte addr hex, n: 8 random bytes, e: unix s }` + signed wire form. `encodeTicket`/`decodeTicket` (fixed-width preimage), `signTicket(payload, privKey)→base64url`, `verifyTicket(encoded, pubKey, now?)→{valid, reason?:'expired'|'badSig'|'malformed', ticket?}`. `TICKET_TTL_SECONDS = 30`. Inject `now`. Use `export type`/`import type`.
  - `src/lib/confirmationCode.ts` — NEW. `confirmationCode(nonce, commitment): string` per the locked encoding. Deterministic, no I/O.
  - `src/lib/orgKeypair.ts` — NEW. `generateOrgKeypair`/`saveOrgKeypair`/`loadOrgKeypair`/`getOrCreateOrgKeypair(pollId)`. localStorage `org-keypair-${pollId}`; injectable `Storage`; try/catch like Poll.tsx:28–34. This is the ticket-signing key, distinct from MetaMask.
  - `src/lib/{ticket,confirmationCode,orgKeypair}.test.ts` — NEW.
  - spec doc — record the Vitest + ed25519-via-`@noble/curves` + canonical-encoding decisions.
- **Steps (TDD):**
  1. **Harness first:** Vitest + scripts + deps + `vitest.config.ts` + tsconfig edits → `npm run test` runs (0 tests).
  2. **`confirmationCode.test.ts` then implement:** determinism; `/^[0-9]{4}$/`; voter/organizer re-derivation agree; different inputs generally change the code.
  3. **`ticket.test.ts` then implement:** valid verifies + round-trips when `now<e`; `now>e`→`'expired'`; tamper/wrong-key→`'badSig'`; garbage→`'malformed'` (no throw).
  4. **`orgKeypair.test.ts` (inject in-memory Storage) then implement:** generate→sign+verify e2e; save→load identical; unknown pollId→null; `getOrCreate` idempotent + per-poll isolated; corrupt→null no throw.
  5. `npm run test` green; scoped eslint of new files (P-1). Add the doc note.
- **Acceptance:** valid verifies & round-trips; expired→`'expired'`; forged→`'badSig'`; malformed→invalid no throw; same `(nonce, commitment)`→same 4-digit code both sides; per-poll keypair persists/loads, `getOrCreate` idempotent + isolated, corrupt/absent→null; `npm run test` green; scoped lint passes; no contract/relayer changes. *(Whole-package lint acceptance DROPPED per P-1.)*
- **Depends on:** P-0, P-1. Foundation layer.

### 2. S1.2 — Relayer: pending-voter queue + ticket endpoints

- **Goal:** In-memory pending-voter queue, consumed-tickets set, and the four ticket endpoints — behind the existing limiter, under `/api/relay`, reusing S1.1's ticket format for server-side verify.
- **Files:**
  - `codes/relayer/src/tickets.ts` — NEW. Per-poll: pending queue `[{ticketNonce, ephemeralIdentityCommitment, confirmationCode, status, createdAt}]`, `consumedTickets: Set` keyed `${pollId}:${nonce}`, org-pubkey map keyed by pollId (set by `issue`). Pure validators returning `{ok,data}|{ok,error}` (mirror `validation.ts:45–94`). `decodeTicket` + `verifyTicketSignature(ticket, storedOrgPubKey)` + expiry, reusing S1.1's bytes. `express.Router()` with `issueRegisterPubkey`/`addPending`/`getQueue`/`redeemTicket`. Keep free of `config`/wallet imports (pure tests need no env).
  - `codes/relayer/src/index.ts` — MODIFY. Mount the router under the existing prefix behind the **same** limiter, after `express.json()` (index.ts:16). Refactor to `createApp()` (no `app.listen` side effect) imported by listener + tests. Mirror the error contract (400 on `!ok`; try/catch→500; `[TICKETS]` log tag).
  - `codes/relayer/package.json` — MODIFY. Add devDeps `vitest`, `supertest` (+types) + `test` script. Add a `lint` script + config OR state lint N/A and use `tsc` build (P-1).
  - `codes/relayer/test/setup.ts` — NEW. Set throwaway `RELAYER_PRIVATE_KEY` before any `config`/app import (config.ts:4–10 throws at import). Vitest `setupFiles`.
  - `codes/relayer/test/tickets.test.ts` — NEW. Unit + supertest.
  - `codes/relayer/README.md` — MODIFY. Versioned API reference for the four endpoints, the in-memory state-lost-on-restart trade-off, and the note that registration is **organizer-wallet-owned, not the relayer's**.
- **Steps (TDD):**
  1. **0.5 — env/harness first:** Vitest + supertest + `test/setup.ts` + `createApp()` split → trivial spec runs.
  2. **Ticket-integrity test then implement** verify/expiry: reject expired; reject forged (flip a sig byte); accept valid against the **stored** org pubkey, NOT a request-body pubkey. Use an S1.1 fixture vector.
  3. **Validator tests then implement** (use `ethers.isAddress` for pollId): reject pending missing `confirmationCode`; reject issue with invalid pollId; `.ok===false` + descriptive `.error`.
  4. **Consumed-set test then implement** redeem: first redeem of `${pollId}:${nonce}` marks consumed + flips queue to `confirmed`; second redeem → 409.
  5. **Queue test then implement** `addPending`+`getQueue`: pollA returns only pollA's pending entries.
  6. **Supertest integration then mount:** `/api/relay/tickets/redeem` rejects reuse e2e; `GET …/queue` returns pending over HTTP; optionally assert rate-limiting.
  7. README API reference + trade-off note. `npm test` + relayer gate green.
- **Acceptance:** four endpoints under `/api/relay/tickets/*` respond (supertest); all behind the existing limiter; a redeemed `(pollId, nonce)` can't be reused; `GET …/queue?pollId=X` returns only X's pending; forged/expired rejected against the stored pubkey; NO contract changes and the relayer does NOT call `registerVoter`; README documents the four endpoints; gates pass. *("issue mints a signed ticket" REWORDED: issue registers the org public verification anchor, rate-limited — signing stays client-side.)*
- **Depends on:** **S1.1** (ticket format/signing/encoding — byte-for-byte). Informed by **S0.3**.

### 3. S1.3 — "Live Meeting Mode" toggle on CreatePoll

- **Goal:** A toggle that deploys an M1 (`ZkAnonVoting`) poll the organizer owns and redirects to `/live/:pollId/host`; non-live deploys unchanged.
- **Files:** `codes/frontend/src/pages/CreatePoll.tsx` (MODIFY). On live deploy, `getOrCreateOrgKeypair(pollId)` (S1.1) + `POST /api/relay/tickets/issue` `{pollId, orgPubKey}`, then `navigate('/live/${pollAddr}/host')`.
- **Steps (TDD):**
  1. Failing E2E/component check: toggle + deploy lands on `/live/:pollId/host`; toggle off → existing path unchanged.
  2. Implement the toggle, the M1 deploy branch, `getOrCreateOrgKeypair` + `POST …/tickets/issue`, redirect.
  3. Scoped lint.
- **Acceptance:** live toggle deploys an owned M1 poll, registers the org pubkey, redirects to host; non-live unchanged; scoped lint passes.
- **Depends on:** **S1.1**, **S1.2** (can build against a stubbed issue call until S1.2 lands).

### 4. S1.4 — LiveHost projector page + components + `useLiveQueue` — *as a sequential phase machine*

- **Goal:** `/live/:pollId/host` with rotating QR, pending-voter queue (Confirm/Reject), live tally, and **explicit Start Voting / End Voting controls**. Confirm/Reject in **Registration**; tally moves in **Voting**; never interleaved.
- **Files:**
  - `src/hooks/useLiveQueue.ts` — NEW. Polls `GET /api/relay/tickets/queue?pollId=` (one consistent timeout style) ~2s; returns `{ queue, isLoading, error, refresh, remove(commitment), confirmVoter(commitment) }`. `PendingVoter = { commitment, confirmationCode, nonce, ticket, proximityVerified? }`. `remove()` optimistically drops a row (Reject = client-side, no chain call). Degrade to empty+error when the relayer is down. **All relayer calls live here** (portability boundary).
  - `src/components/live/RotatingQR.tsx` — NEW. Props `{ pollId, makeTicket(), refreshMs=25000 }`. `react-qr-code` value `${origin}/live/${pollId}/vote?t=${ticket}`. Re-mint every `refreshMs`; 1s countdown; clear interval on unmount. `data-testid='rotating-qr'`. Build against a `makeTicket` stub so it ships before S1.1 is wired.
  - `src/components/live/PendingVoterList.tsx` — NEW. Pure presentational. `{ voters, onConfirm, onReject, confirmingCommitment }`. Projector-legible 4-digit code per row; Confirm + Reject (min-h-44px, db-* tokens); spinner+disable while confirming; empty state.
  - `src/components/live/LiveTally.tsx` — NEW. `{ pollAddress }`. Seed from `usePollResults` + `usePollOptions`; `useWatchContractEvent({eventName:'VoteCast', onLogs})` → **trigger `getResults` refetch** (http transport polls; don't raw-increment — avoids double-count; matches `useRegistry.ts`). Existing 3s poll is a backstop. Renders `<ResultsBarsDb …/>`.
  - `src/pages/LiveHost.tsx` — NEW. `:pollId` route param is the poll **address** (`0x${string}`). Owner gate: `usePollOwner(pollId)` vs `useAccount().address`, **case-insensitive**; if not owner, show "connect the organizer wallet that owns this poll" + hide Confirm. Composes RotatingQR (stub→S1.1), PendingVoterList (via `useLiveQueue`), LiveTally, display-only TimeRemaining, and **`Start Voting` / `End Voting` controls** (copy `startVoting`/`endVoting` from Poll.tsx:400/412). **Phase lifecycle:** Registration (Confirm/Reject; tally zero/seeded) → **Start Voting** (`registerVoter` now blocked) → Voting (tally moves) → **End Voting** (requires `state==Voting`). **Do NOT call `groupSync.reset()` here** (group re-sync belongs on the voter page).
  - `src/App.tsx` — MODIFY. Add `<Route path="/live/:pollId/host" element={<LiveHost/>} />` + import.
  - `codes/frontend/e2e/08-live-host.spec.ts` — NEW. Scoped to the mockable surface only.
- **Steps (TDD):**
  1. **Failing E2E first** (`08-live-host`): route-mock `**/api/relay/tickets/queue*` → two pending voters; assert mockable facts only. Red.
  2. Add the route + a minimal LiveHost stub so navigation resolves.
  3. `useLiveQueue` (poll queue; degrade to empty+error on 500).
  4. `PendingVoterList` (rows, 44px buttons, spinner on `confirmingCommitment`, empty state); wire in.
  5. `RotatingQR` (absolute `/live/<addr>/vote?t=…`, re-mint on shortened `refreshMs`, countdown, clear timers on unmount); `makeTicket` stub.
  6. `LiveTally` (seed from results, VoteCast→refetch, render `ResultsBarsDb`).
  7. Owner gate + **Start/End Voting** controls + TimeRemaining. Confirm/Reject wired (Confirm detail in S1.6; here stubbed to `confirmVoter`). Reject → `remove` only.
  8. Scoped lint (`src/components/live src/hooks/useLiveQueue.ts src/pages/LiveHost.tsx`) + spec; green.
- **Acceptance:** rotating QR re-mints its `/live/:pollId/vote?t=<ticket>` URL (~25s) with a visible countdown; pending list renders one row per voter with the code + Confirm/Reject; **Start/End Voting** controls drive the phase; in Registration, Reject drops a voter with **no tx**; page owner-gated (case-insensitive); LiveTally seeds from `getResults` + updates on `VoteCast` without reload; display-only TimeRemaining; NO contract changes; scoped lint + `08-live-host` pass. *(DROPPED: the interleaved "Confirm registers AND bars move in one phase" — impossible under `NotInRegistration`/`NotInVoting`; the E2E does not do in-test deploy + real register + real cast in one spec — that's the S0.3 spike / manual demo.)*
- **Depends on:** **S1.1** (real ticket — stubbed until then), **S1.2** (queue — route-mocked in E2E), **S1.3** (route to the page). Confirm-handler detail in **S1.6**.

### 5. S1.5 — Wallet-free voter page (LiveVote)

- **Goal:** Zero-install voter flow at `/live/:pollId/vote`: verify the ticket, mint an ephemeral Semaphore identity, show the big 4-digit code, **poll for on-chain confirmation**, then question + options → tap → client-side ZK proof → relayer `castVote` → receipt modal. No wallet.
- **Files:**
  - `src/pages/LiveVote.tsx` — NEW. Read `?t=<ticket>`; `verifyTicket` (S1.1) → expired/forged shows "code expired, get a fresh QR". Mint `new Identity()`; `confirmationCode(nonce, identity.commitment)`; `POST /api/relay/tickets/pending` `{pollId, ticket, ephemeralIdentityCommitment, confirmationCode}`. Show the big code. **Gate on TWO on-chain reads — `registeredCommitments(commitment)` AND `getState()` — as a THREE-state machine** (NOT the org queue, never local optimistic state):
    1. `!registered` → **"waiting for confirmation"** (big code shown).
    2. `registered && state == Registration` → **"confirmed — waiting for the organizer to open voting"** (do NOT show options yet; `castVote` would revert `NotInVoting`).
    3. `registered && state == Voting` → **only now** re-sync **this page's** group (`useGroupSync` here — the Merkle root is frozen once registration closes, so the membership proof is valid) → render options → tap → proof → `POST /api/relay/vote` → ReceiptModal (reuse).
    Syncing the group in state 2 would build a proof against a stale root that keeps changing as more voters are confirmed — that's why the group-sync is deferred to state 3 (same root-freezing argument as spec §2.2 #3, applied to the voter).
  - `src/components/live/ConfirmationCode.tsx` — NEW. Big code + animation.
  - `src/App.tsx` — MODIFY. Add `<Route path="/live/:pollId/vote" element={<LiveVote/>} />`.
- **Steps (TDD):**
  1. Failing E2E (folded into S1.7 or focused): valid `?t=` → mint identity, show 4-digit code, stay "waiting" until `registeredCommitments` reads true.
  2. Ticket verify + identity mint + code display + `POST …/tickets/pending`.
  3. Implement the **three-state gate**: poll `registeredCommitments(commitment)` AND `getState()`. State 2 (`registered && Registration`) shows "confirmed — waiting for the organizer to open voting" (no options). **Only in state 3 (`registered && Voting`)** do the group re-sync + render options.
  4. Tap → proof → `POST /api/relay/vote` → receipt; friendly errors.
  5. Scoped lint.
- **Acceptance:** on a second browser, scan → code → (after on-chain confirm) → tap → vote lands → receipt, **no wallet**; expired/forged → graceful "get a fresh code"; enablement driven by the **on-chain reads** (`registeredCommitments` + `getState`), never local optimistic state; the vote UI appears **only when `registered && state == Voting`** — while `registered && Registration` the page shows the "waiting for the organizer to open voting" state and never lets a tap reach `castVote` (which would revert `NotInVoting`); the group is synced **only after voting opens** (proof built against the frozen root); scoped lint passes.
- **Depends on:** **S1.1**, **S1.2**. Buildable against mocks before S1.6.

### 6. S1.6 — Wire organizer-owned on-chain registration on Confirm

- **Goal:** Confirm registers the voter on-chain from the **organizer's own wallet** (`registerVoter(commitment)`) during **Registration**; the voter's page flips to enabled **only after the tx is mined**; the relayer marks the ticket consumed exactly once on redeem.
- **Files:**
  - `src/hooks/useLiveQueue.ts` — MODIFY. `confirmVoter(commitment)`: (a) `writeContractAsync({address: pollAddr, abi, functionName:'registerVoter', args:[commitment], gas: <override like Poll.tsx's 15000000n>})` — **single scalar arg, NOT an array**; (b) **await a per-tx `publicClient.waitForTransactionReceipt({hash})`** (mirror Poll.tsx:294–303) — drive per-voter state from THAT, not `usePollWrite`'s shared `isConfirming`/`isSuccess` (racy across a multi-voter queue); (c) then `POST /api/relay/tickets/redeem`. Treat `AlreadyRegistered()` (ZkAnonVoting.sol:124) as success (read `registeredCommitments` to confirm) so retry is idempotent. Never flip to enabled on tx send.
  - `src/components/live/PendingVoterList.tsx` — MODIFY. Confirm → `confirmVoter`; disable unless connected wallet === `usePollOwner(pollId)`; "Registering on-chain…" while pending; flip on receipt. Reject leaves un-registered + drops the row.
  - `src/pages/LiveVote.tsx` — MODIFY. Enablement is the **three-state gate** (S1.5): `registeredCommitments(commitment)` + `getState()` on-chain — NOT the org queue, not local state. The vote UI unlocks only in state 3 (`registered && Voting`); group-sync deferred to that state.
  - `codes/relayer/src/tickets.ts` — MODIFY. On redeem, move ticket pending→consumed + surface state. Pin redeem payload jointly with S1.2. **This overrides the design doc's `/relay/register`** — registration is the organizer's browser wallet (the owner); a relayer-driven `registerVoter` would revert `OwnableUnauthorizedAccount`. Document the override.
  - `codes/relayer/test/tickets.test.ts` — MODIFY. Redeem marks consumed exactly once; replay rejected; status reflects consumed only post-redeem.
  - `codes/relayer/README.md` — MODIFY. Redeem semantics + `/relay/register` override.
- **Steps (TDD):**
  1. **Confirm dependencies landed** (S1.2 endpoints+consumed set, S1.4 PendingVoterList+Confirm point, S1.5 LiveVote+useLiveQueue). If any missing, STOP — S1.6 is pure wiring.
  2. Relayer redeem test then implement: consumed exactly once; replay rejected.
  3. `confirmVoter` (single-arg register, per-tx `waitForTransactionReceipt`, then redeem; `AlreadyRegistered`→idempotent success).
  4. Wire Confirm (owner-gated; "Registering…"; flip on receipt). Reject → drop only.
  5. Wire LiveVote enablement to the on-chain read.
  6. Scoped frontend lint + relayer gate; README + plan-doc notes.
- **Acceptance:** voter page stays "waiting" and flips to enabled **only after** the organizer's `registerVoter` tx is mined (per-tx receipt), driven by the on-chain `registeredCommitments` read; Confirm calls `registerVoter` from the owner wallet (onlyOwner, zero contract changes) during Registration; on confirmation the relayer marks the ticket consumed and a second redeem is rejected; Reject sends no tx and never enables; Confirm graceful for a non-owner wallet; `AlreadyRegistered` idempotent; relayer change documented; gates pass. *(DROPPED: gating the voter on the org-authed `GET /tickets/queue`; using `usePollWrite`'s shared `isSuccess` for the per-voter gate.)*
- **Depends on:** **S1.2, S1.4, S1.5** (poll must stay in **Registration** during the confirm window), transitively **S1.1**; **S0.3** green first.

### 7. S1.7 — Two-context E2E (organizer + voter): happy + reject

- **Goal:** A Playwright spec running an organizer context (MetaMask owner) and a voter context (wallet-free), covering happy + reject under the sequential phase machine.
- **Files:** `codes/frontend/e2e/09-live-two-context.spec.ts` — NEW (synpress MetaMask config). May absorb the focused S1.5/S1.6 specs.
- **Steps (TDD):**
  1. **Happy path:** organizer creates/owns a live M1 poll → host; voter scans the `/vote?t=` URL → code → disabled; organizer Confirms (real `registerVoter`) → voter's `registeredCommitments` flips → **assert the voter now shows "waiting for the organizer to open voting" with NO options visible** (guards the three-state bug — see S1.5; without this assertion the test passes even if the voter wrongly shows options in Registration) → organizer **Start Voting** → voter taps → relayed `castVote` → tally moves → organizer **End Voting**.
  2. **Reject path:** a "friend not in the room" scans, gets a code; organizer Rejects → no tx → that voter never enables.
- **Acceptance:** both contexts run; happy path tallies one vote through Registration→Start Voting→Voting; reject path leaves the voter blocked with no tx; no contract changes.
- **Depends on:** **S1.4, S1.5, S1.6** (+ S1.1/S1.2/S1.3 transitively).

### Review checkpoint (Sprint 1)

Demo the **sequential** 60-second meeting script: create a Live Meeting poll → projector host page → two voters scan, show codes → organizer Confirms each face-to-face (wallet registers each on-chain; each voter enables only after the tx mines) → a "friend not in the room" scans, organizer can't find them → **Reject** (no tx, permanently blocked) → organizer **Start Voting** → confirmed voters tap → **tally bars move live** → organizer **End Voting**.

Verify: S1.1 Vitest green; S1.2 endpoints documented + behind the existing limiter, reuse blocked; the host is an explicit Registration→Voting phase machine (register/cast never interleave); the wallet-free voter gates on the on-chain `registeredCommitments` read; the two-context E2E passes happy + reject. Re-check the Pain-Point Analysis: voter-complexity, eligibility-without-PII, and QR-resharing pains moved; no new P0; the relayer in-memory state-loss-on-restart trade-off documented (open Q3).
