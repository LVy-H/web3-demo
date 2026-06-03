# Tessera — UI/UX heuristic review & improvement backlog

> Evidence-based pass over the Tessera Flutter client, evaluated against Nielsen's
> usability heuristics, Material 3, and WCAG. Grounded in live emulator
> screenshots captured 2026-06-03/04 (API-31), saved under `/tmp/tessera-e2e/`
> during the e2e drive. Screens reviewed: **Browse, Poll detail (M1), Survey,
> Identity, Verify, Scan/Paste**. **Not yet reviewed (follow-up):** Create (deploy
> + module picker), Settings, Live-meeting host/voter — assess these in a second
> pass; behaviour is documented in `INSTRUCTIONS.md`.

## What's already strong (keep)

- **Cohesive design system** — the dark "Bauhaus/terminal" language (sharp
  geometry, hairline rules, signal-red accent, Inter + JetBrains Mono) is
  consistent and distinctive across every screen.
- **Empty states exist** — e.g. poll detail "No votes yet"; browse "no match".
- **Correct ballot affordances** — single-choice uses **radios**, multi-select
  uses **checkboxes**, each labelled ("PICK ONE" / "CHECK ANY THAT APPLY"), with
  full-row tap targets. The survey instruction ("all questions are mandatory") is
  explicit.
- **Security-forward Identity screen** — the seed is **truncated + hidden by
  default** with REVEAL/COPY, and a plain-language warning ("anyone with this
  seed can vote as you, so keep it secret").
- **Privacy value stated on Verify** — "Confirm a vote was counted — without
  revealing who voted or which option."
- **Browse affordances** — status filters, category filters, and search.

## Backlog (prioritised)

Severity: **P1** = blocks/clouds the core flow or fails accessibility · **P2** =
notable friction · **P3** = polish. Each item: *screen · heuristic · evidence →
fix*.

### P1

1. **Voting prerequisites are unexplained at the point of voting.**
   *Poll detail (`08-demopoll-votepanel`) · Match system↔real-world / Help users.*
   The cast panel shows a bare `paste your invite token / identity…` field with no
   inline explanation of where that comes from or that a saved identity auto-fills.
   A first-time voter on the poll page has no path to "I need an identity first."
   **Fix:** when no saved identity exists, replace the raw field with a hint + a
   **"Create / select identity →"** link to the Identity tab; when one exists,
   show "Using your saved identity" (with a change affordance) instead of a paste
   box.

2. **Low-contrast tertiary text fails WCAG AA.**
   *Global · Accessibility.* The `muteDim` token (`#4D5566`) on the `void`
   background (`#0A0C10`) measures **2.62:1** — below AA's 4.5:1 (and below the
   3:1 large-text bar). It's used for hints/placeholders (e.g. scanner hint,
   "decimal string" placeholder, tertiary meta). `mute` (`#7A8599`) is borderline
   at 5.26:1; `chalkDim` is fine (12.61:1).
   **Fix:** stop using `muteDim` for *text* (reserve it for non-text/decoration),
   or lighten it to ≥ #6B7488 (~4.5:1). Add a one-off contrast check to the design
   tokens.

3. **The anonymity value-prop is invisible at the moment of voting.**
   *Poll detail · Visibility of system status / trust.* The headline benefit
   (anonymous ZK voting) appears only on Verify, not where the user actually casts.
   **Fix:** a single reassuring line near "CAST YOUR VOTE" — e.g. "Anonymous: a
   zero-knowledge proof proves you're eligible without revealing who you are."

### P2

4. **Long hashes/addresses are shown in full.**
   *Identity (commitment ~77 digits), Poll detail (owner address), Verify
   (nullifier).* These are meant to be copied, not read; full display is visually
   heavy and error-prone to eyeball. **Fix:** a consistent monospace
   middle-ellipsis + copy chip (`0xf39F…2266`), which the browse cards already do.

5. **The disabled cast button reads ambiguously.**
   *Poll detail (`08`) · Consistency.* `[ SELECT AN OPTION ]` is styled like a
   button but is really a prompt. **Fix:** keep the prompt as a helper line under a
   clearly-disabled "CAST VOTE" button, so the control's enabled/disabled state is
   unambiguous.

6. **Scanner is missing torch + image-import.** *Scan sheet · Flexibility.* The new
   navbar scanner has no torch toggle (low-light) and no "scan from a saved image"
   — both are standard QR-UX affordances (and were called out in the navbar-scan
   research). **Fix (self-identified follow-up):** add a torch toggle via
   `MobileScannerController.toggleTorch`, and optionally `analyzeImage` for gallery
   import.

7. **No way to share/QR a poll — the new scanner has little to read.** *Poll detail
   · Closing the loop.* The app now *reads* `tessera://poll/…` and
   `tessera://verify/…` links but only *generates* QRs for live-meeting tickets.
   **Fix:** a "Share" action on poll detail (and a "Share receipt" on Verify) that
   produces the matching `tessera://` link + QR — turning the scanner into a
   two-sided feature.

### P3

8. **Reassure on destructive/again-only actions.** *Identity · Error prevention.*
   "Clear identity" loses the seed irrecoverably; confirm with a "you can't undo
   this — copy your seed first" guard (verify current behaviour).

9. **Transient-only confirmations.** *Global · Visibility.* Key confirmations
   ("New identity created", scan errors) are SnackBars that auto-dismiss; consider
   a brief inline persistent state for the important ones.

10. **Filter-strip horizontal scroll discoverability.** *Browse · Discoverability.*
    The STATUS/CATEGORY pills scroll horizontally; add an edge fade / partial next
    pill so it's clear more exist.

## Accessibility checklist (run before any "1.0" / store submission)

- [ ] **Contrast:** fix `muteDim` text (P1-2); re-audit all tokens at AA.
- [ ] **Semantic labels:** every icon-only control (REVEAL/COPY, close-X, nav
      icons, future torch) needs a `Semantics`/`tooltip` label for screen readers.
- [ ] **Text scaling:** verify layouts reflow at 200% font scale (the
      `narrow_overflow_test` already guards 340px width — extend to large-text).
- [ ] **Touch targets:** confirm all interactive rows/icons are ≥ 48×48 dp
      (ballot rows look compliant; verify the small radio/checkbox glyphs use the
      full row).
- [ ] **Focus order & dismissal:** dialogs/sheets trap focus and are
      back-button/Esc dismissable (the scan paste dialog regression — fixed in the
      navbar-scan PR — is a reminder to test these flows on-device).

## Recommended next steps

- Promote **P1-1, P1-2, P1-3** to tracked items in `docs/improvements/findings.md`
  (they're concrete and high-value for "user friendly" + "1.0").
- Do the **second review pass** over Create / Settings / Live-meeting.
- The screenshots backing each finding are in `/tmp/tessera-e2e/` (ephemeral);
  re-capture into the repo if any finding needs a durable visual.
