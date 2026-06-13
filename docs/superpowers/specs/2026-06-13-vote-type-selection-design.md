# Vote-type selection redesign — CREATE flow

Date: 2026-06-13 · Space: ORGANIZE · File: `feature_organize/.../create/create_flow_view.dart`

## The problem

The CREATE form's `_modulePicker()` rendered all six `OrganizerModule` values as a
flat `Wrap` of equal `OutlinedButton` chips, and the explanatory `moduleBlurb`
appeared **only for the already-selected** chip. Three concrete failures:

1. **No comparison before choosing.** The differentiator a first-time organizer
   needs ("when do I rank vs. approve?") was hidden until *after* they'd already
   committed to a guess — so the picker taught nothing.
2. **No grouping / guidance.** Six peer chips with no goal framing; the organizer
   has to already know the jargon to navigate.
3. **A category error.** "Sealed until reveal" (`blindVote`) is a **result-timing**
   property of single-choice voting, not a peer ballot mechanic — yet it sat as a
   sixth equal chip. `blindVote` is literally the `anonVote` ballot (pick-one, no
   questions, no 8-cap) with a reveal window. Listing it as a type implied you
   could "rank, sealed" or "survey, sealed" — which the contracts cannot do.

## Approach (research-backed)

Two well-established selection patterns:

- **Goal-first grouping** (progressive disclosure / "choose by intent"): group
  options under the *outcome the user wants*, not the engine name — the same move
  Stripe/Typeform make for "what are you trying to do?" pickers. Lowers the
  knowledge bar to zero jargon.
- **Always-visible differentiators with a sane default** (radio-card pattern,
  Nielsen Norman "card sort / comparison" guidance): show every option's
  one-liner at all times so the choice is a comparison, not a memory test, and
  pre-select the safe default so the organizer is never staring at an empty
  picker.
- **Property-as-toggle, not as-type**: a cross-cutting property (sealing) belongs
  on the type it modifies as a switch, never as a fake peer — this is what kills
  the category error and the impossible "sealed survey" combinations.

## The design (shipped — P1)

Replace the flat `Wrap` with **goal-grouped radio cards**; "Pick one" pre-selected.
The picker offers **five ballot types** (NOT `blindVote`).

**DECIDE ON A WINNER**
- **Pick one** (`anonVote`) — badge *Recommended* — "Everyone picks one option;
  most votes wins. Best for two clear choices."
- **Rank them** (`rankedVote`) — "Voters put options in order; finds a true
  majority — avoids vote-splitting when 3+ options are similar."
- **Approve any** (`approvalVote`) — "Voters tick every option they'd accept; the
  most broadly liked wins."

**GATHER OPINIONS**
- **Questionnaire** (`surveyVote`) — "Several questions at once — collects
  answers, not a single winner."

**PRIORITIZE & ALLOCATE**
- **Split 100 points** (`quadraticVote`) — badge *Advanced* — "Voters spread a
  budget to show how much they care — caring a lot costs more."

Each card always shows its differentiator (`dbSans(12,400,chalkDim)`); selected
state is a radio glyph + `Db.segnale` border + `Db.slate2` fill, name in `Db.chalk`
when selected else `Db.chalkDim`. Group headers reuse the `_label(...)` style.

**Sealing toggle** (replaces the `blindVote` card): rendered **only when "Pick
one" is selected** — a switch row *"Hide results until voting closes"* / *"Early
votes can't sway later ones."* When ON, the effective deployed module becomes
`OrganizerModule.blindVote` and the existing `_revealWindowPicker()` appears.

### State / `_effectiveModule`

The single `_module` field is replaced by `_ballotType` (one of the five
non-blind values, default `anonVote`) + `_sealed` (bool, default false):

```dart
OrganizerModule get _effectiveModule =>
    (_ballotType == OrganizerModule.anonVote && _sealed)
        ? OrganizerModule.blindVote
        : _ballotType;
```

`_effectiveModule` drives the built spec (`module:`), the reveal window
(`_effectiveModule == blindVote`), and the `usesQuestions` / `capsOptionsAtEight`
branches. `blindVote` is therefore reachable **only** via Pick one + toggle.

### No-ghost sealing constraint

The toggle is **never rendered** for ranked/approval/survey/quadratic — not even
disabled. The contracts seal single-choice voting only; offering a greyed toggle
would imply a "sealed ranked" combination that cannot be deployed. Switching away
from Pick one simply removes the toggle; `_sealed` is ignored by
`_effectiveModule`, so the effective module is always a valid combination.

> Known downstream limit (out of this change's scope): `RelayOrganizerPort.deployPoll`
> still refuses `blindVote` with a typed honest failure (sponsored allow-list
> excludes it). So the UI now lets organizers *build* a sealed Pick-one and see
> the reveal-window control, but a deploy attempt surfaces the existing
> "Sealed-until-reveal polls can't be created from this app yet" message. Wiring
> sealed creation end-to-end is tracked separately (R5 sealed-ballots).

## P2 follow-ups

- **Guided "what's your goal?" chooser** — an optional first step that asks the
  intent in plain words and lands the organizer on the right group/card.
- **Voter ballot preview** — a tiny live mock of what a voter will see for the
  selected type, so the organizer can confirm the experience before deploying.
