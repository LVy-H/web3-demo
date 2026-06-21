# Status

> **Snapshot:** 2026-06-21 — keep this date current when editing.

## TL;DR

**The product has been re-designed from first principles.** A ground-up rethink
(spec: [`docs/superpowers/specs/2026-06-19-tessera-system-design.md`](../superpowers/specs/2026-06-19-tessera-system-design.md))
replaced the on-chain + Semaphore-ZK + relayer architecture with a **self-hosted verifiable
bulletin board**: an append-only ballot log + blind-signature credentials + a public
commitment anchor (broadcast by default, a public chain as the equivocation-resistant
upgrade). The core job is now stated plainly — *let a group make a decision everyone can
trust, and check the result is honest without trusting whoever ran it* — under the threat
model *trust the organiser for integrity, prove the count to everyone*. The design was
hardened against a four-lens adversarial review (security / systems / product / red-team);
its claims are deliberately honest about single-party trust (§6/§13). The new
[ROADMAP](./ROADMAP.md) is a clean Phase 0–6 path to **1.0**.

**Phases 1–2 are now built.** Phase 1 dismantled the on-chain / ZK / relayer stack (PR #133);
Phase 2 built the self-hosted TypeScript server end-to-end for **open-ballot** decisions —
SQLite append-only log, convener auth, the decision lifecycle, the six-method tally oracle +
verdict, idempotent cast with signed hash-chained receipts, and the public read API. The server
builds, starts with one command, and runs create→open→cast→close→publish (245 tests + a
running-server smoke). Blind-sig credentials, Merkle/anchor, and the independent verifier are
Phase 3. See the implementation plan under `docs/superpowers/plans/`.

## Where things actually stand

### Designed / decided (Phase 0 — DONE)
- System design doc (v2, post-review): core job, actors, FR/NFR (incl. the product FRs the
  review surfaced — result semantics, notifications, lifecycle edits, abstain, sharing,
  trust-level disclosure), data model, API, hardened verification protocol, honest claims,
  1.0-vs-post-1.0 scope.
- Repo cleaned: local `main` synced to `origin/main`; worktree/branch sprawl pruned;
  `.tmp` artifacts cleared; devenv WIP preserved on `chore/devenv-migration-wip`; a
  remote-branch prune script generated for the shared repo (`.out/remote-branch-cleanup.sh`).

### Removed (Phase 1 — DONE, PR #133)
- `codes/contracts/` (on-chain ZK voting + verifiers + `ZkAirdrop`), `codes/relayer/` (gasless
  relay), and `core_crypto/proof/` (provers + 5.5 MB SNARK artifacts) — all deleted; the proof
  seam is fenced behind a throwing stub. Semaphore ZK is *parked* as the post-1.0 "strong mode",
  not lost. CI repointed to `app` + `android` + a new `server` job.

### Built (Phase 2 — DONE: server, open-ballot end-to-end)
- `codes/server/` (TypeScript + Express + better-sqlite3): SQLite WAL append-only log + typed
  repos; convener bootstrap-token auth; the decision lifecycle (state machine + signed events);
  the six-method **tally oracle + verdict** (ported from `core_domain/voting`); idempotent
  single-transaction **cast** with server-signed **hash-chained receipts**; the public read API
  (`/decisions`, `/ballots`, `/root`, `/results`, `/anchor`). 245 tests + a running-server smoke;
  one-command build/start; Docker + `dev-stack.sh up`.

### Kept (survives the pivot — backend-agnostic)
- `design_system` (Dark Bauhaus tokens + widgets); `core_domain` journey state machines +
  `voting/` off-chain tally (IRV/quadratic/survey); `core_storage`; the `feature_*` voting
  UI screens + ballot widgets; the join-code grammar. (Client rewire to the server is Phase 4.)

### Remaining (Phases 3–6)
- **Phase 3** trust core: blind-sig credentials (secret ballots), RFC 6962 Merkle + checkpoints,
  the anchor adapter (broadcast/chain), the independent public verifier.
- **Phase 4** client rewire to the server + the voter web-payload budget gate. **Phase 5**
  product FRs (result semantics, notifications, lifecycle edits, abstain, sharing, a11y/i18n).
  **Phase 6** 1.0 hardening + one-command self-host packaging.

## Known open decision (flagged for the owner)
- **Privacy against a *live* malicious host** is a post-1.0 "strong mode" (separate
  registrar ⊥ ballot box, and/or the parked ZK). 1.0 secret mode protects against
  participants/observers/forensics, not a live malicious host — stated honestly in the
  design (§6). If stronger is needed sooner, that decision can be pulled forward.

## How to update this file
- Move items between sections as work progresses; when a phase ships, update here and in
  ROADMAP. Don't accumulate history — that's CHANGELOG's job.
