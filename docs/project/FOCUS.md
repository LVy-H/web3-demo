# Current Focus

> **Iteration window:** 2026-06-28 → *(set the end date when scoping Phase 5)*

Use this file to answer "what should I open my laptop and work on right now?" — narrower
than ROADMAP (a phase), broader than a single issue.

## This iteration's goal

**Goal:** **Phase 5 — product completeness.** With the redesign shipped (v0.4.0: server,
trust core + verifier, client rewire, secret ballots server+client, multi-tenant control
plane, one-command demo), make a real club / student-org / board able to run a decision
end-to-end **and come back to it**, on an accessible voter path.

**Why now:** Phases 1–4 are merged to `main` and CI-green; the redesign is real and
live-proven. What's left for 1.0 is the product layer the adversarial review proved are
first-hour-of-real-use needs (not polish) plus 1.0 hardening (Phase 6).

**Scope (from ROADMAP Phase 5):**
- Decision **result semantics**: pass threshold / quorum / tie-break → published verdict
  (recomputed by the verifier).
- **Notifications / reminders** (opt-in; "now open" / "closing soon").
- Lifecycle **edit / cancel / extend**; **abstain / none-of-the-above**; **result
  share/export** (link/QR, CSV, PDF for minutes).
- **Accessibility** pass to WCAG 2.1 AA on the voter path; strings externalised (i18n-ready).

**Done when:** a real group can create → open → vote (secret or open) → close → publish →
verify → **export/share** a result, get reminded, and the voter path is WCAG-AA.

## Carried-over open item (Phase 4)
- The voter **web-payload budget CI gate** (≤~1 MB, ≤~3 s cold load on throttled 4G) is still
  open — the `flutter build web` compile gate exists, the *size budget* gate does not. Land it
  alongside Phase 5 (it gates the same voter path).

## Out of scope this iteration
- **Strong mode** (privacy against a live malicious host) — post-1.0 unless the owner pulls it
  forward (flagged in STATUS).
- Reviving any dropped on-chain/relayer/ZK stack.
- 1.0 hardening / security review / packaging — that's Phase 6, after the product FRs land.

## How to use this file
- One clear goal per iteration. Cap active items at ~5. Update STATUS when items move; at
  iteration end, copy a retro into a dated CHANGELOG entry and reset this file.
