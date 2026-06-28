# Visual Design Guide

How to design interfaces for the Anonymous Web3 Voting System that feel trustworthy, professional, and effortless to use.

---

## 1. Theme System

### Color Philosophy

A voting app must feel **neutral, trustworthy, and secure**. Avoid bright/playful palettes (feels unserious) and dark/aggressive palettes (feels intimidating). Use **cool neutrals with a single accent**.

**Primary palette (locked):**

| Token | Color | Usage |
|-------|-------|-------|
| `--color-surface` | Slate-50 (`#F8FAFC`) | Page background |
| `--color-card` | White (`#FFFFFF`) | Cards, panels, modals |
| `--color-text` | Slate-900 (`#0F172A`) | Primary text |
| `--color-text-muted` | Slate-500 (`#64748B`) | Secondary text, descriptions |
| `--color-border` | Slate-200 (`#E2E8F0`) | Card borders, dividers |
| `--color-action` | Slate-900 (`#0F172A`) | Primary buttons |
| `--color-accent` | Blue-600 (`#2563EB`) | Links, focus rings, interactive highlights |

**Semantic palette:**

| Token | Background | Text | Icon | When |
|-------|-----------|------|------|------|
| Success | Emerald-50 | Emerald-700 | Checkmark | Vote cast, poll created |
| Warning | Amber-50 | Amber-700 | Exclamation | Pending action, low participation |
| Danger | Rose-50 | Rose-700 | X mark | Errors, destructive actions |
| Info | Blue-50 | Blue-700 | Info circle | Tips, explanations |

**Rule: Never use color alone to convey meaning.** Always pair with an icon or text label. This ensures color-blind users get the same information.

### Typography

**Font stack:** System fonts (no custom font loading = faster paint):
```css
--font-sans: ui-sans-serif, system-ui, -apple-system, sans-serif;
--font-mono: ui-monospace, SFMono-Regular, Menlo, monospace;
```

**Type scale (Major Third -- 1.250 ratio):**

| Role | Size | Weight | Line Height | Usage |
|------|------|--------|-------------|-------|
| Page title | `text-3xl` (30px) | `font-extrabold` (800) | 1.2 | "Voting Hub" |
| Section heading | `text-xl` (20px) | `font-bold` (700) | 1.4 | "Cast Your Vote" |
| Card title | `text-lg` (18px) | `font-semibold` (600) | 1.4 | Poll title in card |
| Body | `text-sm` (14px) | `font-normal` (400) | 1.5 | Descriptions, labels |
| Caption | `text-xs` (12px) | `font-medium` (500) | 1.4 | Badges, timestamps |
| Monospace | `text-xs` (12px) | `font-normal` (400) | 1.5 | Addresses, tokens, hashes |

**Rules:**
- Maximum 3 font weights per page (400, 600, 800)
- Never use bold for paragraphs -- bold is for headings and labels only
- Monospace (`font-mono`) only for technical data (decision ids, hashes, tokens)
- Minimum 14px for body text (12px only for captions)

### Spacing (8px Grid)

All spacing is a multiple of 8px. This creates visual rhythm.

| Context | Value | Tailwind | Example |
|---------|-------|----------|---------|
| Within related elements | 8px | `gap-2` | Label to input, icon to text |
| Between form fields | 16px | `gap-4` / `space-y-4` | Input to input |
| Between sections | 24-32px | `gap-6` / `gap-8` | "Your Identity" to "Cast Vote" |
| Between major blocks | 40-48px | `gap-10` / `gap-12` | Left panel to right panel |
| Page-level | 48-64px | `p-6 md:p-12` | Page margins |

**Rule: The gap between groups must be at least 2x the gap within groups.** This is Gestalt proximity -- users mentally group elements that are close together.

### Contrast Requirements

| Element | Minimum Ratio | Target | Check With |
|---------|--------------|--------|------------|
| Body text on white | 4.5:1 (AA) | 7:1 (AAA) | Slate-900 on white = 15.4:1 |
| Muted text on white | 4.5:1 (AA) | -- | Slate-500 on white = 4.6:1 |
| Button text | 4.5:1 (AA) | 7:1 (AAA) | White on Slate-900 = 15.4:1 |
| Focus ring | 3:1 | -- | Blue-600 on white = 4.7:1 |

---

## 2. Component Design Principles

### Principle of Least Surprise

The user should never think "wait, what just happened?" Every element should behave exactly as expected.

**Button placement (never break these):**
- Primary action: **bottom-right** of its section, or **full-width bottom**
- Secondary action: **left of primary**
- Destructive action: **separate row**, lower visual prominence (outline style, not filled)
- "Back" / navigation: **top-left**

**Consistent state communication:**

| State | Visual | Example |
|-------|--------|---------|
| Default | Normal colors | "Create Poll" |
| Hover | Slight lightening (+5%) | `hover:bg-slate-800` |
| Active/Pressed | Slight darkening | `active:bg-slate-950` |
| Loading | Spinner + "Processing..." | Button becomes non-clickable |
| Disabled | 50% opacity | `disabled:opacity-50 disabled:cursor-not-allowed` |
| Success | Green background + checkmark | "Poll Created!" for 3 seconds |
| Error | Red text below button | Human-readable message |

**Form conventions:**
- Radio buttons for candidate selection (not dropdowns) -- each option is visible
- Each option card: minimum 48px height, full-width, clear selected state
- Selected state: colored left border (3px) + background tint + checkmark icon
- Never shuffle option order between page loads
- Submit button disabled until a selection is made (with tooltip explaining why)

### Components That Build Trust

**For a voting/privacy app, trust is the product.** These components signal security:

**1. Encryption indicator:**
```
┌──────────────────────────────────────────┐
│  🔒  Your vote is encrypted end-to-end   │
│       Only the final tally is revealed    │
└──────────────────────────────────────────┘
```
- Lock icon (16-20px) + clear statement
- Appears during and after vote submission
- Light blue background (`bg-blue-50`) -- blue signals security

**2. Privacy receipt (show, don't tell):**
```
What we record:              What we DON'T record:
✓ Your vote was counted      ✗ Your identity
✓ Timestamp                  ✗ Your wallet address
✓ Confirmation ID: A7F2...   ✗ Which option you chose
```
- Green checkmarks for collected data, red X for excluded data
- Monospace for the confirmation ID
- This is more convincing than "your vote is anonymous" text

**3. State progression (padlock metaphor):**
```
[ 🔓 Preparing ] → [ 🔐 Encrypting ] → [ 🔒 Submitted ] → [ ✓ Verified ]
```
- Discrete steps, not a continuous bar
- Each step has a label and icon
- Current step pulses gently, completed steps are solid green

**4. Skeleton loaders during verification:**
- Show skeleton loaders while verifying votes (not just while loading data)
- Include time estimate: "Verifying... ~3 seconds"
- This signals the system is doing real work, not just a spinner

### Components That Create Ease of Use

**1. Empty states with personality:**
- Not: "No polls found."
- Better: "No polls yet. Create the first one!" with a prominent "Create Poll" button
- Empty state is the first thing a new user sees. Make it inviting.

**2. Inline validation (not after submit):**
- Validate on blur (when field loses focus), not on every keystroke
- Show validation within 200ms of blur
- Green border + checkmark for valid, red border + message for invalid
- Never block the form -- show all errors at once, let user fix in any order

**3. Forgiving inputs:**
- Addresses: accept with or without `0x` prefix, auto-format
- Tokens: trim whitespace automatically
- Numbers: accept commas and spaces, parse gracefully

**4. Confirmation before irreversible actions:**
- Vote submission: show summary ("You're voting for Option B in 'Best Framework'") with explicit "Confirm" button
- Poll creation: show preview before deploying
- Width: 400-512px dialog. Primary action right-aligned.
- Use specific labels: "Confirm My Vote" not "OK"

---

## 3. Cognitive Laws Applied

### Fitts's Law (bigger targets for important actions)

| Element | Minimum Size | Recommended |
|---------|-------------|-------------|
| Vote button | 48px height, full width | 56px height |
| Option cards | 48px height, full width | 64px height |
| Touch targets | 44x44px | 48x48px |
| Gap between adjacent buttons | 12px | 16px |

**Rule: The most important action on the page should be the largest clickable element.**

### Hick's Law (fewer choices = faster decisions)

- Maximum 7 poll options visible at once. If more, paginate with "Showing 1-7 of 12"
- Poll creation form: show only Title + Options initially. Description, advanced settings behind "More options" toggle
- Admin panel: show only the actions available in the current phase. Hide irrelevant controls.

### Miller's Rule (7 ± 2 items)

- Dashboard: maximum 6-9 poll cards per page, then paginate
- Navigation: maximum 5 top-level items
- Poll options: 7 visible at once, scroll for more with a count indicator

---

## 4. Gestalt Principles for Layout

### Proximity (group related things)

```
┌─────────────────────────────────┐
│ YOUR IDENTITY          (8px gap)│
│ ┌─────────────────────────────┐ │
│ │ Token input     [Load]      │ │  ← Related: 8px between input and button
│ └─────────────────────────────┘ │
│                                 │
│                    (24px gap)   │  ← Unrelated: 24px between sections
│                                 │
│ CAST YOUR VOTE                  │
│ ┌─────────────────────────────┐ │
│ │ ○ Option A                  │ │
│ │                   (8px gap) │ │  ← Related options: 8px apart
│ │ ● Option B                  │ │
│ │                   (8px gap) │ │
│ │ ○ Option C                  │ │
│ └─────────────────────────────┘ │
│                    (16px gap)   │
│ [ Generate Proof & Vote ]       │  ← Action separated from options
└─────────────────────────────────┘
```

### Similarity (same style = same function)

- All poll cards: identical dimensions, identical layout (title → description → address → badge)
- All action buttons: same height (44px), same border-radius (`rounded-xl`)
- All status badges: same font size (`text-xs`), same padding (`px-2.5 py-1`), same uppercase tracking

### Closure (show progress toward completion)

- Step indicators: filled circles for done, ring for current, dots for future
- Poll results: always show total vote count and percentage (gives sense of completion)
- Registration: "3 of 10 voters registered" -- numeric progress

### Continuity (consistent direction and flow)

- Reading flow: top-to-bottom, left-to-right
- Poll lifecycle flows left-to-right: Registration → Voting → Ended
- "Next" always on the right, "Back" always on the left
- Completed states always green, current always blue, future always gray

---

## 5. Emotional Design

### Norman's 3 Levels

**Visceral (first impression, 50ms):**
- Clean whitespace (don't cram)
- Muted professional colors (slate + blue)
- Sharp typography hierarchy (clear size jumps between heading levels)
- No clutter above the fold -- title, one action, nothing else
- **Test: screenshot the page. Show it for 1 second. Ask "what does this do?" If the answer isn't clear, redesign.**

**Behavioral (during use):**
- Every click produces feedback within 100ms
- Forms validate as you go, not after submit
- Errors tell you what to do, not what went wrong
- Loading states have time estimates
- Success states feel rewarding (large checkmark, generous spacing, clear next step)

**Reflective (after use):**
- Post-vote screen: "Your voice matters. X% of voters have participated."
- Receipt page: clean, downloadable, shareable
- History view: "You voted in 3 polls this month"
- **The user should leave feeling good about having participated**

### State-Specific Emotions

| State | Target Emotion | How |
|-------|---------------|-----|
| Empty state | Curiosity, invitation | Friendly copy, prominent CTA |
| Loading | Patience, trust | Skeleton loaders, time estimates |
| Error | Calm, agency | Clear message, retry button, no blame language |
| Success | Pride, completion | Large checkmark, congratulatory text, next action |
| Results | Transparency, fairness | Even-handed presentation, percentages, no bias colors |

---

## 6. Accessibility Baseline

### Non-Negotiable Rules

1. **Focus indicators on every interactive element.** 3px solid outline, 2px offset, Blue-600 color. Never `outline: none` without a replacement.

2. **Tab order matches visual order.** Test by pressing Tab through the entire page.

3. **All inputs have `<label>` elements.** Placeholder text is NOT a substitute for labels.

4. **Form inputs minimum 16px font size.** Prevents iOS Safari auto-zoom on focus.

5. **`prefers-reduced-motion` respected.** Wrap all animations:
   ```css
   @media (prefers-reduced-motion: reduce) {
     *, *::before, *::after { animation-duration: 0.01ms !important; }
   }
   ```

6. **No color-only indicators.** Every status color is paired with an icon:
   - Success: green + checkmark (✓)
   - Error: red + X mark (✗)
   - Warning: amber + exclamation (!)
   - Info: blue + info circle (i)

7. **Touch targets 48x48px.** This includes radio buttons, checkboxes (click area includes label), and icon buttons.

8. **Vote confirmation uses `role="alert"` with `aria-live="assertive"`.** Screen readers announce it immediately.

---

## Quick Reference: Design Decisions

When in doubt, choose the option that is:

1. **More boring** -- exciting design is distracting in a voting app
2. **More explicit** -- "Confirm My Vote for Option B" beats "Submit"
3. **More spacious** -- whitespace signals quality and confidence
4. **More consistent** -- same pattern everywhere, even if a specific case could be "optimized"
5. **More accessible** -- if it works for a keyboard-only user, it works for everyone

---

## Checklist: Before Any Design PR

- [ ] Contrast ratios: 4.5:1 for text, 3:1 for UI elements
- [ ] No color-only status indicators (always paired with icon/text)
- [ ] Focus indicators visible on all interactive elements
- [ ] Touch targets minimum 48x48px
- [ ] Primary action is the largest/most prominent element
- [ ] Button placement follows convention (primary bottom-right)
- [ ] Spacing follows 8px grid (8, 16, 24, 32, 40, 48, 64)
- [ ] Maximum 7 items in any list before pagination/scroll
- [ ] Empty states have friendly copy and a clear CTA
- [ ] Error messages tell the user what to DO, not what went wrong
- [ ] Success states feel rewarding (not just "done")
- [ ] Page passes the "1-second screenshot test"
