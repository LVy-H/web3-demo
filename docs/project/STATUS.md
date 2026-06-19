# Status

> **Snapshot:** 2026-06-19 — keep this date current when editing.

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

**This is a planning milestone, not a shipped product change yet.** No new architecture
code has been written; the old stack still exists in the tree and is slated for removal in
Phase 1 (dismantle & extract). See the implementation plan under
`docs/superpowers/plans/`.

## Where things actually stand

### Designed / decided (Phase 0 — DONE)
- System design doc (v2, post-review): core job, actors, FR/NFR (incl. the product FRs the
  review surfaced — result semantics, notifications, lifecycle edits, abstain, sharing,
  trust-level disclosure), data model, API, hardened verification protocol, honest claims,
  1.0-vs-post-1.0 scope.
- Repo cleaned: local `main` synced to `origin/main`; worktree/branch sprawl pruned;
  `.tmp` artifacts cleared; devenv WIP preserved on `chore/devenv-migration-wip`; a
  remote-branch prune script generated for the shared repo (`.out/remote-branch-cleanup.sh`).

### Exists but slated for removal (Phase 1)
- `codes/contracts/` — 6 ZK voting modules + `PollRegistry` + verifiers + `ZkAirdrop`
  (~2,000 LOC Solidity, 268 tests). **To delete.**
- `codes/relayer/` — Express gasless-relay + sponsored lifecycle (~2,500 LOC, 96 tests).
  **To delete** (its Express/Vitest scaffolding seeds the new server).
- `codes/app/packages/core_crypto/proof/` — 3 provers + 4.7 MB SNARK artifacts. **To delete**
  (Semaphore ZK is *parked* as the post-1.0 "strong mode", not lost).
- Client `ChainWriter` / dev-signer / port adapters. **To delete / rewire to server HTTP.**

### Kept (survives the pivot — backend-agnostic)
- `design_system` (Dark Bauhaus tokens + widgets); `core_domain` journey state machines +
  `voting/` off-chain tally (IRV/quadratic/survey); `core_storage`; the `feature_*` voting
  UI screens + ballot widgets; the join-code grammar.

### Not started
- The new server, blind-sig credentials, Merkle/checkpoint/anchor, public verifier, client
  rewire, the product FRs, the WCAG-AA + web-payload work (Phases 2–6).

## Known open decision (flagged for the owner)
- **Privacy against a *live* malicious host** is a post-1.0 "strong mode" (separate
  registrar ⊥ ballot box, and/or the parked ZK). 1.0 secret mode protects against
  participants/observers/forensics, not a live malicious host — stated honestly in the
  design (§6). If stronger is needed sooner, that decision can be pulled forward.

## How to update this file
- Move items between sections as work progresses; when a phase ships, update here and in
  ROADMAP. Don't accumulate history — that's CHANGELOG's job.
