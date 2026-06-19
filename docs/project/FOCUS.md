# Current Focus

> **Iteration window:** 2026-06-19 → *(set the end date when scoping Phase 1)*

Use this file to answer "what should I open my laptop and work on right now?" — narrower
than ROADMAP (a phase), broader than a single issue.

## This iteration's goal

**Goal:** Close out the design reset (Phase 0) and scope **Phase 1 — Dismantle & extract**:
delete the old on-chain/ZK/relayer stack and quarantine the reusable packages behind clean
interfaces, so the workspace is ready to build the new server on.

**Why now:** the architecture was re-designed from scratch and hardened against adversarial
review (see [STATUS](./STATUS.md) and the design doc). Nothing should be built on the new
architecture until the dead stack is removed and the kept code is behind a clean seam —
otherwise the old chain/relay/crypto coupling leaks into the new client.

**Done when:**
- [ ] Owner has reviewed the system design doc + roadmap + implementation plan.
- [ ] Phase 1 scoped into concrete deletion/extraction tasks (the implementation plan has
      the bucket-level map; turn it into ordered PR-sized steps).
- [ ] The "strong mode now vs post-1.0" decision is confirmed (default: post-1.0).
- [ ] Remote-branch cleanup on the shared repo run or declined (`.out/remote-branch-cleanup.sh`).

## Active work items

| ID | Title | Status | Notes |
|----|-------|--------|-------|
| P0 | Design reset + repo cleanup | done | system design doc v2; repo pruned |
| P1-SCOPE | Scope Phase 1 dismantle into PR-sized steps | next | from the impl plan's bucket map |
| STRONG-MODE | Confirm registrar-separation / ZK is post-1.0 | decision | flagged in STATUS |

## Out of scope this iteration
- Writing any new-architecture server/credential/anchor code (that's Phase 2+ — design and
  scope first).
- Pulling "strong mode" into 1.0 unless the owner calls for it.
- Reviving any of the dropped stack (contracts/relayer/ZK provers).

## Decisions needed

| Question | Owner | By when |
|----------|-------|---------|
| Strong mode (privacy vs a live malicious host): post-1.0 as planned, or pull forward? | owner | before Phase 3 |
| Anchor: ship broadcast-default for 1.0 and chain as upgrade, or invest in a witnessed-log adapter sooner? | owner | before Phase 3 |

## How to use this file
- One clear goal per iteration. Cap active items at ~5. Update STATUS when items move; at
  iteration end, copy a retro into a dated CHANGELOG entry and reset this file.
