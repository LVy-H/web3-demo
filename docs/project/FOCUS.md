# Current Focus

> **Iteration window:** *(set start–end dates when an iteration kicks off)*

Use this file to answer "what should I open my laptop and work on right now?" — narrower than ROADMAP (a phase), broader than a single issue.

## This iteration's goal

*One sentence. Examples: "Land the P1 contract-hardening pass." / "Truth-up every doc to the current Tessera/Flutter reality." / "Stand up a Sepolia deploy."*

**Goal:** Tessera Revolution — execute the ground-up redesign spec (`docs/superpowers/specs/2026-06-11-tessera-revolution-design.md`): R0 triage fixes first, then workspace/packages, journey engine, three-space IA, privacy defaults.

**Why now:** Owner mandate (2026-06-11): the app is a feature collection with no flow enforcement, hidden/unreachable features, no persona design, and everything globally exposed. Six code audits verified all of it.

**Done when:**
- [ ] R0 shipped: refresh-after-cast everywhere, module-aware card tap, reveal-deadline gating, live-voter timeout, relayer ballot-log strip, 5 missing screen tests
- [ ] R1 shipped: pub workspace + melos, `core_*`/`design_system` extracted, per-package CI green
- [ ] R2–R3 shipped: journey state machines + router guards; VOTE/ORGANIZE/JOIN/You shell replaces the 5-tab shell
- [ ] R4 shipped: unlisted-by-default + sealed-results-by-default with creation-time opt-ins

## Active work items

Pull from `improvements/findings.md` (or wherever the work originates). One row per item, max ~5 — if you have more, narrow the focus.

| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
|    |       |       |        |       |

## Out of scope this iteration

Things you are explicitly **not** doing right now, even though they're tempting. Captures decisions so you don't relitigate.

- _________________________________________________
- _________________________________________________

## Decisions needed

Open questions blocking progress. One row per question, with who owns the call.

| Question | Owner | By when |
|----------|-------|---------|
|          |       |         |

## Retrospective (filled in at iteration end)

> Move the contents of this section into the next iteration's lessons-learned, then clear it.

**What shipped:**
**What slipped (and why):**
**What we learned:**

---

## How to use this file

- Pick **one** clear goal per iteration. If you can't, the iteration is too long.
- Cap active work items at ~5. Anything more = focus is wrong.
- Update STATUS.md when items move, but the source of truth for *what's active* lives here.
- At iteration end, copy the retro into a dated entry in CHANGELOG.md and reset this file.
