# Live Meeting Vote — Agile Development Plan

**Status:** Draft for review.
**Authors:** Hoang + Claude.
**Date:** 2026-05-31.
**Supersedes/extends:** [`docs/design/live-meeting-vote.md`](../../design/live-meeting-vote.md) (the original 2026-05-14 design — still the canonical reference for the cryptographic detail; this doc is the *execution plan* on top of it).

---

## 0. How to read this document

This is an **agile delivery plan** for the full Live Meeting Vote vision, not just an MVP. It is organised as:

- An **Epic** (the whole feature) broken into **Sprints** (iterations), each shipping a working, demoable increment.
- Each sprint has a **Sprint Goal**, **User Stories** (`As a … I want … so that …`), **Acceptance Criteria**, a **Demo** outcome, and a rough **size** (S / M / L / XL — T-shirt, not hours, to avoid false precision).
- A **Pain-Point Analysis** (Section 3) — explicit about what we solve, what we partly solve, and what stays unsolved. Re-read it at each sprint review.
- A **Definition of Done** (Section 7) that every story must meet.

Work the sprints top-to-bottom. The **Platform Stabilization** track (Sprint P) runs in parallel and is not a blocker for the live work, with one exception called out in Sprint 0.

---

## 1. Vision (TL;DR)

Turn the existing ZK voting dApp into a **live in-person meeting voting tool**. The organizer (teacher, chair, facilitator) projects a rotating QR code. Each attendee scans it, their browser mints a throwaway (ephemeral) Semaphore identity — **no wallet, no login, no PII** — and shows a short confirmation code. The organizer reads that code off the attendee's phone **face-to-face**, confirms it on their dashboard, and the vote unlocks. The attendee taps an option; a zero-knowledge proof is generated client-side and submitted gaslessly via the relayer.

The insight: pure cryptography can't stop "I forward my QR to a friend who isn't in the room" without expensive proximity hardware. A **two-second human face-to-face check** closes that gap. Cryptography makes cheating *technically expensive*; the human layer makes it *socially impossible* in a real meeting.

This is **additive**. Async / DAO-style polls keep working unchanged; "live mode" is a new flow layered on the same contracts.

---

## 2. Architecture

### 2.1 Decision: organizer-owned poll, organizer-authorized registration

**Chosen (2026-05-31):** the organizer connects MetaMask, creates and **owns** the poll. On face-to-face confirm, the organizer's own wallet calls `registerVoter(commitment)`. Voters never need a wallet; their vote is relayed gaslessly. **Zero contract changes for the MVP.**

```
Voter:     scan QR → ephemeral Semaphore identity → show 4-digit code → [organizer confirms] → tap option → relayer casts vote   (no wallet, no gas)
Organizer: MetaMask → owns poll → reads code, clicks Confirm → own wallet calls registerVoter(commitment)
Relayer:   relays castVote (already exists) + hosts the pending-voter queue + signs tickets
Contracts: NO CHANGES
```

**Why this over the alternatives:**

- *Relayer-owned (fully gasless, no organizer wallet)* — rejected for the MVP because it makes the relayer the trusted poll owner (centralisation) and adds relayer surface the codebase doesn't have today. Revisit if "organizer needs no wallet" becomes a hard requirement (Section 8, Q1).
- *On-chain ticket burn (trustless registration)* — rejected for the MVP because it needs contract changes + tests + audit surface. Tracked as a later evolution (Sprint 2/Backlog) if relayer trust becomes unacceptable.

### 2.2 Two corrections to the original design doc (found by reading the contracts)

The 2026-05-14 design doc assumed the relayer registers voters and that polls have an end-time. Reading `codes/contracts/` shows otherwise:

1. **M1 registration is owner-only.** `ZkAnonVoting.registerVoter` / `registerVoters` are `onlyOwner`. So registration must be authorized by the poll owner — which is exactly why the organizer-owned model above is the natural fit. (`ZkBlindVoting.register()` *is* permissionless, but M2 is commit-reveal — a two-step vote+reveal — which is the wrong UX for a single-tap live vote. We use **M1** for live mode.)
2. **There is no on-chain auto-close.** State transitions (`startVoting`, `endVoting`) are manual owner calls; there is no timestamp gate on the voting window. For a live meeting this is fine — the organizer is physically present and clicks "End." The host page enforces the *display* of the timer; the actual close is a manual `endVoting()`. **No contract change needed for timing.**

### 2.3 What we reuse vs. build new

| Reuse (already in repo) | Build new |
|---|---|
| `PollRegistry` factory; `ZkAnonVoting` (M1, single-tap) | `/live/:pollId/host` (projector) + `/live/:pollId/vote` (voter) pages |
| Relayer `POST /api/relay/vote` (gasless votes) | Relayer ticket + pending-queue endpoints; consumed-tickets set |
| `Verify` page + `ReceiptModal` (participation receipts) | `CreatePoll` "Live Meeting Mode" toggle |
| Dark Bauhaus design system + `PollTemplates` | Client libs: `ticket.ts`, `confirmationCode.ts`, `orgKeypair.ts` |
| `useRelay`, `useRegistry`, `useGroupSync` hooks | `RotatingQR`, `PendingVoterList`, `ConfirmationCode`, `LiveTally` components |

### 2.4 File map (target)

```
codes/frontend/src/
├── pages/
│   ├── LiveHost.tsx          NEW    /live/:pollId/host — organizer projector
│   ├── LiveVote.tsx          NEW    /live/:pollId/vote — voter ephemeral flow
│   └── CreatePoll.tsx        MODIFY add "Live Meeting Mode" toggle + redirect
├── components/live/
│   ├── RotatingQR.tsx        NEW    QR that refreshes every ~25s
│   ├── PendingVoterList.tsx  NEW    org-side queue with confirm/reject
│   ├── ConfirmationCode.tsx  NEW    voter-side big code + animation
│   └── LiveTally.tsx         NEW    real-time bars (subscribe VoteCast)
├── hooks/
│   └── useLiveQueue.ts        NEW   poll the relayer queue, manage state
├── lib/
│   ├── ticket.ts             NEW    sign / verify / encode / decode tickets
│   ├── confirmationCode.ts   NEW    derive 4-digit code from nonce + commitment
│   └── orgKeypair.ts         NEW    generate / store / load per-poll org key
codes/relayer/src/
├── tickets.ts                NEW    consumed-tickets set + queue + handlers
└── index.ts                  MODIFY mount the new endpoints
contracts/                    NO CHANGES (Sprint 1)
```

### 2.5 Cross-platform strategy (web now, Flutter later)

**Context (decided 2026-05-31):** the product serves *both* ad-hoc meeting voters and recurring members. That splits the surfaces cleanly:

| Surface | Platform | Why |
|---|---|---|
| Live-meeting **voter** | **Web / PWA — permanent** | Zero-install is the value prop. A walk-in attendee won't download an app to vote once. Stays web even in a Flutter future. |
| Live-meeting **organizer / projector** | **Web now**; Flutter-app option later | Projector is a big-screen, web-native surface; a recurring host may later want a native companion. |
| **Recurring-member** app (async voting, identity, receipts) | **Flutter (future)** | Install cost amortises over many uses; richer native UX is worth it for returning users. |

**The portability boundary is the relayer HTTP API + the contract ABIs.** Both the React web app and any future Flutter client are just HTTP + JSON-RPC consumers. We do **not** build a shared cross-language core now — we keep that API clean, documented, and versioned (see Definition of Done). That is the entire integration contract.

**Honest correction to "this is the last web/React version":** it isn't — and that's fine. The live-meeting voter page is web *by design* and will outlive the React→Flutter shift for everything else. What this plan delivers is (a) the durable zero-install voter surface and (b) the stable API the Flutter apps will consume. **Flutter is a separate epic with its own spec — not part of Sprints 0–4 here.**

**Flagged risk for the Flutter port — Semaphore proofs on Dart.** Proofs are generated client-side with snarkjs/WASM (artifacts fetched at runtime — see P4-24); Dart has no mature native Semaphore prover. Resolve this when the Flutter port is scoped, by choosing one of: (1) a hidden WebView running snarkjs, (2) a Rust-FFI binding (`semaphore-rs`-style), or (3) Flutter Web + JS interop. Don't pick now — just don't let the Flutter spec begin without confronting it.

---

## 3. Pain-Point Analysis

> The heart of the plan. What problem does each piece actually solve? Honest about the gaps.

### 3.1 Pains we **solve**

| Pain | How we solve it | Lands in |
|---|---|---|
| **Voter complexity** — today voting needs MetaMask + adding the Hardhat network + gas + managing a Semaphore identity. Too much for a classroom. | Wallet-free, login-free, gas-free, install-free. Scan a QR, tap an option, done. | Sprint 1 |
| **Eligibility without surveillance** — proving "you were in the room" usually means collecting names/emails. | Ephemeral identity + face-to-face confirm. Only attendees vote, exactly once, **no PII collected**. | Sprint 1 |
| **Transparency / auditability** — people distrust a black-box tally. | All votes on-chain; tally publicly verifiable via `VoteCast` events; downloadable participation receipt. | Sprint 1 (reuses shipped receipts) |
| **Vote privacy** — nobody should see how you voted. | Semaphore ZK proof; the chain reveals *that* a registered member voted, never *which one*. Receipt is participation-only (receipt-free for direction). | Sprint 1 (reuses shipped privacy model) |
| **Remote-QR-resharing attack** — forward the QR to someone not present. | 30s ticket expiry + organizer face-to-face check (a non-attendee's code is never read out). | Sprint 1 |
| **Organizer friction** — setting up a vote should take seconds. | One toggle on CreatePoll, templates, auto-redirect to the projector page. <60s to launch. | Sprint 1 |
| **Relayer honesty doubts** — "how do I know the relayer didn't stuff the voter set?" | Relayer signs a manifest of consumed tickets; anyone can audit it. | Sprint 2 |

### 3.2 Pains we **partially** solve

| Pain | What we do | What remains |
|---|---|---|
| **Same person, two devices** (phone + tablet → two votes). | Organizer sees both devices at the face-to-face step and confirms only one. | Not cryptographically enforced — relies on the human check. |
| **Trusted organizer** — a dishonest organizer could confirm a confederate. | The pending queue is projected; collusion is socially visible to the room. | Not eliminated. A fully trustless scheme would need on-chain ticket burn (Backlog). |
| **Trusted relayer** — it enforces single-use tickets and pays gas. | Signed consumed-ticket manifest (Sprint 2) makes misbehaviour auditable. | Full trustlessness needs on-chain ticket consumption — out of MVP scope. |
| **Scale to big rooms** — face-to-face is O(n) organizer effort. | Multi-QR + bulk-confirm + optional BLE auto-confirm reduce per-voter time. | Inherently doesn't scale to thousands; face-to-face is the bottleneck by design. |
| **Cross-platform reach / native UX** — users on any device, plus a richer native experience for regulars. | Web/PWA reaches every device with a browser (access: solved); the relayer API is kept clean so a native Flutter client can be added without re-architecting (§2.5). | Native mobile richness is deferred to a separate Flutter epic; Semaphore-proof-on-Dart is unsolved until that port is scoped. Adds a second client surface to maintain. |

### 3.3 Pains **not yet solved** / explicitly out of scope

| Pain | Why it's unsolved | Disposition |
|---|---|---|
| **iOS BLE/NFC proximity** | Apple/WebKit don't expose Web Bluetooth or Web NFC. | Out of our control. Face-to-face stays the baseline; BLE is an Android/desktop *bonus* (Sprint 4). |
| **In-room coercion / vote-buying** | A bully standing over you is a human problem, not a protocol one. | Receipt-freeness handles *proving direction*; physical coercion is out of scope. |
| **Venue connectivity dead spots** | If a phone has no internet, it can't relay a vote. | Out of MVP scope. Future: L2 + pre-funded ephemeral wallet, or an offline queue. |
| **Async-mode UI/UX debt** (separate from live) | `Poll.tsx` (855 LOC) / `BlindPoll.tsx` (710 LOC) are large; the poll list re-polls `getAllPolls` every 5s and won't scale past dozens; `ZkAirdrop` is untested. | Named honestly. **Does not block live work.** Pushed to the Platform Stabilization track (Sprint P). |
| **Mainnet trust** (real money, real stakes) | No external audit; mock verifier in local tests. | Out of scope for this epic. Tracked in `docs/project/ROADMAP.md` Phase 7. |

---

## 4. Epic breakdown — Sprints

Sizes: **S** ≈ a focused sitting, **M** ≈ a day, **L** ≈ multi-day, **XL** ≈ split it further.

### Sprint 0 — De-risk & foundation
**Goal:** Remove the two P0 bugs that sit *on the live path*, and prove the organizer-owned registration loop on local Hardhat before building UI on top of it.
**Why first:** Live mode reuses the M1 vote path and Semaphore identities. P0-1 (cross-poll nullifier false-positive) and P0-2 (module-scope state leak) would surface as confusing failures *during a live demo*. P0-3/P0-4 are unrelated to live and go to Sprint P.

| ID | Story | Size | Acceptance |
|---|---|---|---|
| S0.1 | *As a voter, I want my "already voted" state scoped per-poll so voting on poll A doesn't block poll B.* (P0-1) | S | Vote on poll A, navigate to poll B → vote UI available on B. `localStorage` nullifier key is per-poll. |
| S0.2 | *As a developer, I want group-sync state inside React (not module globals) so navigation between polls can't leak state.* (P0-2) | S | No module-scope `let` in `Poll.tsx`; logic in a `useGroupSync`-style hook; existing E2E passes. |
| S0.3 | *Spike: prove organizer-owned registration end-to-end on local Hardhat* — organizer wallet registers an ephemeral commitment, relayer relays that identity's vote, tally updates. | S | A throwaway script or test demonstrates the full loop with **no contract changes**. Documents any surprises in this plan. |

**Demo:** existing flows work; cross-poll bug is gone; the organizer-owned loop is proven.

---

### Sprint 1 — Live MVP (original design "Phase A")
**Goal:** A working end-to-end live vote loop demoable across two browsers — including the live "reject the cheater" moment.

| ID | Story | Size | Acceptance |
|---|---|---|---|
| S1.1 | *As a developer, I want ticket + code + org-key libs* — `ticket.ts` (sign/verify/encode/decode, ed25519 or secp256k1), `confirmationCode.ts` (4-digit from `hash(nonce ‖ commitment)`), `orgKeypair.ts` (per-poll keypair in `localStorage`). | M | Unit tests: a valid ticket verifies, an expired/forged one is rejected; the same `(nonce, commitment)` yields the same code on both sides. |
| S1.2 | *As an organizer's dashboard, I want relayer queue + ticket endpoints* — `POST /tickets/issue`, `POST /tickets/pending`, `GET /tickets/queue`, `POST /tickets/redeem`, with an in-memory consumed-tickets set. | M | Endpoints exist behind the existing rate-limiter; a redeemed ticket can't be reused; queue returns pending voters for a poll. |
| S1.3 | *As an organizer, I want a "Live Meeting Mode" toggle on CreatePoll* that deploys an M1 poll I own and redirects me to `/live/:pollId/host`. | S | Toggling it and deploying lands on the host page; non-live deploys unchanged. |
| S1.4 | *As an organizer, I want a projector host page* — rotating QR (~25s), pending-voter list with Confirm/Reject, live tally (subscribe `VoteCast`), time-remaining counter. | L | Two voters appear in the queue; Confirm calls `registerVoter` from the organizer wallet; Reject drops them; tally bars update live. |
| S1.5 | *As a voter, I want a wallet-free vote page* — verify ticket, mint ephemeral identity, show big 4-digit code, poll for "confirmed", then show question + options; tap → ZK proof → relayer vote → receipt modal. | L | On a second browser: scan→code→(confirmed)→tap→vote lands on-chain→receipt shown. No wallet involved. |
| S1.6 | *As an organizer, I want Confirm to register the voter on-chain* via my wallet (`registerVoter(commitment)`), gating the voter's enablement on the tx. | M | Voter's page flips to "vote enabled" only after the registration tx confirms. |
| S1.7 | *As a maintainer, I want a two-context E2E* (organizer + voter) covering the happy path **and** the reject path. | M | Playwright spec runs both contexts; happy path tallies a vote; reject path leaves the voter blocked. |

**Demo (the 60-second teacher script from the design doc):** create poll → project QR → two voters scan, show codes, get confirmed, vote → bars move live → a "friend not in the room" scans, gets a code, organizer can't find them → Reject → they can never vote.

---

### Sprint 2 — Hardening (original design "Phase B")
**Goal:** Robust enough to run in a real classroom; auditability + projector polish.

| ID | Story | Size | Acceptance |
|---|---|---|---|
| S2.1 | *As an auditor, I want the relayer to sign a consumed-ticket manifest* exposed at `GET /tickets/manifest` so the voter set is verifiable. | M | Manifest is signed; tampering is detectable; a doc explains how to verify it. |
| S2.2 | *As an organizer, I want my per-poll key persisted with a "regenerate" option* in case it's compromised. | S | Key survives reload keyed by pollId; regenerate invalidates old tickets. |
| S2.3 | *As an organizer, I want a projector-mode host UI* — huge text, dark, low-distraction, readable across a room. | M | Host page legible on a projector; passes a quick contrast/size check. |
| S2.4 | *As a voter, I want the vote page to be a PWA* (installable, offline shell) so a flaky network mid-meeting is less fatal. | M | Lighthouse PWA installable; the shell loads offline (the vote tx still needs network). |
| S2.5 | *As an organizer, I want an enforced voting window* — host shows a countdown and prompts `endVoting()` when it elapses. | M | Timer drives a prompt; `endVoting()` is a single click; off-chain enforcement documented. |
| S2.6 | *As a voter, I want a "get a fresh code" button* if my screen locked before I was confirmed. | S | New code generates a new identity; the old one is invalid. |

**Demo:** run a 10-voter mock meeting end-to-end on a projector; show the auditable manifest.

---

### Sprint 3 — Polish & scale (original design "Phase C")
**Goal:** Bigger rooms, shareability, locale.

| ID | Story | Size | Acceptance |
|---|---|---|---|
| S3.1 | *As an organizer of a big crowd, I want multiple parallel QRs* (batched tickets) so a 200-person room isn't one bottleneck. | M | N QRs render; each maps to a ticket batch; confirms work across batches. |
| S3.2 | *As an organizer, I want bulk-confirm* ("approve all current N in the queue"). | S | One action confirms the visible queue; each still triggers its registration. |
| S3.3 | *As a voter, I want my receipt as a shareable image.* | S | Receipt downloads as a PNG/QR image. |
| S3.4 | *As a Vietnamese-speaking user, I want EN/VI i18n.* | M | Language toggle; both locales render the live flow. |
| S3.5 | *As a maintainer, I want anonymous telemetry* (polls created, voters, avg time-to-vote) with no PII. | S | Counts only; documented as PII-free; opt-out respected. |

---

### Sprint 4 — Hardware-assisted proximity (original design "Phase E")
**Goal:** Optional automated proximity check that *augments* (never replaces) the face-to-face baseline.

| ID | Story | Size | Acceptance |
|---|---|---|---|
| S4.1 | *As an Android/desktop voter, I want auto-proximity via Web Bluetooth* — scan for the organizer's beacon UUID; strong RSSI sets `proximityVerified`, shown as a green badge on the org dashboard. | L | On a supported browser, proximity sets the badge; the registration still requires organizer confirm. |
| S4.2 | *As an Android voter, I want an NFC-tap option* — tap the organizer's tag to attest presence. | M | Chrome-on-Android reads the tag; token flows to the relayer. |
| S4.3 | *As an iOS voter, I want graceful fallback* — no BLE/NFC, face-to-face still works, no broken UI. | S | iOS shows only the code path; no errors; documented support matrix. |

**Out of scope (acknowledged):** cross-chain, token-gated polls, multi-question polls, iOS BLE/NFC (Apple platform constraints).

---

### Sprint P — Platform Stabilization (parallel track)
**Goal:** Pay down platform debt so the live feature has a trustworthy base and can be demoed on a real testnet. Runs alongside; only S0 is a hard prerequisite for live work.

> **Note — STATUS.md is stale (dated 2026-04-27).** Reading the contracts shows several P1 items already appear landed: contracts use OZ `Ownable` (diamond-resolved `owner()`), custom errors (`revert NotInRegistration()` etc.), and a unified `pragma solidity 0.8.28`. **First task here is to audit which P1 items are actually done and close them in `docs/improvements/findings.md`**, rather than re-doing work.

| ID | Story | Size | Source |
|---|---|---|---|
| SP.1 | *Audit & close already-done P1 items* (Ownable / custom errors / pragma) and update findings + STATUS. | S | P1-5/6/7/10 |
| SP.2 | *ZkAirdrop test suite* (it moves real ETH and has zero tests). | M | P0-3 |
| SP.3 | *Rewrite stale `codes/` docs* that describe the removed `ZkVotingLottery`. | S | P0-4 |
| SP.4 | *GitHub Actions CI* — matrix on contracts + frontend, required on `main`. | M | P3-16 |
| SP.5 | *Sepolia deploy with real verifier* + loud mock-verifier banner, so the live demo can run on a public testnet. | L | P3-19, P4-23, ROADMAP Phase 6 |
| SP.6 | *Refactor `Poll.tsx` / `BlindPoll.tsx`* into composed components (pure refactor, no behavior change). | L | P2-13, P2-14 |
| SP.7 | *Scale the poll list* — pagination + event-driven updates instead of 5s polling. | M | P4-21, P4-22 |

---

## 5. Cryptographic guarantees & attack model (summary)

Full detail lives in [`docs/design/live-meeting-vote.md`](../../design/live-meeting-vote.md) §2 and §6. The load-bearing claims:

- **One vote per identity** — Semaphore nullifier, enforced on-chain.
- **One registration per ticket** — relayer consumed-ticket set (auditable manifest in Sprint 2).
- **Ticket integrity & expiry** — signed by the organizer's per-poll key; rejected after ~30s.
- **Privacy** — organizer sees only `(code, commitment)` pairs, never the vote choice; the chain never links a commitment to a choice.
- **The QR-resharing attacks (A3/A4)** are stopped by the **human face-to-face check**, not by cryptography — this is the deliberate, central design choice.

---

## 6. Tech & dependencies

- **No new contract dependency** for Sprints 0–4 (organizer-owned model). On-chain ticket burn (Backlog) would add one.
- **Relayer** gains in-memory ticket/queue state (Sprint 1) → signed manifest (Sprint 2). No DB required for the MVP; note the trade-off (state lost on restart) and revisit only if needed.
- **Frontend**: QR generation lib, a signing primitive (ed25519 via `@noble/ed25519` or secp256k1 from the existing wallet stack), PWA tooling (Sprint 2), Web Bluetooth/NFC (Sprint 4, feature-detected).
- **Semaphore artifacts** already fetched at runtime; bundling is a separate ROADMAP item (P4-24).

---

## 7. Definition of Done (every story)

- Code matches surrounding conventions (`docs/standards/frontend-conventions.md`).
- Tests appropriate to the layer: unit for libs, contract tests if contracts change (they don't in 0–4), Playwright E2E for user-visible flows.
- `npm run lint` passes in the touched package.
- Relevant docs updated (this plan, module docs, or `findings.md`).
- **Any relayer endpoint added or changed is documented as a versioned API reference** — it is the cross-client contract both the web app and future Flutter clients consume (§2.5). Keep it explicit and stable.
- The increment is **demoable** and introduces **no new P0**.
- Each sprint ends with a short review against the Pain-Point Analysis: did we move any "partial/unsolved" pain, or create a new one?

---

## 8. Open questions / decisions to revisit

1. **Organizer wallet vs. fully gasless organizer.** MVP requires the organizer to have MetaMask + a little gas. If a target user (a non-crypto teacher) can't, revisit the relayer-owned model. *Owner: Hoang.*
2. **Ticket expiry sweet spot.** Design recommends 25–30s. Tune with real scanning in Sprint 2. *Owner: Hoang.*
3. **Relayer state durability.** In-memory is fine for a single meeting; if polls must survive a relayer restart, add persistence. Defer until proven necessary (YAGNI). *Owner: Hoang.*
4. **Is the async (non-live) mode still a product goal**, or does live become the headline? Affects how much of Sprint P (SP.6/SP.7) is worth doing. *Owner: Hoang.*
5. **Flutter port scope & sequencing** — which native surface first: the organizer app, or the recurring-member voter app? Out of scope for this plan; needs its own spec once the web API stabilises (end of Sprint 1/2). *Owner: Hoang.*
6. **Semaphore-proof-on-Dart path** — WebView+snarkjs vs. Rust-FFI vs. Flutter-Web+JS interop (§2.5). Decide at Flutter-spec time; it is the long pole of the port. *Owner: Hoang.*

---

## 9. References

- Original design — [`docs/design/live-meeting-vote.md`](../../design/live-meeting-vote.md)
- Roadmap & status — [`docs/project/ROADMAP.md`](../../project/ROADMAP.md), [`docs/project/STATUS.md`](../../project/STATUS.md)
- Improvement backlog (P0–P4) — [`docs/improvements/findings.md`](../../improvements/findings.md)
- System overview — [`docs/architecture/system-overview.md`](../../architecture/system-overview.md)
- Semaphore protocol — https://semaphore.pse.dev/
