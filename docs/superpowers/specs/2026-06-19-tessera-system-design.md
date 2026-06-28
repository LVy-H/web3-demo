# Tessera — System Design (ground-up rethink)

> **Status:** draft v2 (post adversarial review) · 2026-06-19
> **Supersedes:** the **architecture** of `2026-06-11-tessera-revolution-design.md`
> (on-chain + Semaphore ZK + relayer). That spec's **product/IA layer** (three
> spaces, journey state machines, jargon-free voter path, private-by-default)
> **survives** on top of this architecture. Also supersedes
> `docs/architecture/system-overview.md` (to be rewritten to match).
> **Method:** derived from first principles — requirements → threat model →
> architecture → data/API → trade-offs — *questioning every foundational
> commitment instead of inheriting it*, then hardened against a four-lens
> adversarial review (security, systems, product, red-team).

## Changelog
- **v2 (2026-06-19):** incorporated the adversarial review. Reframed the threat
  model and claims to be **honest about single-party trust** (§6); hardened the
  verification protocol (running hash-chained checkpoints, mandatory root-binding,
  challenge window, registration-before-voting — §11); expanded the data model and
  API (auth, per-decision keys, anchor status, idempotency, errors — §9/§10); added
  the missing **product** FRs (notifications, result semantics, continuity, lifecycle
  edits, abstain, sharing, trust-level disclosure — §3); added a11y/i18n NFRs (§4);
  added an explicit **"what Tessera guarantees / doesn't"** section answering "why not
  Google Forms + a hash?" (§13); split scope into **1.0 vs post-1.0** with
  distributed-trust / strong-anonymity as the named upgrade path (§16); logged every
  review finding → resolution (§17).
- **v1 (2026-06-19):** initial ground-up design.

---

## 0. Why this document exists

The product was built feature-first; its design was reverse-engineered into docs
afterwards. This is the inverse: one coherent design derived up front, by re-opening
the four hard commitments the old system rested on — a blockchain backend, Semaphore
ZK, a relayer, one Flutter client — and keeping each only if requirements earned it.
Three of the four did not survive intact.

Headline: **Tessera is not a scale problem, it is a trust problem.** Once admitted,
most of the heavy machinery (a smart-contract chain, Groth16 ZK, a gas-paying relayer)
is solving a problem the chosen threat model doesn't have. A far simpler,
classically-grounded design (a verifiable bulletin board) satisfies the requirements —
**provided we are honest about exactly which trust it does and doesn't remove.** v2's
main job was making that honesty load-bearing rather than aspirational.

---

## 1. Core job

> **Tessera lets a group make a decision everyone can trust — and check the result is
> honest without having to take the word of whoever ran it.**

The **decision** is the product. Optimise for a clear result, low-friction
participation, and public auditability. Chosen over *honest anonymous input* (needs
anonymity even against the organiser → more crypto, conflicts with the trust model) and
*verifiable secret-ballot elections* (assume you do **not** trust the organiser →
heaviest crypto + coercion-resistance). Both remain possible future modes (§16).

## 2. Actors

| Actor | Wants (one sentence) |
|---|---|
| **Participant** | *"Prove I'm allowed, cast my choice, know it counted — no jargon, no wallet, no account."* |
| **Convener** | *"Set up a decision, get the right people in, run it cleanly, publish a result people accept — without being a sysadmin."* |
| **Verifier** | *"Confirm the published result matches the ballots — without taking the convener's or host's word for it."* **First-class.** |
| **Host** *(deployment)* | *"Stand up my own instance from open source, and never depend on a service the Tessera authors run."* Usually = Convener for small groups. |

No delegate, no moderator (YAGNI; proxy voting noted as a post-1.0 HOA need, §16).

## 3. Functional requirements

> v2 adds the product FRs the review surfaced (marked ⊕). The originals were a clean
> create→vote→close loop; these are what a real group hits in the first hour.

**Participant**
- **P1** Join with zero setup — link / QR / short code; no account, wallet, funds, or install (web).
- **P2** Be admitted only if eligible, by the convener's chosen method (open · invite list · passcode · email domain).
- **P3** Cast exactly one ballot — no double-voting (idempotent; see §12.6).
- **P4** Cast in the decision's format — pick one · approve any · rank · split points · short form · **⊕ abstain / none-of-the-above** (per-decision, recorded distinctly).
- **P5** Confirm their own vote counted — a receipt that is **⊕ self-contained**: it resolves against the public ballot set + anchor with no account and no server trust (a saved link/QR/screenshot suffices).
- **⊕ P6** Opt in, at cast time, to a reminder channel the voter provides (e.g. email) for "closing soon" / "now open" — the only way to bring an account-less voter back.
- **⊕ P7** Returning after voting shows the **receipt + result-when-allowed**, never a re-castable ballot; a shared in-room device offers an explicit "new voter on this device."

**Convener**
- **C1** Create a decision: question + options + method + **ballotMode (open/secret)** + **resultsPolicy (sealed/live)** (orthogonal, §7).
- **C2** Set eligibility (+ **⊕** for invite-list async: see who hasn't voted **in open mode only**, resend, add a late-eligible voter as a logged amendment).
- **C3** Set visibility (link-only vs listed) + schedule (open/close).
- **⊕ C-rules** Set the **decision rule**: pass threshold (plurality / majority / supermajority %), optional **quorum**, and **tie-break** (declare tie / runoff / convener casting vote / public-seed random). The published result states **carried / failed / tie / quorum-not-met**, not just counts — and the verifier recomputes *that verdict* (V1).
- **C5** Distribute — link / QR / code.
- **C6** Watch turnout while open (how *many*, never how; coarse buckets in secret mode, §12.7).
- **C7** Close and publish.
- **⊕ C8** Trigger / schedule reminders (P6) and re-broadcast the link with current turnout + time-left.
- **⊕ C9** **Publish & share the result**: a public, anchor-backed result page with the verifier link embedded; shareable as link/QR; export (CSV of the public ballot set + human-readable summary; PDF for minutes).
- **⊕ C-lifecycle** **Edit** freely in `draft`; **cancel** at any pre-publish state into a terminal *cancelled* (a verifier sees it was voided, not vanished); **extend** the close time while `open` as a logged, anchored amendment.

**Verifier**
- **V1** Recompute the tally **and the decision verdict** from recorded ballots; confirm it equals the published result.
- **V2** Confirm the ballot set wasn't altered/dropped/reordered after acknowledgement (running checkpoints + anchor; §11). *See §6 for the honest limit on stuffing.*
- **V3** Confirm their own ballot is in the set (Merkle inclusion under the anchored root).
- **V4** Confirm no double-vote (no duplicate serials); confirm eligibility *to the extent the roster is attestable* (§6).
- **⊕ V5** See the **trust level** of any result: `anchored` (chain, equivocation-resistant) vs `broadcast` (signed root distributed, tamper-evident if kept) vs `casual` (host-attested only) — so a receipt can never be mistaken for a stronger guarantee than it carries.

**Host** — **H1** stand up an instance with one command (casual/broadcast default, no wallet); **H2** no hard dependency on any Tessera-authors-run service.

## 4. Non-functional requirements

| NFR | Requirement |
|---|---|
| **N1 Verifiability** | published result + verdict provably matches recorded ballots; ballot set tamper-evident *even against the host* once anchored; publicly auditable |
| **N2 Privacy** | unlisted-by-default discovery; per-decision ballot secrecy against **participants, outside observers, and after-the-fact forensics** (the host limit is named in §6) |
| **N3 Trust-min** | verification possible without trusting the host or any Tessera-run service |
| **N4 Zero-friction** | no account/wallet/funds/install on the voter web path; **<30 s to vote**; hard voter web-payload budget gated in CI (§12.4) |
| **N5 Self-host** | one-command deploy, minimal deps, permissive licence; the **default** path needs **no crypto wallet** |
| **N6 Modest scale** | tens–thousands of voters/poll; hundreds–low-thousands of polls/instance; a small VPS suffices; **do not over-engineer** |
| **N7 Portability** | one client across web (first), then mobile/desktop — *conditioned on N4 (§12.4)* |
| **⊕ N8 Accessibility** | voter path meets **WCAG 2.1 AA** (screen-reader labels, AA contrast, 44px targets, dynamic type). **1.0 gate.** |
| **⊕ N9 Localisation** | strings externalised, RTL-capable, voter path translatable. Externalisation in 1.0; full translations roadmap. |

**Deliberately absent:** high throughput, sharding, caching tiers, coercion-resistance,
certified external eligibility, upgrade/governance systems.

## 5. Scale estimate (the reframing)

5 – a few thousand voters/poll; hundreds–low-thousands of polls/instance. Peak ≈ 0.25
votes/s (30-person in-room); a 1,000-person day-long election ≈ negligible. Every ballot
ever cast fits in megabytes. **Throughput, storage, sharding, caching = non-issues.** All
pressure is on integrity, privacy, trust — none a scale axis. (Note: this argues against
a chain *for scale*; the chain's real job here is non-equivocation, §13 — not throughput.)

## 6. Threat model — what is and isn't defended (honest version)

The convener/host is **trusted for integrity but checked** — *and v2 is explicit about
where "checked" has teeth and where it reduces to trust.*

**Holds even against a malicious host (mechanism, not policy):**
- **Tally correctness** — anyone recomputes the result + verdict from the published
  ballots (V1).
- **Ballot-set tamper-evidence after acknowledgement** — receipts are a **signed
  hash-chain** over the running log and the log's roots are **anchored** (final + interim);
  dropping/reordering/altering an acknowledged ballot breaks a chain a receipt-holder can
  exhibit (§11). A verifier **must** recompute the Merkle root from the served ballots and
  assert it equals the anchored root (the binding step).
- **Setup immutability** — question, options, rules, roster-commitment, and the
  per-decision signing pubkey are committed in `setupCommitment` and anchored before
  registration (§11.1, §9).

**Rests on host honesty (named limits — do NOT overclaim):**
- **Eligibility / stuffing.** The host *defines* the roster, so it can stuff via
  fake-eligible identities or by casting the credentials of no-shows; in secret mode
  blind signatures make stuffed ballots indistinguishable from real ones. Mitigations:
  **open/passcode/domain rosters are published or member-challengeable** (a roster member
  can publicly dispute "the registered count is 47 but only 30 of us registered"); secret
  mode publishes per-identity issuance counts for member audit. **Residual: a determined
  host can stuff up to its roster-control budget.** This is consistent with "trust the
  organiser for integrity" — but V2/V4 are *detection aids*, not proofs against the host
  on eligibility.
- **Secret-ballot privacy against a *live* malicious host.** One self-hosted process
  does eligibility + blind-signing + ballot box, so it can correlate register↔cast by
  timing / IP / session. Blind RSA hides the *token*, not the *act*. Mitigations:
  **registration closes before voting opens** (breaks issuance↔cast ordering), casts on a
  fresh session, coarse turnout. **Residual: a host that logs metadata can narrow the
  anonymity set, badly in small groups.** Secret mode therefore protects against
  participants/observers/forensics, **not** a live malicious host. (The distributed-trust
  fix — separate registrar ⊥ ballot box, Belenios-style — is the post-1.0 "strong mode",
  §16.)
- **Censorship by silence.** A host can drop a ballot and return no receipt; the voter
  then has nothing to exhibit. Receipts prove **deletion-after-acknowledgement**, not
  **refusal-to-acknowledge**. (Partial mitigation: a server-signed *ack of submission*
  before commit, §11.)

**Out of scope (by the core job):** coercion / vote-buying (receipt-freeness, MACI-class);
anonymity against global blockchain validators (no ballots on chain); nation-state availability.

## 7. Ballot mode × results policy are orthogonal

Two independent axes → four valid, named combinations. The default for board/DAO is
secret + sealed.

| | **resultsPolicy = sealed-until-close** | **resultsPolicy = live** |
|---|---|---|
| **ballotMode = open** | on-record, results at close | on-record, live tally (show of hands) |
| **ballotMode = secret** | **secret + sealed** (board/DAO default; anti-herding) | secret + live (aggregate only, never per-voter) |

Live results in secret mode are **aggregate-only**. Turnout (C6) is visible in all modes,
never *how* anyone voted.

## 8. Architecture — verifiable bulletin board (lean hybrid)

Forced by one collision: **self-host (N5)** + **verify without trusting the host
(N1/N3)**. If the host controls the server, the record can't live only there — we need
one thing the host can't forge. That is the classic **verifiable bulletin-board** pattern
(Helios/Belenios lineage; §13/§17 note what we borrow and what we knowingly don't), with a
self-host twist: the board lives on the host's server, its checkpoints pinned to a
**public, host-independent anchor**.

```
        ┌────────────────────────────────────────────┐
        │      PUBLIC ANCHOR  (default: signed-root    │  host-independent,
        │      broadcast; upgrade: an L2 chain)        │  tamper-evident,
        │   stores: setupCommitment, interim+final root│  equivocation-resistant (chain)
        └──────────────▲─────────────────────▲────────┘
                       │ post roots          │ read roots (anyone)
  ┌────────────────────┴─────────┐   ┌───────┴─────────────────┐
  │  TESSERA SERVER (self-host)  │   │   VERIFIER  (anyone)    │
  │  • lifecycle + convener auth │   │  • recompute tally+verdict
  │  • eligibility + per-decision│   │  • recompute Merkle root │
  │    blind-sign issuer         │   │    == anchored root      │
  │  • append-only log + running │   │  • check serials/incl.   │
  │    hash-chained checkpoints  │   │  • read trust level (V5) │
  │  • Merkle roots + receipts   │   └───────▲─────────────────┘
  └───▲──────────────▲───────────┘           │ published ballots (read-only)
      │ join / cast  │ serve app + proofs ───┘
  ┌───┴──────────────────────────┐
  │   CLIENT  (Flutter, web-first)│   Participant / Convener / Verifier UI
  └──────────────────────────────┘
```

### Verdict on the four foundations

| Commitment | Verdict | Why |
|---|---|---|
| **Blockchain backend** | **Demote to a notary; not even the default** | Needed only for host-independent **non-equivocation** of checkpoint roots, and only when a host funds a wallet. Default anchoring is a **zero-wallet signed-root broadcast** (tamper-evident); chain is the equivocation-resistant upgrade. Drop ≈2,000 lines of Solidity. |
| **Semaphore / Groth16 ZK** | **Drop from 1.0; keep as the post-1.0 "strong mode"** | The blind-sig credential meets the chosen threat model with no circuit/prover; ZK's real residual value (permissionless membership, anonymity not resting on host) maps exactly to "strong mode" (§16) — keep the proven code parked, don't delete the option. |
| **Relayer** | **Drop** | Existed only to pay gas for on-chain votes. Votes POST to the server now. |
| **One Flutter client** | **Keep — gated on a hard web-payload budget** | Reuse design-system + product code; but N4 makes the voter-path payload a CI gate, with a thin web voter shell as a *pre-planned* fallback (§12.4), not an emergency. |

## 9. Data model

| Entity | Holds | Notes |
|---|---|---|
| **Account** (convener) | id, displayName, authCredential, createdAt | first-run bootstrap admin token printed to logs; per-convener tokens |
| **Session/Token** | bearer token, account, expiry | gates all convener routes |
| **Decision** | id, convener, title, options, method, eligibilityPolicy, visibility, **ballotMode**, **resultsPolicy**, rule (threshold/quorum/tie), schedule, **anchorMode** (chain/broadcast/casual), maxParticipants, `setupCommitment`, state | state: draft→registration→open→**closed→challenge→published** / *cancelled* |
| **SigningKey** | keyId, RSABSSA-PSS public key + params, **per-decision**, createdAt, status | pubkey hash ∈ `setupCommitment` and anchored; per-decision so leakage is contained |
| **Roster / EligibilityRecord** | method, identifier-or-hash, status (issued/used), challengeable? | per-invitee state; passcode hash + counter; domain + (SMTP) verification |
| **IssuedCredential ledger** | serial-blob ref, issuedAt, decisionId | backs the "issued-count ≤ roster" audit |
| **Ballot** | decisionId, format payload, credential `(serial, sig)`, **idempotencyKey**, logSeq, **prevHead** | append-only; payload validated by the shared tally oracle |
| **Receipt** | `(ballotHash, logPosition, runningRoot, serverSig)` | signs the **running root** (hash-chain), not an isolated position |
| **Checkpoint** | `prevRoot`, root, seqRange, `anchorRef`, status | interim + final; the unit that gets anchored |
| **Anchor** | mechanism, ref/txHash, chainId?, status (queued/submitted/confirmed/finalized/failed), confirmations | models async chain posting + reorg/finality |
| **LifecycleEvent** | transition, actor, timestamp, signed | tamper-evident admin trail (open/close/publish/extend/cancel), folded into the checkpointed log |

`setupCommitment = H(canonical( options ‖ method ‖ rule ‖ ballotMode ‖ resultsPolicy ‖
rosterCommitment ‖ issuerPubKeyHash ‖ schedule ))`, anchored before registration opens.

**Storage:** SQLite default (WAL, `busy_timeout`, single-writer discipline; §12.6).
The append-only log is the source of truth; tallies/turnout are derived.

## 10. API

**Convener** (bearer auth; first-run bootstrap token): `POST /decisions` · `/open` ·
`/close` · `/publish` · `/extend` · `/cancel` · `GET /turnout`.
**Participant:** `GET /d/:id` · `POST /register` (eligibility → blind-sign credential) ·
`POST /ballots` (**idempotencyKey required**; durably commits ballot+receipt in one txn,
returns the *same* receipt on retry).
**Public / Verifier** (no auth, read-only): `GET /decisions/:id` (metadata + commitments +
pubkey + anchor refs + trust level) · `GET /ballots?after=&limit=` (cursor-paginated, with
page hash + leaf count) · `GET /root` · `GET /results` (non-authoritative; canonical result
= what the anchored ballots tally to) · `GET /anchor` (status).

**Error model:** stable codes + HTTP statuses for every endpoint; **rejections that
matter for censorship-detection are server-signed** (decision-closed, ineligible) so a
refusal is at least exhibitable. **Abuse controls:** rate-limit `/register` + `/ballots`,
optional CAPTCHA/turnstile hook, `maxParticipants` cap, per-link issuance budgets
(open mode trades stuffing-resistance for friction — disclosed, §6).

## 11. Verification protocol (v2 — hardened)

0. **Registration closes before voting opens** (breaks issuance↔cast ordering; fixes the
   issued-set for stuffing audit).
1. **Setup can't shift.** Verifier recomputes `setupCommitment` from metadata and compares
   to the anchored value.
2. **Eligibility (with honest caveat).** Every ballot carries a valid credential
   (blind-sig verifies against the *anchored* per-decision pubkey); credential binds
   `decisionId` (no cross-decision replay). `issued-count ≤ roster size` — *necessary, not
   sufficient*; roster honesty is host-trusted, audited via published/challengeable rosters
   (§6).
3. **No double-vote.** No duplicate serials in the published set (catches voter reuse;
   host over-issuance is the §6 roster limit).
4. **Honest tally + verdict.** Recompute the result **and** the carried/failed/quorum
   verdict from published ballots via the shared tally oracle; compare to `/results`.
5. **Nothing dropped after acknowledgement.** Final root anchored; receipts are a signed
   hash-chain; **the verifier recomputes the Merkle root over the served ballots and
   asserts it equals the anchored root**; each receipt yields an inclusion proof. A valid
   receipt not resolving under the anchored root = exhibitable host misconduct.
6. **Challenge window.** Between `closed` and `published`, receipt-holders submit receipts
   for inclusion proofs and roster members raise count challenges; a valid fraud proof
   flags the decision **disputed** (anchored), even when no authority adjudicates a
   self-hosted instance.

All six hold **without ZK**. The honest scope of each (esp. 2, 5) is §6, not marketing.

## 12. Component deep-dives

### 12.1 Anchor (verifiable by default — *and* zero-wallet)
Pluggable `Anchor` adapter with three levels, **disclosed to verifiers (V5)**:
- **broadcast (default, no wallet):** server signs each checkpoint root; the **final
  signed root is distributed to all voters** (in the result page / receipt / optional
  email). Tamper-evident if any voter keeps it; equivocation only detectable by voters
  comparing. Zero crypto for the host → "one command" stays true.
- **chain (upgrade):** post roots to a public L2 → host-independent **non-equivocation** +
  public timestamp. Needs a funded wallet (cents/decision); models tx status/finality/
  reorg, holds the decision in `closed-pending-anchor` until confirmed, never shows an
  unconfirmed root as final.
- **casual:** host-attested only (no signed-root distribution). Clearly branded
  "unverifiable / trust-the-host."

This makes "verifiable by default" *real* — the default needs no wallet — while keeping the
chain as the equivocation-resistant upgrade.

### 12.2 Credential (secret mode)
**Per-decision RSABSSA-PSS blind signatures (RFC 9474, randomized variant);** pubkey hash
committed in `setupCommitment` and anchored (no host pubkey-swap). Credential message binds
`decisionId`. Issued-credential ledger backs the §6 stuffing audit. Lighter alternative to
revisit: **VOPRF / Privacy Pass anonymous tokens (RFC 9578)** — smaller, browser-friendly;
**note: no blind primitive fixes the roster (§6) or metadata-correlation (§6) holes.**
Semaphore ZK is parked for "strong mode" (§16), not deleted.

### 12.3 Server
One self-hostable service: lifecycle + convener auth · per-decision blind-sign issuer ·
append-only log (SQLite) · running hash-chained checkpoint builder · anchor adapter · static
app server. Tally recomputable by anyone.

### 12.4 Client (one Flutter codebase — gated on N4)
Kept for reuse + native reach, **but the voter path (join→cast→verify) has a hard
web-payload budget** (target ≈ ≤1 MB transfer, ≤3 s cold load on throttled 4G), measured as
a **CI gate**. Run the budget as a **spike before committing UI scope**; if Flutter web
misses (CanvasKit engine loads before app-level route-splitting can help), adopt the
**pre-planned thin web voter shell** and rewrite N7/§12.4 to "one codebase for
organise/verify/native; the voter cast path is a lightweight web target." Don't let the
premise survive on hope.

### 12.5 Schedule & close
Close is an explicit, logged, **signed state transition** committed to the log — not a bare
timestamp. Scheduled close time ∈ `setupCommitment`. Late ballots get a signed
"decision closed" response (voter holds proof). On startup-after-downtime the server
reconciles: auto-close anything past its scheduled close before accepting traffic.
Convener's explicit `POST /close` is authoritative; wall-clock close is best-effort.

### 12.6 Durability & exactly-once
`POST /ballots` requires an **idempotencyKey** (derived from the credential serial in secret
mode; voter-key+decisionId in open mode). Ballot **and** receipt commit in a single SQLite
txn before the response; retry with the same key returns the same receipt. SQLite: WAL,
`synchronous=FULL`, `busy_timeout`, single-writer for append+checkpoint+anchor-bookkeeping.

### 12.7 Turnout privacy
Secret mode: coarse turnout buckets, withhold live per-time-bucket order (it leaks casting
order → feeds correlation). Final count revealed at close.

## 13. What Tessera guarantees — and the honest "why not Google Forms + a hash?"

| | Google Forms + a posted hash | **Tessera** |
|---|---|---|
| Anonymous **and** eligibility-gated ballots | no (either named, or open) | **yes** (blind-sig credential) |
| Tally anyone can recompute from raw ballots | no (owner-controlled) | **yes** (published ballots + shared oracle) |
| Closed ballot-set tamper-evident vs the owner | only the final blob, owner re-hashes freely | **yes** (running hash-chained receipts + anchored interim roots) |
| Equivocation-resistant (one global view) | no | **chain mode** |
| A verifier tool + a stated **trust level** | no | **yes** (V1–V5) |

What it does **not** give (be honest, §6): privacy against a *live malicious host* in
secret mode; stuffing-proofness when the host controls the roster; coercion-resistance.
Those are the post-1.0 "strong mode" (§16). **The differentiator is genuine but narrow:
anonymous-yet-eligible ballots with a publicly recomputable tally and tamper-evident
history — not "trustless."**

## 14. Trade-offs & known limits

Censorship by silence (undetectable to third parties); single-party metadata correlation
in secret mode; host roster-stuffing budget; small-group deanonymisation; broadcast-mode
equivocation only voter-detectable; casual mode forfeits N1/N3 (branded as such). All
surfaced in UI via V5 and documented — *not* papered over.

## 15. Open questions

1. Chain choice + a no-wallet **non-equivocation** option (a free witnessed/transparency
   log adapter would beat broadcast mode without a wallet) — pick in implementation.
2. SMTP dependency for email-domain eligibility + reminders (weakens H2's "no external
   service") — make it optional/pluggable.
3. Multi-question ballot: elevate Decision to an ordered list of questions (shared
   roster/schedule/turnout/receipt) vs a "ballot = group of decisions" — decide before the
   data model freezes (§9 currently = one question per Decision).

## 16. Scope: 1.0 vs post-1.0

**1.0 (this design, single-party, honest claims):** verifiable bulletin board; open +
secret modes; per-decision blind-sig credentials; broadcast + chain anchoring with trust-
level disclosure; the product FRs (§3); WCAG-AA voter path; the six voting methods as
off-chain tally; one Flutter client (or thin voter shell if N4 fails).

**Post-1.0 (the upgrade path — named, not vague):**
- **Strong mode / privacy against the host** — separate **registrar ⊥ ballot box**
  (Belenios-style; recovers "either-party-honest"), and/or the **parked Semaphore ZK**
  membership credential for permissionless, host-independent anonymity.
- **Witnessed-log anchor** (no-wallet non-equivocation).
- **Proxy/delegate voting** (HOA bylaw need), multi-question ballots, full i18n, native apps.

## 17. Adversarial review log (finding → resolution)

| # | Finding (reviewer) | Resolution in v2 |
|---|---|---|
| roster-stuffing | "issued≤roster" ≠ no-stuffing; host defines roster (security C1, red-team #1) | §6 names it as a host-trusted limit; published/challengeable rosters as detection; not claimed as proof |
| single-party deanon | one process = registrar+ballotbox → metadata correlation (red-team #1, security H2) | §6 honest scope; registration-before-voting + fresh-session + coarse turnout; distributed-trust = post-1.0 strong mode (§16) |
| final-root-only | rewrite-before-close + no root-binding (security C2) | running hash-chained checkpoints + interim anchoring + **mandatory verifier root-binding step** (§11.5) |
| receipt-withholding | censorship-by-silence undetectable (security H1) | §6 states the limit; signed submission-ack mitigation (§11) |
| crash-mid-cast | double-vote / lost receipt (systems C3) | idempotencyKey + single-txn commit (§12.6) |
| no convener auth | open close/publish (systems C2) | Account/Session + bootstrap token (§9/§10) |
| RSA key lifecycle | reuse/rotation/swap (systems H1, security H4) | per-decision RSABSSA-PSS, pubkey anchored in setupCommitment (§12.2) |
| anchor tx status | reorg/stall (systems H2) | Anchor entity + finality policy + closed-pending-anchor (§9/§12.1) |
| one-command overclaim | wallet friction (systems H3, red-team #3) | broadcast (zero-wallet) is the default; chain is the upgrade (§12.1) |
| schedule/close | downtime late ballots (systems H4) | signed close transition + startup reconciliation (§12.5) |
| open-mode stuffing | no roster bound (systems H5) | abuse controls + maxParticipants + disclosed trade (§10/§6) |
| notifications | turnout dies (product C1) | P6/C8 reminders (§3) |
| result semantics | tally ≠ decision (product C2) | C-rules: threshold/quorum/tie + verdict in V1 (§3/§11) |
| continuity | no-account receipt/2-device (product C3) | self-contained receipts P5; registration-before-vote; export (§3) |
| lifecycle | no edit/cancel/extend (product H4) | C-lifecycle (§3) |
| abstain | missing (product H5) | P4 abstain/none-of-the-above (§3) |
| share/export | no result artifact (product H6) | C9 (§3) |
| already-voted | undefined return state (product H7) | P7 (§3) |
| orthogonal modes | ballotMode×resultsPolicy blurred (product H8) | §7 four-combo table |
| a11y/i18n | absent (product M10) | N8/N9 (§4) |
| casual silent downgrade | trust hollowed (product M12, security L1) | V5 trust-level disclosure (§3) |
| "why not Forms+hash" | differentiation (red-team #2) | §13 honest comparison |
| Helios/Belenios diff | re-derived weaker (red-team #4) | §13/§16 acknowledge; strong mode adopts the trust split |
| Merkle unspecified | second-preimage (security L3) | RFC 6962-style domain-separated hashing (impl note, §11.5) |

**Conceded sound by all reviewers:** dropping the relayer + the on-chain Solidity/tally;
append-only-log + recomputable-tally + first-class verifier; open ballot as default;
blind-RSA over ZK for *this* threat model. The redesign's core is right; v2's job was
honesty + hardening, and preserving ZK as an option rather than a deletion.

## 18. Relationship to prior specs

- **`2026-06-11-tessera-revolution-design.md`:** architecture superseded; product/IA
  layer survives.
- **`docs/architecture/system-overview.md`:** to be rewritten to the bulletin-board model.
- **ROADMAP Phases 0–14:** collapsed into a clean roadmap to 1.0 on this design.
