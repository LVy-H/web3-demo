# Status

> **Snapshot:** 2026-06-28 — keep this date current when editing.

## TL;DR

**The ground-up redesign is shipped.** A first-principles rethink
(spec: [`docs/superpowers/specs/2026-06-19-tessera-system-design.md`](../superpowers/specs/2026-06-19-tessera-system-design.md))
replaced the on-chain + Semaphore-ZK + relayer architecture with a **self-hosted verifiable
bulletin board**: an append-only ballot log + blind-signature credentials + a public
commitment anchor (broadcast by default, a public chain as the equivocation-resistant
upgrade). The core job is stated plainly — *let a group make a decision everyone can trust,
and check the result is honest without trusting whoever ran it* — under the threat model
*trust the organiser for integrity, prove the count to everyone*. The design was hardened
against a four-lens adversarial review (security / systems / product / red-team); its claims
are deliberately honest about single-party trust (§6/§13). The [ROADMAP](./ROADMAP.md) is a
Phase 0–6 path to **1.0**.

**Phases 1–4 are built and merged to `main` (CI green).** Phase 1 dismantled the on-chain /
ZK / relayer stack (#133); Phase 2 built the self-hosted TypeScript server end-to-end for
open-ballot decisions (#134); Phase 3 added the trust core — RFC 6962 Merkle log +
hash-chained checkpoints, the broadcast commitment anchor, and an **independent public
verifier** (#135); Phase 4 rewired the Flutter client onto server HTTP (#136). **Secret
ballots are end-to-end** — per-decision RFC 9474 RSABSSA blind-signature credentials on the
server (#138) plus a pure-Dart client, **live-proven byte-exact** against a real server. A
**multi-tenant control plane** for operators shipped (#137), and a **one-command demo**
(`./demo.sh up`) brings up the server + web client locally. This is the **v0.4.0** release.

> **Honest caveat (unchanged):** 1.0 secret mode protects against participants / observers /
> forensics, **not a live malicious host** — that's the post-1.0 "strong mode". The trust
> model is single-party-for-integrity, verifiable-by-everyone (design §6/§13).

## Where things actually stand

### Designed / decided (Phase 0 — DONE)
- System design doc (v2, post-review): core job, actors, FR/NFR, data model, API, hardened
  verification protocol, honest claims, 1.0-vs-post-1.0 scope.

### Removed (Phase 1 — DONE, #133)
- `codes/contracts/` (on-chain ZK voting + verifiers + `ZkAirdrop`), `codes/relayer/` (gasless
  relay), and `core_crypto/proof/` (provers + ~5 MB SNARK artifacts) — all deleted; the proof
  seam is fenced behind a throwing stub. Semaphore ZK is *parked* as the post-1.0 "strong
  mode", not lost. CI repointed to `app` + `android` + a new `server` job.

### Built (Phases 2–4 — DONE, merged to `main`)
- **Server (#134)** — `codes/server/` (TypeScript + Express + better-sqlite3): SQLite WAL
  append-only log + typed repos; convener bootstrap-token auth; the decision lifecycle
  (state machine + signed events); the five-method **tally oracle + verdict**; idempotent
  single-transaction **cast** with server-signed **hash-chained receipts**; the public read
  API (`/decisions`, `/ballots`, `/root`, `/results`, `/anchor`). One-command build/start;
  Docker + `dev-stack.sh up`.
- **Trust core + verifier (#135)** — RFC 6962 Merkle log + hash-chained checkpoints, the
  broadcast commitment anchor, and an **independent public verifier** (recompute tally +
  verdict, bind the recomputed Merkle root to the anchor, root-binding + no-double-vote
  checks). A result is checkable without trusting the host.
- **Client rewire (#136)** — the Flutter client (`codes/app/`) swapped its journey ports to
  **server HTTP**; server-backed open-ballot organizer + voter adapters (`ServerClient`),
  proven by a live `ServerClient` e2e against a real server.
- **Secret ballots (#138 server + pure-Dart client)** — per-decision RFC 9474
  **RSABSSA-SHA384-PSS-Randomized** blind-signature credentials: `/register` blind-signs, a
  credentialed cast presents `(serial, credentialSig)`, serial uniqueness = no double-vote
  with no voter↔ballot link. The Dart client blinds locally and is **live-proven byte-exact**
  against the real server (register → cast accepted → reused-serial 409 → `GET /verify` ok).
- **Multi-tenant control plane (#137)** — `codes/control/`: isolated instance-per-org,
  host-routing reverse proxy, and the **`tessera-ctl`** operator CLI (localhost-first v1).
- **One-command demo** — `./demo.sh up` (server + Flutter web client locally); `deploy/` has
  the docker-compose production self-host path.

### Kept (survives the pivot — backend-agnostic)
- `design_system` (Dark Bauhaus tokens + widgets); `core_domain` journey state machines +
  `voting/` off-chain tally (IRV/quadratic/survey); `core_storage`; the `feature_*` voting
  UI screens + ballot widgets; the join-code grammar.

### Remaining (Phases 4–6)
- **Phase 4 (one item open):** the voter **web-payload budget CI gate** (≤~1 MB, ≤~3 s cold
  load on throttled 4G). The `flutter build web` compile gate exists; the *size budget* gate
  does not yet.
- **Phase 5 — NEXT — product completeness:** result semantics (threshold/quorum/tie-break),
  notifications/reminders, lifecycle edit/cancel/extend, abstain/none-of-the-above, result
  share/export (CSV/PDF), full **a11y/WCAG-AA** on the voter path, and **i18n** (strings
  externalised).
- **Phase 6 — 1.0 hardening:** verification-protocol + credential security review,
  durability/crash + abuse hardening, one-command self-host packaging + ops docs, then cut
  **1.0**.

## Known open decision (flagged for the owner)
- **Privacy against a *live* malicious host** is a post-1.0 "strong mode" (separate
  registrar ⊥ ballot box, and/or the parked ZK). 1.0 secret mode protects against
  participants/observers/forensics, not a live malicious host — stated honestly in the
  design (§6). If stronger is needed sooner, that decision can be pulled forward.

## How to update this file
- Move items between sections as work progresses; when a phase ships, update here and in
  ROADMAP. Don't accumulate history — that's CHANGELOG's job.
