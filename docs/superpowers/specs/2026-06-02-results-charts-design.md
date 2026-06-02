# Tessera — Results Charts on Poll Detail — Design

> **Date:** 2026-06-02 · **Owner:** Hoang · **Status:** approved, pre-implementation
> Small polish lane under ROADMAP Phase 9. Builds in its own worktree **after
> PR #44 merges** (both touch `poll_detail`).

## Goal

Make poll results **glanceable**: render the per-option tally as horizontal bars
(percentage + count + winner highlight) on the M1 (anon) and M2 (blind) detail
screens, replacing/augmenting the current plain text counts.

## Approach

- **One reusable presentational widget** `lib/ui/widgets/results_bars.dart`:
  - Input: `List<({String label, BigInt count})>` (+ optional `totalVotes`).
  - Renders a themed horizontal bar per option: fill ∝ count/total, with the
    label, count, and `%`. Highlights the leader; ties show no single winner.
  - **Zero state:** "No votes yet" when total is 0 (no divide-by-zero).
  - Pure widget — no data fetching, no `ProofService`, fully themeable via `Db.*`.
- **No new dependency.** Custom-painted/`Flexible`-ratio bars (not `fl_chart`) keep
  the app light and on-theme with the Dark Bauhaus system. Revisit a chart lib
  only if we later need pie/line/time-series.
- **Wiring:**
  - M1: `lib/ui/features/poll_detail/poll_detail_screen.dart` results section,
    fed by the existing `ChainReader.getResults(poll)` (per-option `BigInt`).
  - M2: the blind poll screen's reveal/tally section, fed by the existing blind
    reads. Same widget, same shape.

## Verification

- Widget tests: given counts → correct bar fractions, correct leader highlight,
  tie shows no winner, zero-total shows the empty state, large `BigInt` counts
  don't overflow. `flutter analyze` clean. Runtime smoke on `-d linux`.

## Out of scope

- Live-updating/animated bars, historical charts, CSV export. Single-question
  tallies only (multi-question survey results come with Phase 12d).

## Done-when

- M1 + M2 detail screens show proportional bars with %, count, winner highlight,
  and a clean zero state; widget tests green; analyze clean.
