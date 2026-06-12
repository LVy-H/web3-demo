# Current Focus

> **Iteration window:** 2026-06-13 → *(set the end date when scoped)*

Use this file to answer "what should I open my laptop and work on right now?" — narrower than ROADMAP (a phase), broader than a single issue.

## This iteration's goal

*One sentence. Examples: "Land the P1 contract-hardening pass." / "Truth-up every doc to the current Tessera/Flutter reality." / "Stand up a Sepolia deploy."*

**Goal:** R5 (cryptographic sealing) design spec + Sepolia readiness — the two halves of the merged `1.0` gate (ROADMAP Phase 14 + Phase 10), starting with the design work (threshold/timelock sealing options, receipt-freeness review) before any implementation.

**Why now:** R1–R4 shipped (PRs #100–#122); `resultsPolicy` is honest metadata, not cryptography — the spec (§5/§7) explicitly defers real sealing to R5 and folds it into the Sepolia gate. Nothing else stands between the current state and planning `1.0`.

**Done when:**
- [ ] Legacy `codes/mobile/` cutover PR merged (in flight from the Revolution; CI + `dev-stack.sh` + docs point at `codes/app/`)
- [ ] R5 design spec written and reviewed (sealing mechanism chosen: threshold vs timelock; receipt-freeness reviewed; migration story for the six modules)
- [ ] Sepolia readiness checklist drafted (deploy script per-network addresses, real-verifier-only policy off-localhost, relayer funding/limits, faucet story)
- [ ] Short-code resolver decision made (spec §8 open question 2 — relayer-hosted code→address table or cut)

## Active work items

Pull from `improvements/findings.md` (or wherever the work originates). One row per item, max ~5 — if you have more, narrow the focus.

| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| CUTOVER | Delete `codes/mobile/`, repoint CI + dev-stack + docs | parallel agent | in flight | one-PR cutover per the Revolution spec §6 |
| R5-SPEC | Cryptographic sealing design spec | — | not started | spec §5/§7; separate spec file under `docs/superpowers/specs/` |
| SEP-CHK | Sepolia readiness checklist | — | not started | feeds ROADMAP Phase 10 |

## Out of scope this iteration

Things you are explicitly **not** doing right now, even though they're tempting. Captures decisions so you don't relitigate.

- R5 *implementation* — design first (plan-before-implement rule)
- New voting modules, mainnet, DAO governance (spec non-goals)
- iOS proving, pagination/event-driven poll list (tracked debt, not this window)

## Decisions needed

Open questions blocking progress. One row per question, with who owns the call.

| Question | Owner | By when |
|----------|-------|---------|
| R5 mechanism: threshold (Shutter-style) vs timelock? | owner, after spec drafts options | end of iteration |
| Short-code resolver: ship the relayer-hosted table or cut codes for 1.0? | owner | end of iteration |

## Retrospective (filled in at iteration end)

> Move the contents of this section into the next iteration's lessons-learned, then clear it.

**Iteration 2026-06-11 → 2026-06-12: the Tessera Revolution (R1–R4).**

**What shipped:** all four "Done when" boxes of the previous iteration, minus the cut R0 (owner decision: no interim-usability work — the R0 fixes landed in their final homes instead). PRs #100–#122: relayer ballot-log privacy (#100); `codes/app/` pub workspace, 10 packages + `apps/tessera` (#101); journey contract + voter/blind/organizer/live state machines with real flow enforcement (#102–#107); guarded router + capabilities (#109); the VOTE/ORGANIZE/JOIN/You three-space IA (#110–#114, #116); R4 privacy defaults on-chain + relayer shim + client-core migration (#108, #117) — contracts 268→296 tests, relayer 121; plus web perf −19.7% with the web-proving fix (#115), Tessera brand (#122), nav fix (#121), format CI gate (#119), env-configurable relayer limits (#118, #120).

**What slipped (and why):** the `codes/mobile/` cutover PR (still in flight — deliberately last, one PR, after parity); the short-code *resolver* (only the grammar + honest "codes aren't live yet" UI shipped — the lookup is spec §8 open question 2, never decided); R5 cryptographic sealing (always roadmap, not slipped per se — but worth restating that today's "sealed" is client-honored metadata).

**What we learned:**
- *Process:* **parallel agent fan-out works only with explicit file-ownership rules** — R2's four journey-machine PRs (#104–#107) and R3's four feature-package PRs (#111–#114) merged near-simultaneously without conflicts because each agent owned a disjoint package/file set; the one collision risk (shared `core_domain`) was serialized via the journey-contract PR (#102) landing first.
- *Process:* **watchdog wakeups** kept long autonomous runs honest — periodic check-ins caught stalled/looping agents early instead of discovering dead work hours later.
- *Process:* **worktree recovery** — keep the primary tree on `main` and do all branch work in disposable worktrees; when an agent's worktree got wedged, recovery was "discard the worktree, respawn from origin", never surgery on the main tree.
- *Design:* defaults belong **in the contract, not in callers** (the 4-arg `createPoll` overload IS the privacy default) — and honest NatSpec about what `visibility`/`resultsPolicy` do *not* protect prevented over-claiming.
- *Wire formats:* an additive server-side shim (relayer re-encoding pre-R4 initData) let old clients keep working *and* inherit privacy — but it also means the sponsored wire format is now pinned pre-R4 in `core_relay`; moving to native R4 needs a wire-version change first.
- *Verification:* live acceptance tests against the running stack (chain + relayer) caught what golden-vector unit tests could not (the `InitFailed` overload mismatch in #117).

---

## How to use this file

- Pick **one** clear goal per iteration. If you can't, the iteration is too long.
- Cap active work items at ~5. Anything more = focus is wrong.
- Update STATUS.md when items move, but the source of truth for *what's active* lives here.
- At iteration end, copy the retro into a dated entry in CHANGELOG.md and reset this file.
