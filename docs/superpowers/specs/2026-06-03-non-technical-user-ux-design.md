# Non-technical-user UX — sponsored (wallet-free) poll lifecycle + plain language

Status: full-stack epic plan (contract gate + relayer endpoints + Flutter create/join rework + plain-language sweep + onboarding).
Date: 2026-06-03
Module / surface: relayer (`create-poll`, `register-voter`), Flutter create + join flows, all jargon-bearing screens.

> The product mandate (verbatim intent): *"This is for non-tech users, not some
> behemoth crypto obsession — make the use as at-ease as possible."* Concretely:
> **a non-technical user must CREATE a poll with NO wallet** (the relayer creates
> on their behalf — sponsored), and **anyone must be able to open a shared link
> and vote with NO wallet, NO gas, NO seed phrase**. The decision is already
> made by the user: **the relayer sponsors the whole lifecycle** (create +
> register + vote); the wallet becomes a hidden "Advanced" path. This spec turns
> that decision into an implementable, sequenced plan, and surfaces the **one**
> contract-level obstacle the mandate runs into so a reviewer can resolve it
> before any code is written.

---

## Decisions & alternatives (read this first)

Five forks are settled here. Each is a crisp either/or with the chosen option
marked **CHOSEN**, so a human reviewer can redirect the whole plan by flipping a
single decision before code is written. Decision 0 is load-bearing — it gates the
entire async "share-a-link" experience and is the **one call the user must
confirm**; everything else follows from it.

### Decision 0 — How a brand-new user JOINS a sponsored poll (the crux)

> **The contract's two-phase model blocks the literal mandate.** This is the
> headline product call.

Every shipped module (`ZkAnonVoting.sol:120–179`, mirrored in
`ZkApprovalVoting.sol:142–192`, `ZkSurveyVoting.sol:250–335`, ranked, quadratic)
is a strict two-phase state machine:

- `registerVoter(commitment)` reverts `NotInRegistration` unless `state ==
  Registration` (`ZkAnonVoting.sol:121`).
- `castVote(…)` reverts `NotInVoting` unless `state == Voting`
  (`ZkAnonVoting.sol:165`).
- `startVoting()` is **Registration → Voting, irreversible**, and reverts
  `NeedAtLeastOneVoter` if `participantCount < 1` (`ZkAnonVoting.sol:147–153`).

Three consequences contradict the "tap Join & Vote anytime" narrative:

1. **You cannot auto-`startVoting` at creation** — a fresh poll has zero voters,
   so `startVoting` reverts `NeedAtLeastOneVoter`. "The simplest that lets people
   vote immediately" has no valid answer under the current contract.
2. **Once voting starts, no new voter can register** — registration is closed in
   the `Voting` phase. A newcomer who opens the shared link while the poll is
   *Open for voting* cannot register, and cannot vote without being registered.
3. There is **no single poll state** in which a brand-new user can both register
   AND cast. Voters generate their own Semaphore commitment locally
   (`identity_store.dart`, `vote_view_model.dart:62–83`), so the creator can't
   pre-register people they've never met either.

So the literal mandate — *async share-a-link, anyone votes anytime* — **requires
a contract change**. The relayer alone can only run a *synchronous windowed*
poll, which is the existing live-meeting/ticket flow and locks out late arrivals.

| Option | What it is | Trade-offs |
|---|---|---|
| **0A — Minimal contract change: open self-registration during voting (CHOSEN, pending user confirmation)** | A new sponsored module (or a new init flag on a forked module) lets a registered owner — the relayer — call `registerVoter` while `state == Voting`, OR collapses Registration+Voting into a single "Open" phase where commitments are added lazily on first contact. The relayer remains the gatekeeper (still `onlyOwner`); the difference is purely that registration is no longer phase-locked out. | **The only option that delivers the actual mandate** (async share-a-link, join anytime). Cost: a new/forked module + Hardhat tests + an audit pass, sequenced as **M0 BEFORE** the relayer work. Anonymity is unchanged (still one nullifier per voter; the merkle root simply grows during voting — Semaphore proofs already carry the root they proved against, so late joiners prove against the then-current group). Late-join honesty note: a vote proves membership in *some* root ≤ the cast time; the contract already accepts any historical root Semaphore tracks. |
| 0B — No contract change: relayer-windowed (register in a join window, then sponsored `startVoting`, then voting) | The relayer registers commitments during a creator-controlled join window; when the creator taps "Open voting" (sponsored), the relayer `startVoting`s; thereafter only voting. | Zero contract change, ships fastest. **Fatal for the async use case:** anyone who arrives after "Open voting" is permanently locked out — exactly the non-tech "I got the link an hour late" path. "Join & Vote" degrades to a state-aware **"Join now / vote when it opens"**, and the creator must babysit the window. Acceptable only for scheduled/synchronous polls; it does not satisfy "anyone opens the link and votes." |

**Lean (spec author): 0A** — but the **USER CHOSE 0B (2026-06-03)**: a windowed /
synchronous v1, **no contract change**, ships fastest. So **M0 is DROPPED** and
the implementation follows the **[0B: …]** markers throughout: the relayer
registers commitments during a creator-controlled **join window** while the poll
is in `Registration`; the creator taps **"Start voting"** (sponsored
`startVoting`) to open the ballot; thereafter only voting. "Join & Vote" becomes
the state-aware **"Join now / vote when it opens"**, and the honest limitation —
**anyone who arrives after voting starts is locked out** — is surfaced in-product
(a clear "Voting has started — joining is closed" state), not hidden. The relayer
endpoints, the silent identity, and the entire plain-language sweep are identical
to 0A; only the join UX copy changes.

> Implementation path: **0B (chosen)**. The spec body below describes the 0A
> mechanics for completeness; wherever a **[0B: …]** marker appears, the 0B text
> is authoritative. Milestones start at **M1** (no M0 contract change).

### Decision 1 — Custodial ownership of sponsored polls

> **Relayer-owned (CHOSEN)** vs. per-user app-managed owner key.

| Option | What it is | Trade-offs |
|---|---|---|
| **1A — Owner = the relayer signer (CHOSEN)** | Sponsored polls are owned by the relayer's signer (the same key in `wallet.ts:getRelayerWallet`). The app is the **custodial host**: the relayer registers voters, starts/ends the poll, and pays all gas. | Simplest path to a wallet-free lifecycle — the relayer already holds a funded signer and already sponsors voting. **Trust cost, stated plainly:** the poll is *less decentralized* — the relayer can censor (refuse to register a commitment), close a poll early, or go offline, and the creator has no on-chain recourse. Honest and acceptable for a v1 "at-ease" product; not a trustless system. |
| 1B — Owner = a per-user app-managed key | The app silently generates a second EOA per user, funds it (sponsored), and that key owns the user's polls. | Gives the creator real on-chain ownership, but needs per-user key custody, funding that key (another sponsored-gas surface and abuse vector), and gas-estimation/nonce management on the device — heavy, and reintroduces "a key" the non-tech user must not see. Defeats the simplicity goal for marginal v1 benefit. |

**Recommendation: 1A** for v1 simplicity. The trust trade-off is documented in
*Honesty / trade-offs* below and surfaced in-product as a one-line note on the
creator's "manage poll" view.

### Decision 2 — How a voter gets registered without owning the contract

> **Permissionless registration via a new relayer endpoint (CHOSEN)** vs. a
> permissionless `register()` on a new module.

`registerVoter` is `onlyOwner` (`ZkAnonVoting.sol:120`). With 1A the relayer is
the owner, so:

| Option | What it is | Trade-offs |
|---|---|---|
| **2A — `POST /api/relay/register-voter` (CHOSEN)** | Any user POSTs their Semaphore identity commitment; the relayer (the owner) calls `registerVoter(commitment)` and pays gas. Permissionless from the user's side, owner-gated on-chain. | No new contract surface beyond Decision 0's open-registration change; reuses the exact `registerVoter` the live-host flow already drives (`live_host_repository.dart:67–82`). The relayer becomes the public registration funnel — abuse-guarded per Decision 3. |
| 2B — A permissionless `register()` on a new/blind module (no owner gate) | A new module lets anyone self-add their commitment on-chain (the voter pays, or a meta-tx sponsors). | Heavier: a new contract + the voter needs gas (defeats wallet-free) or a gasless meta-tx standard (out of scope). 2A already achieves permissionless-from-the-user with the relayer paying. |

**Recommendation: 2A.** It is the smallest surface that makes registration
self-service for a wallet-free user.

### Decision 3 — Abuse / rate-limiting for sponsored create + register

> **Reuse + tighten the existing guard, create-specific cap + optional shared
> secret (CHOSEN)** vs. open endpoints (rejected) vs. full anti-spam (out of scope).

Open sponsored create + register is spammable — **the relayer pays gas for every
call**, so a script can drain the relayer's balance or flood the registry with
junk polls. This is real and must not be hand-waved. What already exists to build
on (`app.ts:22–29`): `express-rate-limit` at **20 requests / 60s / IP** across
all of `/api/relay`, and every route gates on `checkRelayerBalance` (refuses
below 0.01 ETH, `relay.ts:262–273`).

**v1 guard (CHOSEN), concretely:**

- **Create is costlier than vote** → a *separate, tighter* limiter on
  `/api/relay/create-poll`: a low per-IP **daily create cap** (e.g. 5/day/IP) on
  top of the global 20/min window, so a single IP cannot mint hundreds of
  sponsored polls.
- **Register** keeps the global limiter; add a per-`(IP, pollAddress)` cap so one
  IP can't spam a single poll's group with thousands of junk commitments
  (commitments are 32-byte opaque values — the relayer can't tell a real voter
  from noise, so cap volume, not content).
- **Optional shared-secret header on create** (`X-Create-Secret`, a build-time
  `--dart-define` / relayer env): when set, create requires it; when unset (local
  dev), create is open. Lets a real deployment gate *who can mint polls* without
  building accounts. Voting/register stay open (the whole point is wallet-free
  participation).
- **Balance floor already enforced** — `checkRelayerBalance` returns 503 below
  0.01 ETH, so the relayer fails safe (stops sponsoring) rather than going
  bankrupt silently. Surface this to the user as a calm "Sponsored creation is
  temporarily paused" message (see §2).

**Explicitly NOT v1 (stated in Out of scope):** captcha/proof-of-humanity,
Sybil-resistant registration, per-poll allow-lists, on-chain meta-tx anti-replay.
v1 is a *light* guard that keeps a casual abuser from draining the relayer; a
production deployment needs more, and we say so.

---

## Summary

Today a non-tech user hits two hard walls. (1) **Creating** a poll requires either
a connected wallet (`wallet_service.dart:createPoll` — the path that hangs on
"Connecting…", needs `WC_PROJECT_ID`, and can't reach the local chain) or a
local dev-signer private key (`poll_creator.dart`, `create_screen.dart`'s
"DEPLOY POLL (DEV SIGNER)"). Both require crypto. (2) **Voting** requires the
user's Semaphore commitment to already be registered by the poll owner
(`vote_view_model.dart:110` surfaces *"This identity isn't registered… ask the
organizer"*), and registration is phase-locked (Decision 0).

This epic makes the relayer sponsor the **entire** lifecycle:

- **Create (wallet-free):** the Flutter app builds `initData` exactly as
  `poll_creator.dart` does today, but sends it to a new
  `POST /api/relay/create-poll`. The relayer forwards it to
  `PollRegistry.createPoll` with **its own** signer, paying gas, and returns the
  new poll address. The owner baked into `initData` is the relayer (Decision 1),
  enforced server-side (see §1).
- **Join (wallet-free):** opening a shared poll, the app silently creates the
  user's anonymous identity (already supported — `identity_store.dart`),
  registers the commitment via a new `POST /api/relay/register-voter`, and (under
  0A) the user can register-and-vote in one Open phase.
- **Vote (wallet-free):** unchanged — the existing `/api/relay/{vote,…}` routes
  already sponsor gas.

No wallet, no gas, no seed phrase is ever shown in the default path. The wallet
and the dev-signer become an **Advanced** setting. In parallel, a
plain-language sweep removes every piece of crypto jargon from the default UI
(§2), and the silent-identity framing (§3) hides the Semaphore seed the secure
store already holds.

---

## 1. Sponsored lifecycle (the core — wallet-free create → join → vote)

### Happy path (the non-tech narrative, under Decision 0A)

1. User taps **Create** → types a **question** + **options** → picks a **simple
   type** ("Pick one", "Pick several", …) → taps **Create**.
2. The app builds `initData` (identical encoding to `poll_creator.dart`'s
   `createAnonPoll`/`_createModulePoll`/`createSurveyPoll`) but with **owner = the
   relayer address**, and POSTs `{ moduleType, title, description, initData }` to
   `/api/relay/create-poll`. A few seconds later it gets back the poll address +
   tx. **No wallet, no gas.**
3. The user gets a **shareable poll** (a "Copy link" / share sheet — never a raw
   `0x…`). The poll is **Open** immediately (the relayer self-registers a seed
   member at create so `startVoting`'s `NeedAtLeastOneVoter` is satisfied, then —
   under 0A — registration stays open during voting; see *Auto-start* below).
4. Someone opens the link → taps **"Join & Vote"**. The app **silently** creates
   their anonymous identity (`generateIdentitySeed` → secure store, §3) and POSTs
   the commitment to `/api/relay/register-voter`. The relayer (owner) registers
   it (sponsored). Under 0A this works even though the poll is already Open.
5. They **cast** (existing sponsored `/api/relay/vote` etc.) and **see results**.
   No wallet, no gas, no seed phrase shown at any step.

### Owner-from-`initData` (load-bearing correctness detail)

`PollRegistry.createPoll` sets the registry's `creator` field to `msg.sender`
(`PollRegistry.sol:67`), but the poll's **owner** comes from the `owner` argument
*inside* `initData` — each module's `initialize` calls `_transferOwnership(_owner)`
(`ZkAnonVoting.sol:64`), **not** from `msg.sender`. Today `poll_creator.dart`
bakes `writer.signerAddress` (the dev key) into that word. For a relayer-owned
custodial poll, `initData`'s owner word **must be the relayer's address**, or the
relayer pays create-gas for a poll it can't register/start (a cheap grief).

**Resolution (CHOSEN): the relayer is the single source of truth for the owner.**
The `create-poll` endpoint **re-encodes / validates the owner word server-side**
so the created poll is always relayer-owned regardless of what the client sent.
Two acceptable implementations, pick at build time:

- **(preferred) Relayer overrides the owner**: the relayer decodes the
  `initialize` call inside `initData`, substitutes its own address for the owner
  argument, re-encodes, and forwards. The client need not even know the relayer
  address. Single source of truth; a malicious client cannot mis-set the owner.
- **(simpler) Client fetches + encodes, relayer rejects mismatches**: the client
  reads the relayer address from `/api/relay/status` (already returns
  `relayer`, `app.ts:244–257`), encodes it as the owner, and the relayer
  **validates** the decoded owner == its own address and 400s otherwise.

Recommend the override variant (robust to client bugs). Either way the spec
requires: **a created sponsored poll is owned by the relayer, verified before the
tx is sent**.

### Auto-start vs. a separate "start" action

A fresh poll has zero voters, so a naive auto-`startVoting` reverts
`NeedAtLeastOneVoter` (Decision 0). To let people **vote immediately** with the
least friction:

- **CHOSEN: the relayer self-registers ONE seed member at create, then
  `startVoting`s, all sponsored, atomically inside `create-poll`.** The seed
  member is a commitment the relayer derives and discards (it never votes — it
  only satisfies `participantCount ≥ 1`). The poll comes back **Open**, so the
  creator shares a link that works instantly. Under 0A late joiners still
  register during voting, so the seed member is purely a bootstrap. *(Flag: the
  seed member inflates `participantCount` by 1 and is a registered-but-never-voting
  member — documented, harmless to tallies which count votes not members, but
  noted in Open calls.)*
- **[0B: no seed member.]** Under 0B the relayer registers real voters during a
  join window and the **creator** triggers a sponsored "Open voting" action
  (which `startVoting`s). The poll is *not* instantly votable; "Join & Vote"
  shows "Join now / opens when the creator starts it."

Recommend the seed-member auto-open under 0A (simplest path to "share → vote
now"). Confirm the seed-member trade-off with the user.

### New relayer endpoints (precise)

Both mirror the existing route shape in `app.ts` (validate → `checkRelayerBalance`
→ relay → JSON), reuse `getRelayerWallet`, and are covered by the create-specific
guard (Decision 3).

**`POST /api/relay/create-poll`**

- Body: `{ moduleType: string, title: string, description: string, initData: string (0x hex) }`.
- `moduleType` ∈ the canonical strings (`anon-vote`, `approval-vote`,
  `ranked-vote`, `quadratic-vote`, `survey-vote`) — validated against an allow-list
  (reject unknown modules before spending gas).
- Validation: `title`/`description` length caps (anti-bloat); `initData` is valid
  hex and decodes to a known `initialize` shape; **owner word == relayer**
  (override or reject per above).
- Action: `PollRegistry.createPoll(moduleType, title, description, initData)` via
  the relayer signer; then the seed-register + `startVoting` (CHOSEN auto-open).
- Returns: `{ success: true, pollAddress, txHash }`. On insufficient balance, 503
  with the calm-message contract (§2). On any revert (e.g. `InitFailed`), 400/500
  with a non-leaky message.

**`POST /api/relay/register-voter`**

- Body: `{ pollAddress: string, identityCommitment: string (decimal field element) }`.
- Validation: `isAddress(pollAddress)`; `identityCommitment` is a non-zero
  in-field decimal (`< BN254 r`, the bound already used in `validation.ts:342`);
  per-`(IP, pollAddress)` cap (Decision 3).
- Pre-checks (fail fast, like the vote routes): poll exists / is a known module;
  under 0A, `state ∈ {Open}`; commitment not already registered
  (`registeredCommitments(commitment)` is public, `ZkAnonVoting.sol:39`) — return
  ok-idempotent if already a member so a double-tap "Join" is harmless.
- Action: `registerVoter(identityCommitment)` (owner) via the relayer signer.
- Returns: `{ success: true, txHash }`.

**Existing vote routes unchanged** — `/api/relay/{vote,approval-vote,ranked-vote,
quadratic-vote,survey-vote}` already sponsor voting and stay byte-for-byte as-is.

### Validation reuse

The relayer already has `validateVoteRequest`-style validators
(`validation.ts`). The two new endpoints get sibling `validateCreatePollRequest`
/ `validateRegisterVoterRequest` validators in the same file, the same
`{ ok, data | error }` shape, the same `isValidAddress` / field-order bound
helpers. No new validation idiom.

---

## 2. Plain-language UX (Nielsen principles, named)

Every mapping below names the heuristic it serves. The rule: **the default path
shows zero crypto vocabulary.** Anything a non-tech user can't define in one
breath is either renamed or hidden behind Advanced.

| Today (jargon) | Where it lives | Plain language | Heuristic |
|---|---|---|---|
| `T-MINUS —` | `browse_screen.dart:512` (a dead placeholder — never wired) | The poll's **status**: **Open** / **Closed** / **Starts soon** (a small status pill, color-coded). Wiring it to real state also fixes the unwired countdown. | Match the real world; visibility of system status |
| `(anon-vote)`, `(approval-vote)`, `(ranked-vote)`, `(quadratic-vote)`, `(survey-vote)` suffixes | `create_screen.dart:289–337` picker subtitles | **Gone.** The module string is an internal routing key; it never appears in UI. | Aesthetic & minimalist design |
| "dev-signer", "DEPLOY POLL (DEV SIGNER)", "Dev signer active" | `create_screen.dart:256–264, 404–420, 570` | **Gone from the default flow.** The dev-signer (and wallet) move to **Advanced** (§ wallet path). Default create button reads **"Create poll"**. | Minimalist; match the real world |
| `WC_PROJECT_ID`, "Connect a wallet to deploy", "Connecting…" hang | `create_screen.dart:443`, `wallet_service.dart` | **Removed from the default flow entirely.** Wallet → Advanced. No spinner can hang the default path (it never calls the wallet). | Error prevention; user control & freedom |
| "nullifier", "scope", "module", "commitment", "proof", "Semaphore" | view-models, error strings (`vote_view_model.dart:111`) | **Never shown.** User-facing errors are plain: e.g. *"You've already voted in this poll."* (nullifier reuse), *"This poll isn't open yet."* (state). | Help users recognize/recover from errors; match the real world |
| Raw `0x…` poll/relayer addresses, tx hashes (`create_screen.dart:156` "Deploy sent · <addr>") | create success, banners | **Behind the human name.** Show the poll **title**; offer **"Copy link"** / share, not a hash. Tx hashes only under Advanced. | Recognition over recall; minimalist |

### The voting-type picker (friendly names + one-line plain descriptions)

The crypto is hidden; each type gets a human name and a single plain sentence.
(Internal module string in parentheses is the routing key — **not shown**.)

| Friendly name | One-line description (shown) | Internal (hidden) |
|---|---|---|
| **Pick one** | "Voters choose a single option." | `anon-vote` |
| **Pick several** | "Voters can choose more than one." | `approval-vote` |
| **Rank them** | "Voters put the options in order of preference." | `ranked-vote` |
| **Budget your votes** | "Voters split a pool of points across options." | `quadratic-vote` |
| **A short survey** | "Several questions in one form." | `survey-vote` |

(Blind/commit-reveal stays out of the mobile create flow as today —
`create_screen.dart:338–345` — and simply isn't offered.)

### No dead-end spinners

Every async action gets a **timeout + a calm fallback**, building on the
`RelayClient` pattern that already does this (`relay_client.dart:151` — *"Relayer
did not respond in time. Try again."*):

- **Create**: a few-second busy state with a clear label; on timeout, a calm
  *"Couldn't reach the sponsor service — try again in a moment."* (never a hung
  spinner). On 503 balance-floor, *"Sponsored creation is paused right now."*
- **Join**: silent identity + register, with the same timeout/fallback.
- **The wallet "Connecting…" path is removed from the default flow** — it only
  exists under Advanced, where a wallet-savvy user expects it.

### Friendly empty / loading / error states + first-run explainer

- Reuse the existing empty/loading views (`browse_screen.dart:518–537` already
  has plain copy) and extend the pattern to create/join.
- **First-run explainer** (one calm card, dismissible): *"Vote anonymously. No
  account, no wallet."* — sets the at-ease tone and the privacy promise in one
  line. Heuristic: match the real world; reduce anxiety before first action.

---

## 3. Identity for non-tech users

**This is mostly framing, not new crypto — the silent path already exists.**
`identity_store.dart` already generates a 32-byte seed (`generateIdentitySeed`,
`Random.secure()`) and persists it in `FlutterSecureStorage`
(Keychain / EncryptedSharedPreferences / libsecret). The `IdentityViewModel`
already supports create / import / clear (`identity_view_model.dart:43–67`). What
changes is **exposure and framing**, not the mechanism:

- **Silent generation on first use.** On first contact with any poll (or first
  "Join & Vote"), if `IdentityStore.read()` is empty, call `createNew()`
  **silently** — no prompt, no seed shown. Framed in any surfacing UI as
  *"your private voting key — kept on this device."* No "seed", "Semaphore",
  "commitment" vocabulary in the default path.
- **No seed phrase in the default UI.** The current identity screen
  (`identity_screen.dart`) shows the raw seed; move that raw view + the manual
  create/import behind **Advanced → "Back up / import"** (optional, opt-in). The
  default identity surface shows only a reassurance line and a "Back up" affordance.
- **Optional advanced back-up / import.** Keep `IdentityViewModel.import` /
  `seed` exposure, but only under Advanced — framed as *"Back up your voting key"*
  / *"Restore from a backup"*, not "paste your Semaphore seed".

Net: Section 3 is a **UI/visibility change over existing storage**, plus a silent
first-use call. No new identity primitive.

---

## 4. Honesty / trade-offs / out-of-scope

### Custodial relayer model (stated plainly)

- The relayer **owns** every sponsored poll (Decision 1A). It can **censor**
  (refuse to register a commitment), **close** a poll early (`endVoting`), and if
  it is **offline or unfunded**, the entire sponsored lifecycle stops — creation,
  registration, and voting all depend on the relayer's signer and balance. There
  is **no on-chain recourse** for a creator whose poll the relayer mistreats.
- This is **less decentralized** than the wallet path (where the connecting wallet
  owns the poll). It is a deliberate v1 trade for a wallet-free, at-ease product,
  and it is surfaced in-product as a one-line note on the creator's manage view
  (*"This poll is hosted for you — the host service runs it on your behalf."*).
- The wallet/dev-signer path remains available under **Advanced** for users who
  want true self-custody.

### Abuse surface + the v1 mitigation chosen

- Open sponsored create + register lets a script **drain the relayer's gas** or
  **flood** the registry/groups. v1 mitigates with the **tiered limiter +
  create-specific daily cap + per-`(IP, poll)` register cap + optional create
  shared-secret + the existing balance floor** (Decision 3). This stops a casual
  abuser; it is **not** Sybil-resistant.
- The relayer **fails safe**: below 0.01 ETH it returns 503 and stops sponsoring
  (`relay.ts:262–273`) rather than going bankrupt silently — surfaced as a calm
  "paused" message, not an error dump.

### Out of scope (explicitly)

- **Real decentralization of sponsorship** — removing the custodial relayer
  (e.g. account abstraction / ERC-4337 paymasters, a trustless gasless standard).
- **Account recovery beyond local back-up/import** — no server-side custody, no
  social recovery. Losing the device + the back-up loses the voting key.
- **Production-grade anti-spam** — captcha, proof-of-humanity, Sybil resistance,
  per-poll allow-lists. v1 is a *light* guard only.
- **Gasless meta-transaction standards** — the relayer pays gas directly with its
  own signer; we do not implement EIP-2771 / 4337 meta-tx relaying.
- **Migrating existing wallet/dev-signer-created polls** to the sponsored model —
  the two paths coexist; no migration.

---

## 5. Milestones (build → verify each)

> Under **0A** the plan opens with a contract milestone (M0). **[0B: delete M0;
> M1 starts the plan, and the join flow in M2 becomes a windowed "Join now / vote
> when it opens" — every other milestone is identical.]**

- **M0 — Open-registration contract change (0A only).** Fork/extend a sponsored
  module so the owner (relayer) may `registerVoter` while the poll is Open
  (registration not phase-locked out of voting), or collapse Registration+Voting
  into one Open phase. Hardhat tests against `MockSemaphoreVerifier`: register a
  commitment *during voting*, then a vote by that late joiner succeeds; existing
  modules' two-phase behavior is untouched; the no-lockout discipline holds.
  **Audit pass before M1.** *Go/no-go:* if the open-registration change is
  unacceptable, fall back to 0B (windowed) and drop M0.
- **M1 — Relayer `create-poll` + `register-voter` endpoints.** Add the two routes
  (mirroring the existing route shape), their validators in `validation.ts`, the
  owner-override/enforce logic, the seed-register + auto-`startVoting` (0A) /
  windowed `startVoting` (0B), and the create-specific guard (Decision 3). Tests:
  unit (validators, owner enforcement, abuse caps) + **local-stack e2e:
  sponsored create → register → vote with NO wallet and NO dev-signer**, proving
  the full wallet-free lifecycle end-to-end against the local Hardhat node via
  the `dev-stack.sh` harness.
- **M2 — Flutter sponsored-create flow + silent identity + "Join & Vote".**
  Rework `create_screen.dart` to be **wallet-free by default**: it POSTs to
  `/api/relay/create-poll` (no wallet, no dev-signer in the default path); the
  wallet/dev-signer move to Advanced. Wire silent identity (§3 — silent
  `createNew()` on first use). Add the **"Join & Vote"** action on a poll the
  user opens from a shared link: silent identity → `register-voter` → cast.
  Tests: widget tests for the wallet-free create form; the join flow registers +
  votes without surfacing any crypto.
- **M3 — Plain-language sweep.** Apply §2 across all screens: `T-MINUS` →
  status pill (`browse_screen.dart:512`), drop module-string suffixes
  (`create_screen.dart`), friendly type names, plain error strings (no
  nullifier/scope/module), `0x…`/tx hashes behind names + "Copy link", and move
  wallet/dev-signer copy to **Advanced**. Tests: snapshot/golden the renamed
  picker + status pill; assert no banned token (`nullifier`, `scope`,
  `anon-vote`, `dev-signer`, `WC_PROJECT_ID`) appears in default-path widgets.
- **M4 — Friendly states / onboarding + docs.** First-run explainer card
  (*"Vote anonymously. No account, no wallet."*), timeout/calm-fallback on every
  new async action, the 503 "paused" message, the custodial one-liner on the
  creator's manage view. Update `ROADMAP` / `STATUS` / the runbook with the
  sponsored-lifecycle flow and the relayer's new gas-bearing endpoints (and the
  funding/abuse note for operators).

---

## Open calls flagged for the reviewer

- **Decision 0 (0A vs 0B) — THE call the user must confirm.** 0A (a contract
  change enabling open registration during voting) is the only option that
  delivers the literal mandate (async share-a-link, join anytime); it costs a
  contract milestone + an audit. 0B (windowed) ships without a contract change but
  **cannot serve late arrivals** — "Join & Vote" becomes "Join now / vote when it
  opens." The entire rest of the plan (endpoints, identity, plain-language sweep)
  is identical either way. **Confirm 0A or 0B before M0/M1.**
- **Seed-member auto-open (0A).** The CHOSEN auto-open registers one throwaway
  relayer-derived commitment at create so `startVoting` can run, leaving the poll
  instantly Open. It inflates `participantCount` by 1 with a never-voting member
  (harmless to tallies, which count votes not members). Flip to a manual
  creator-triggered "Open" action if a clean `participantCount` matters more than
  instant-share.
- **Owner enforcement variant.** Recommend the relayer **override** the owner word
  server-side (robust). The lighter alternative (client encodes relayer address
  from `/api/relay/status`, relayer rejects mismatches) is acceptable if the
  override decode/re-encode is deemed too much for v1.
- **Create shared-secret default.** Recommend create is **open in local dev**
  (no secret) and **gated by `X-Create-Secret` in any funded deployment**. Confirm
  whether v1 should ship the secret enforced-by-default or opt-in.
- **Custodial trust surfacing.** Recommend a one-line in-product note on the
  creator's manage view. Confirm whether the user wants a stronger disclosure
  (e.g. a first-create confirmation) or the minimal one-liner.
