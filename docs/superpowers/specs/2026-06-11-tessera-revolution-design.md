# Tessera Revolution — ground-up product redesign

> **Status:** draft for owner review · 2026-06-11
> **Supersedes:** the IA implied by `2026-06-02-tessera-unify-flutter-design.md` (the unify-on-Flutter decision itself stands).
> **Inputs:** six code audits (navigation/reachability, workarounds/gates, layout, bugs, user journeys, privacy/exposure — 2026-06-11) + external research (e-voting doctrine, competitor UX, Flutter packaging).

## 1. Why (pain points, verified in code)

The app is a **feature collection, not a product**. Each capability shipped correctly in isolation; nobody designed the journey between them. Verified evidence:

| # | Pain | Evidence |
|---|------|----------|
| P1 | **Module screens unreachable by navigation.** Tapping a blind/approval/ranked/quadratic/survey poll card opens the *anon* screen; the correct screen exists but is reachable only via QR/deep-link the app itself generated. | `browse_screen.dart:207` (tap passes no module), `router.dart:55` |
| P2 | **No flow enforcement.** Vote forms render in the wrong phase and let users cast into guaranteed failure; registration is checked reactively after seed paste; no onboarding; nothing routes the voter to their receipt after casting. | `poll_detail_screen.dart:407–519`, `vote_view_model.dart:62–161` |
| P3 | **Results lie after voting.** 5 of 6 modules never refresh the tally after a successful cast ("VOTE COUNTED" + stale bars). No pull-to-refresh anywhere. | `poll_detail_screen.dart:514` |
| P4 | **Unrecoverable dead ends.** Blind-vote salt is device-local → lost device/storage = permanently unrevealable vote, with no warning. Live voters poll forever if the host walks away. Reveal deadline fetched but never shown or enforced client-side. | `blind_commit_store.dart`, `live_vote_view_model.dart:141–144` |
| P5 | **Capability maze.** What a user can do = platform × dev-signer × relayer × wallet × hardware. Voting impossible on iOS/desktop (no prover); creating anything beyond anon requires dev key or relayer; 4 disabled tiles; "go use the web app" for blind creation. | `proof_service_factory.dart`, `create_screen.dart:405–456` |
| P6 | **Everything globally exposed.** All polls listed publicly with plaintext metadata; every ballot plaintext in events (option, bitmask, full ranking, full survey answers); live per-option tallies public during voting; relayer logs IP + ballot + nullifier; blind-vote links address→choice at reveal. No private polls, no sealed tallies, no encryption anywhere. | `PollRegistry.sol:80`, all `VoteCast` events, `app.ts:89–237` |
| P7 | **No persona thinking.** Voters (want simplicity) get module jargon and an identity screen; organizers (want transparency + monitoring) get no dashboard and phase buttons scattered or hidden behind the live-host screen; operators (want easy hosting/distribution) get dev-signer requirements. | journey audit, all screens |

What is **not** broken: the Dark Bauhaus design system (token-complete, overflow-safe, responsive) and the cryptographic core (real Groth16 verifier proven e2e). The revolution is IA + flows + defaults + packaging, not visuals or crypto plumbing.

## 2. Who uses this, and how (research-grounded)

Design for **contexts**, not abstract features. The research says participation dies with every step of friction (DAO turnout < 5 %; Helios' UCLouvain election: 25 k eligible → 4 k cast, a round decided by 2 votes; Kahoot's 6-digit-PIN zero-onboarding is the live-segment norm).

| Context | Voter device & moment | Organizer | Stakes / constraint |
|---|---|---|---|
| **Club / class / meetup (in-room)** | phone, in the room, 30 seconds of patience, no account | one person projecting or holding a phone | low stakes, zero tolerance for setup friction |
| **Student org / co-op / HOA election** | email/chat link → phone or laptop, asynchronous over days | committee; needs turnout monitoring + a result everyone trusts | medium-high stakes; legal/secrecy expectations (HOA laws: anonymous ballot, verified eligibility) |
| **DAO / online community** | link from Discord/forum, wallet-optional | proposer; expects shielded voting (Snapshot norm) | herding/bandwagon manipulation is a known attack — sealed tallies expected |
| **Board / committee** | small group (5–30), high confidentiality | secretary; needs auditable record | small-group deanonymization is the dominant risk |

Three roles cut across all contexts (one human may hold several):

- **Voter** — *"prove I may vote, vote, get a receipt — without learning what Semaphore is."*
- **Organizer** — *"create → distribute → monitor turnout → publish results — and be able to show the result is honest."*
- **Operator/Host** — *"run the event: open registration, admit people, open/close voting — from one place, without a private key in an env var."*

## 3. Design principles ("by design", not by configuration)

1. **Private by default.** New polls are **unlisted**: discoverable only by link/QR/code. A public listing is an explicit creation-time opt-in. (CoE Rec(2017)5: data minimization is part of ballot secrecy.)
2. **Sealed by default.** Voters and the public see **no tally while voting is open** (fairness: "no partial tally before close"). Organizer may opt in to live-public results at creation — the Slido/Mentimeter/Vocdoni organizer-choice pattern. v1 enforces this at the client+relayer layer (UI policy stored in poll metadata); v2 enforces cryptographically (threshold/timelock — Shutter-style; roadmap, not this spec).
3. **Flow enforced by state machine.** Every journey is an explicit typed state machine; the UI renders the *current state's* one next action. Invalid states are unreachable (router guards), not error-handled after the fact.
4. **Wrong things impossible, not discouraged.** Release builds cannot contain a dev signer (compile-time assert). The relayer never logs ballot contents. A device that can't prove never shows a ballot it can't cast — it shows what it *can* do (browse, verify, organize) and says why honestly.
5. **Jargon-free voter path.** Voters never see: "Semaphore", "commitment", "nullifier", "module", "relayer". They see: "your voting pass", "your receipt", poll types named by what they do ("pick one", "approve any", "rank them", "split 100 points", "questionnaire").
6. **One human, one identity, automatic.** The identity seed is created lazily on first need, backed up via a recovery phrase prompt, and never a prerequisite screen the voter must discover.

## 4. Information architecture (ground-up)

### 4.1 Navigation = personas, not modules

Replace the 5-tab module-flavored shell (POLLS / VERIFY / CREATE / IDENTITY / SCAN) with **three spaces + one universal action**:

```
┌─────────────────────────────────────────────┐
│  VOTE          ORGANIZE         (drawer: You)│
│  ────          ────────                      │
│  "polls I can  "polls/events    identity,    │
│   act on now"   I run"          receipts,    │
│  + history     dashboard        settings     │
│                                              │
│            [ JOIN ]  ← center FAB:           │
│      QR / link / 6-char code, always there   │
└─────────────────────────────────────────────┘
```

- **JOIN** is the universal entry (Kahoot pattern): camera QR, paste link, or type a short code. It is how voters enter *everything* — polls, live sessions, receipts. Replaces SCAN-as-5th-tab.
- **VOTE** is the voter home: "needs your action" (registered, voting open) → "waiting" (registered, not open; committed, awaiting reveal) → "done" (receipt chips). The *public* directory of opt-in-listed polls is a secondary tab inside VOTE, not the home.
- **ORGANIZE** is the organizer home: the polls you created/host, each with a dashboard card (phase, turnout, next action). CREATE lives here as its primary button. The live-host console is this same dashboard's "run event" mode — not a separate hidden route.
- **You (drawer or profile):** voting pass (identity + recovery), receipts archive, verify-anything, settings. IDENTITY and VERIFY stop being top-level tabs; verification is also offered contextually (after casting, on receipts).

### 4.2 Screens are journey states, not feature pages

The poll screen is **one route** (`/poll/:address`) that resolves the module type on-chain (fixes P1 at the root — no `?module=` guessing), then renders by journey state:

```
voter journey (anon/approval/ranked/quadratic/survey):
  discover → eligibility(auto) → [not eligible: join/request]
          → waiting-for-open (countdown, notify-me)
          → ballot (module-specific input ONLY here)
          → proving (progress, "~10s is normal")
          → cast ✓ → receipt (save/share/verify) → results-when-policy-allows

blind journey adds:  committed (salt receipted + export warning) → reveal window
                     (deadline countdown, enforced client-side) → revealed
live-voter journey:  scanned → pending (code display, host-presence heartbeat,
                     timeout + "ask host" recovery) → admitted → ballot → done
organizer journey:   draft → created(unlisted) → distribute (QR/link/code/NFC)
                     → registration (live roster count) → voting open (turnout
                     only, tally sealed) → closed → published (results live now)
```

Each journey is a Dart state machine (`sealed class` states, explicit `advance()` transitions, one source of truth for "what can this user do now") — the missing orchestration layer the journey audit identified. Screens become thin renderers of states. Router `redirect` + `refreshListenable` guard entry: you cannot arrive at a ballot without an admitted identity and an open phase; you are *taken* to your receipt after casting.

### 4.3 Honest capability surface

A single `Capabilities` object (computed once from platform + config + hardware probes) drives the UI:

- can't prove → VOTE space shows polls read-only with one banner ("Voting from this device isn't supported yet — vote on the web or Android"), never a ballot that fails.
- can't sign → ORGANIZE offers sponsored (relayer) creation as *the* path, not a fallback; wallet/dev paths appear only when actually usable.
- no camera/NFC → JOIN leads with paste/code; share sheet drops NFC tile.

## 5. Privacy model (v1, no new cryptography)

| Data | Today | By-design default | Mechanism (v1) |
|---|---|---|---|
| Poll listing | global | **unlisted** (link/code only); listed = opt-in | registry: `visibility` flag + listed-index; client directory honors it; unlisted metadata fetched only by address |
| Live tally | public during voting | **sealed until close**; live = creation opt-in | poll metadata policy + client/relayer enforcement; contracts gain `resultsPolicy` field; cryptographic sealing (threshold/timelock) = Phase R5 roadmap |
| Ballot contents in relayer logs | plaintext incl. survey answers | **never logged** | strip `vote/bitmask/ranking/alloc/answers` from logs; log only poll + status |
| Voter join | registration events enumerable | unchanged on-chain (Semaphore needs the group); UI stops *presenting* the roster to non-organizers | client policy |
| Small-group risk | undocumented in UI | creation-time warning ("under N voters, results can identify people") + organizer-set minimum-turnout-to-publish | client + docs |
| Blind reveal linkage | address→choice public | documented honestly in UI ("your address links to your choice at reveal"); module renamed "Sealed-until-reveal" with the caveat | client copy |

On-chain ballots remain public-plaintext in v1 (that is the audit-transparency trade Semaphore gives us; the docs already admit it). The spec's claim is narrower and honest: **discovery and timing are private by default**; content privacy beyond "who" requires the R5 crypto phase.

## 6. Package architecture (modularity mandate)

Pub workspace (Dart 3.6+) + melos for orchestration. `codes/mobile/` becomes `codes/app/` workspace:

```
codes/app/
  pubspec.yaml                 # workspace root
  melos.yaml
  apps/
    tessera/                   # thin shell: composition root, router, DI wiring only
  packages/
    core_domain/               # entities, journey state machines, policies (pure Dart, no Flutter)
    core_chain/                # chain reader/writer, registry, ABIs (pure Dart)
    core_crypto/               # identity, proofs (platform impls), commitments
    core_relay/                # relayer client
    core_storage/              # secure stores (identity, salts, created polls, config)
    design_system/             # Dark Bauhaus: Db tokens, typography, shared widgets (phase strip, ResultsBars, buttons)
    feature_join/              # JOIN: scan/paste/code + deep-link grammar
    feature_vote/              # voter space + per-module ballot widgets (anon/approval/ranked/quadratic/survey/blind/live-voter)
    feature_organize/          # organizer space: create, dashboard, live-host console
    feature_you/               # identity/pass, receipts, verify, settings
```

Dependency rules (enforced by the graph — packages cannot import upward or sideways):
`apps/tessera → feature_* → core_* + design_system`; `design_system → Flutter only`; `core_domain → nothing`. Journey state machines live in `core_domain`, so flow enforcement is testable without widgets.

**Migration is greenfield-parallel (owner decision 2026-06-11: from-scratch where easier; no interim-usability work).** The workspace is built fresh at `codes/app/`; the proven non-UI code (crypto ports + their golden-vector tests, proof services, chain reader/writer, relay client, secure stores, `Db` design tokens, deep-link grammar + tests) is *lifted verbatim* into `core_*`/`design_system` — reuse, not rewrite. All UI is built new in `feature_*` against the journey engine. `codes/mobile/` stays untouched on `main` as the working reference until the new app reaches feature parity; cutover is one PR that deletes `codes/mobile/` and points CI + `dev-stack.sh` at `codes/app/`.

## 7. What ships when (phased; each phase = audited PRs, green CI)

> **Owner decision (2026-06-11): no interim-usability work.** The app is not
> being used in production now, so nothing is patched that the redesign later
> replaces. ~~R0 triage phase~~ — **cut**. The R0 fixes are NOT dropped; each
> lands once, in its final home: refresh-after-cast, phase gating,
> reveal-deadline enforcement, and live-voter timeout become *transitions and
> guards of the R2 journey state machines*; module-aware routing is the R2/R3
> single-route on-chain resolver; the missing screen tests are written against
> the R3 screens. Only the relayer ballot-log strip survives standalone (it is
> final regardless) and folds into R4.

- **R1 — Workspace + extraction:** pub workspace + melos; extract `core_*`, `design_system`; CI per-package. Zero behavior change.
- **R2 — Journey engine:** state machines in `core_domain` for the 4 journeys; router guards (`redirect` + `refreshListenable`); capabilities object; jargon-free copy pass.
- **R3 — The three-space IA:** new shell (VOTE / ORGANIZE / JOIN / You); organizer dashboard with phase controls + turnout; live-host console folded in; old tabs deleted.
- **R4 — Privacy defaults:** `visibility` + `resultsPolicy` in registry/poll metadata (contract change + migration), unlisted-by-default, sealed-by-default with creation-time opt-ins; small-group warning.
- **R5 (roadmap, separate spec):** cryptographic sealing (Shutter-style threshold or timelock), receipt-freeness review, Sepolia (existing Phase 10) folds in after R4.

Non-goals of this spec: new voting modules, mainnet, DAO governance, native iOS proving (tracked elsewhere).

## 8. Open questions for the owner

1. ~~R0 first or fold into R2?~~ **Decided 2026-06-11: R0 cut; fixes land once in their final home (see §7).**
2. **Short join-codes** need a resolver (code → poll address). Relayer-hosted table is the pragmatic v1 — acceptable, or chain-only (longer codes)?
3. **Contract changes in R4** (visibility/resultsPolicy) break deployed-addresses fixtures — fine pre-Sepolia (local-only today), confirm.
