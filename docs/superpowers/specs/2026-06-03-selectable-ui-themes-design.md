# Tessera — Selectable UI Themes — Design

> **Date:** 2026-06-03 · **Owner:** Hoang · **Status:** approved, pre-implementation
> Product-polish lane under ROADMAP Phase 9 (`docs/project/ROADMAP.md:96` already
> lists **Settings → theme**). Builds in its own worktree. Spec only — no code here.

## Goal

Let the user pick from a small set of **curated UI themes** (e.g. the current Dark
Bauhaus, a Light Bauhaus, and one or two accent variants) from **Settings**,
applied **app-wide immediately** on selection and **persisted** across restarts.
This is the "More Theme" item from the feature wishlist.

The whole visual system today flows through one file —
`codes/mobile/lib/ui/core/theme.dart` — via the `abstract class Db` colour
tokens (`Db.void_`, `Db.segnale`, …), the text-style helpers
(`dbSans`/`dbMono`/`dbLabel`/`dbHero`/`dbSectionTitle`), and the single
`buildDarkBauhausTheme()` `ThemeData` (`theme.dart:107`). All of these currently
bake **compile-time `static const`** colours. Making the theme selectable means
making those colours **resolve at runtime** against an active palette. **Which
mechanism does the swap** is the load-bearing decision, so it leads.

---

## Decisions & alternatives (read this first)

One fork decides the whole shape of the change. Each option is a crisp either/or
with the chosen one marked, so a reviewer can redirect the plan by flipping a
single decision before any code is written. The recommendation is **driven by the
measured const-churn count** (below), exactly as the brief asked.

### The measured cost that drives the decision

`Db.*` is used **713 times across 21 files** (`grep -rn 'Db\.' codes/mobile/lib`).
The number that matters is **how many of those sit inside a `const` expression** —
because any approach that makes the colours non-`const` must edit every one of
those sites.

That count was obtained **empirically, not by grep** (grep cannot see Dart's
*implicit* const propagation — e.g. `const [Icon(color: Db.x)]` makes the `Icon`
const with no `const` keyword on its line). Method: in a throwaway edit, flip only
the `Color` fields of `Db` from `static const` to `static final` (Strings/lists
like `fontSans`/`categoryLabels` left `const` — Approach A doesn't touch them),
run `flutter analyze lib`, count the constant-evaluation errors per file, then
`git checkout` the file. Result:

| Error code | Count | What it is |
|---|---|---|
| `invalid_constant` | **205** | a `Db.*` colour used inside a `const` widget/expr — **rote fix:** drop the `const` keyword from that subtree |
| `non_constant_default_value` | **3** | a `Db.*` colour used as an **optional-parameter default** — **not** a rote drop (see below) |
| `const_initialized_with_non_constant_value` | **1** | `const scheme = ColorScheme.dark(...)` in `theme.dart` — drop `const` (it's rebuilt per-theme anyway) |
| **Total const edit-sites** | **209** | the exact churn of Approach A, implicit-const cases included |

So **~209 of 713 (≈29%) usages are const-context edit-sites**; the other **~504
are already non-`const`** (runtime `BoxDecoration`, conditional colours,
`.withValues(alpha:)`, builder bodies) and need **no change at all** under
Approach A. The 209 spread across 19 files; the heaviest are the per-type poll
screens (`survey_poll` 26, `ranked_poll`/`quadratic_poll` 25 each, `poll_detail`
23, `approval_poll` 22) — mostly `const Icon(... color: Db.x)`, `const
Divider(color: Db.rule)`, `const BorderSide(color: Db.rule)`, `const
BoxDecoration(color: Db.slate, …)`.

> **The 3 non-rote sites (call these out — they are the only non-mechanical
> churn):** a `Db.*` colour used as an **optional-parameter default value** must
> be a compile-time constant, so "drop `const`" does not apply — the parameter has
> to become nullable and resolve in the body (`color ??= Db.mute`). All three:
> - `theme.dart:92` — `dbLabel({Color color = Db.mute, …})`
> - `browse_screen.dart:323` — `_Pill(…, {this.activeColor = Db.slate})`
> - `live_vote_screen.dart:215` — `_banner(…, {Color color = Db.segnale})`
>
> Pattern for each: change to `{Color? color}` and resolve `color ?? Db.<role>`
> at the use site. Three small, well-understood edits — not a blocker, but they
> are the part of the migration a reviewer should eyeball.

### The fork

| Option | What it is | Trade-offs |
|---|---|---|
| **A — swappable palette behind the `Db` accessors (CHOSEN)** | Convert `Db`'s `static const` colour fields to `static Color get` accessors that read from a mutable `_current` `DbPalette`. A `ThemeController` (`ChangeNotifier`) swaps `_current` + persists the choice; the root wraps `MaterialApp` in a `ListenableBuilder` so a swap rebuilds the app. | **Every `Db.segnale`-style call site is unchanged** (713 reads keep working as-is). The only churn is the **209 const edit-sites** measured above (206 rote + 3 default-value), plus rebuilding `theme.dart`'s `ThemeData`/`ColorScheme` from the active palette. **Cost:** colours become non-`const` (the const drops); a deliberate rebuild trigger is needed (the `ListenableBuilder`); one piece of static mutable state (`Db._current`) — acceptable and contained, set once before first paint and on each user swap. |
| B — `ThemeExtension<DbColors>` on `ThemeData` | The idiomatic Flutter way: register a `ThemeExtension<DbColors>` per theme, resolve colours via `Theme.of(context).extension<DbColors>()!.segnale`. | Idiomatic, reactive, **no static mutable state**. **But it touches ALL ~713 call sites** (every `Db.color` → a `context`-based lookup), and needs a `BuildContext` *everywhere a colour is read* — including the **non-widget** code that has none today: the text-style helpers `dbSans`/`dbMono`/`dbLabel`/`dbHero`/`dbSectionTitle` (pure functions, `theme.dart:54–104`), `Db.optionColor(i)`/`Db.categoryColor(i)`, and painters like `dot_grid_background.dart`/`watermark.dart`. Those would all have to be restructured to take a `context`/`DbColors` argument and re-thread it through every caller. A ~3.4× larger, riskier mechanical refactor for the same user-visible result. |
| C — multiple full `ThemeData` objects selected at the root | Build N `ThemeData`s and switch `MaterialApp.theme` by the chosen index. | Trivially reactive at the root, but **does not solve the problem**: the app reads `Db.*` **directly**, not through `Theme.of(context)` — only a handful of Material widgets pick colours up from `ThemeData`. The 713 `Db.*` reads would still show Dark-Bauhaus colours regardless of which `ThemeData` is active. To make C actually work you must *also* make `Db` swappable — i.e. you're back to A (and then the multiple `ThemeData`s are just A's per-palette `buildTheme(palette)`). C alone is rejected. |

### Recommendation: **Approach A**

A is **dramatically less churn** (209 edit-sites, 206 of them rote `const`-drops,
vs. B's ~713 call-site rewrites **plus** restructuring every non-widget helper to
carry a `BuildContext`) for an **identical** user-visible outcome. The const count
came in at ≈29% of usages — squarely in the "manageable, mostly rote" range, not
the "ugly" range that the brief said would flip the recommendation. The two
theoretical wins of B — idiomatic `ThemeExtension`, no static mutable state — do
not justify a 3.4× larger refactor that drags `BuildContext` into pure helper
functions. **A is chosen; B/C are the alternatives, documented for a reviewer who
wants to flip.**

> Honesty about A's one real smell: `Db._current` is **static mutable state**.
> This is contained — it is written in exactly two places (once at startup before
> `runApp`, and inside `ThemeController.select`), always on the UI isolate, and
> every read is a plain field read. It is the same shape as any app-singleton
> palette. The risk it introduces (a colour read *before* the palette is set)
> is eliminated by initialising `_current` to the default palette as its field
> initialiser, so `Db.*` is **never** null even before startup runs.

---

## Design (Approach A)

### The palette object

A `DbPalette` immutable value object names **every colour role** that `Db`
exposes today, so a theme is exactly one `DbPalette`:

```
class DbPalette {
  final Color void_, slate, slate2, slateDim, slate3, slate4;   // surfaces
  final Color chalk, chalkDim, mute, muteDim;                    // text
  final Color rule, ruleSoft;                                    // borders
  final Color segnale, segnaleD, oltremare, success, amber;      // signals
  final Color catGovernance, catTreasury, catTech, catSocial;    // category hues
  final Brightness brightness;                                   // drives ThemeData
  const DbPalette({ required … });
}
```

Each named theme is a `const DbPalette(...)` constant (so the *palettes
themselves* stay compile-time const — only the live `Db._current` pointer is
mutable). The role set is **complete** — it is the literal field list of today's
`Db` (`theme.dart:7–29`), the `_optionColors`/`_categoryColors` lists
(`theme.dart:35,40`), nothing more.

### `Db` becomes accessors over `_current`

`Db`'s `static const <role> = Color(...)` fields become `static Color get
<role> => _current.<role>;`, backed by:

```
static DbPalette _current = TessThemes.darkBauhaus;   // default, never null
```

- `Db.optionColor(i)` / `Db.categoryColor(i)` read the now-dynamic role getters
  (the `_optionColors`/`_categoryColors` lists are rebuilt from `_current`, or
  replaced by small switch-on-`i` helpers — either way no const list).
- `Db.fontSans` / `Db.fontMono` / `Db.categoryLabels` / `Db.categoryFor(addr)`
  **stay `static const`** — fonts and category metadata are **not** themed in v1.
  (Keeping them const is also why the measured churn is only the colour sites.)

### Text styles + `ThemeData` pick up the active palette automatically

- `dbSans`/`dbMono` already **take a `Color` argument** — callers pass `Db.chalk`
  etc., which now resolves dynamically. **No signature change.**
- `dbLabel`/`dbHero`/`dbSectionTitle` reference `Db.mute`/`Db.chalk` **internally**
  (`theme.dart:92,100,104`). Once those are getters, the helpers read the active
  palette every call. The **only** edit is `dbLabel`'s **default-param** `Color
  color = Db.mute` → `{Color? color}` + `color ?? Db.mute` in the body (one of the
  3 non-rote sites above). `dbHero`/`dbSectionTitle` use `Db.chalk` in the body,
  not as a default, so they need no change.
- `buildDarkBauhausTheme()` (`theme.dart:107`) generalises to
  **`ThemeData buildTheme(DbPalette p)`**: it builds `ColorScheme` +
  `scaffoldBackgroundColor` + `appBarTheme` + `dividerColor` + `textTheme` from
  `p` (using `p.brightness` for `ColorScheme.light`/`.dark`) instead of the baked
  `Db.*` constants. The `const scheme`/`const AppBarTheme` lose their `const`
  (the 1 `const_initialized_with_non_constant_value` + a couple of the
  `invalid_constant` sites land here). `buildDarkBauhausTheme()` can stay as a
  thin `=> buildTheme(TessThemes.darkBauhaus)` for any existing caller.

### The controller + reactive root

```
class ThemeController extends ChangeNotifier {
  ThemeController(this._store);
  TessThemeId get current;                 // the selected theme id
  Future<void> load();                     // read persisted id → set Db._current (startup)
  Future<void> select(TessThemeId id);     // set Db._current + persist + notifyListeners()
}
```

- `select` sets `Db._current = TessThemes.byId(id)`, persists the id, and
  `notifyListeners()`.
- The root (`main.dart`) exposes the controller (it already uses `provider` —
  add a `ChangeNotifierProvider<ThemeController>`, mirroring the existing
  `ChangeNotifierProvider<WalletService>` at `main.dart:173`) and wraps the
  `MaterialApp.router` in a **`ListenableBuilder`** (listening to the controller)
  so a swap rebuilds the app with `theme: buildTheme(palette-for-current)`. Both
  `MaterialApp.theme` **and** the live `Db.*` reads then reflect the new palette
  in the same frame.

### Persistence + no-flash startup

**Finding flagged — the task's premise is partly wrong, and the spec must decide
it explicitly.** The brief says to "mirror how network/relayer settings persist."
They **do not persist**: `AppConfig.rpcUrl`/`relayerUrl`/`registryAddress` are
**compile-time** `String.fromEnvironment` (`config.dart:5–20`), and
`settings_screen.dart` is **read-only diagnostics** — it writes nothing. There is
no settings store to mirror, and **`shared_preferences` is not a current
dependency** (the only persistence in the app is `flutter_secure_storage`, used
for the identity seed and blind commits). **The theme is therefore the app's
first runtime-persisted user preference**, and the persistence layer is new.

Decision — **reuse the repo's existing store pattern, do not add a new
dependency.** Model a `ThemeStore` exactly like `IdentityStore`
(`identity_store.dart`): an abstract interface + a production impl backed by
`flutter_secure_storage` (already in `pubspec.yaml:54`; it stores a plain string
fine — the theme id is not secret, but the dependency is already present and the
pattern is established) + an `InMemoryThemeStore` fake for tests/previews.

```
abstract class ThemeStore {
  Future<TessThemeId?> read();
  Future<void> write(TessThemeId id);
}
class SecureThemeStore implements ThemeStore { … key 'tessera.theme.id' … }
class InMemoryThemeStore implements ThemeStore { … }
```

> Alternative for the reviewer: if a non-secure, conventional preferences store is
> preferred, add `shared_preferences` and back `SecureThemeStore` → `PrefsThemeStore`
> instead. Flagged because it is a genuine choice and adds a dependency; the
> recommendation is to reuse `flutter_secure_storage` (zero new deps).

**No-flash startup:** `main()` is **already `async`** (`main.dart:33`, it awaits
ABI bundle loads before `runApp`). The chosen theme loads **before first paint**:
in `main()`, after `WidgetsFlutterBinding.ensureInitialized()`, `await
themeController.load()` (which sets `Db._current` from the persisted id) **before**
`runApp(...)`. The first frame therefore paints the correct palette — no flash of
the default theme. If `load()` finds nothing persisted, the default
(`TessThemes.darkBauhaus`) is already in place, so the first-run experience is the
current app exactly.

---

## v1 theme set

Four curated themes ship in v1. Each is a complete `DbPalette` (all roles named
above). **No user-custom colour pickers in v1** (out of scope, below).

| Id | Theme | Brightness | What it is |
|---|---|---|---|
| `darkBauhaus` | **Dark Bauhaus** (DEFAULT) | dark | The **current** palette verbatim (`theme.dart:7–29`) — `void_` page, signal-red `segnale`, Inter/JetBrains-Mono. The default so the app looks identical until a user opts in. |
| `lightBauhaus` | **Light Bauhaus** | light | The hard one (see caveat). Paper/ink inversion of the Bauhaus system — light surfaces, dark text, signal-red retained as the accent but **contrast-re-derived**, not numerically inverted. |
| `signalBlue` | **Signal Blue** (dark accent variant) | dark | The Dark Bauhaus surfaces/text **unchanged**, but the primary signal role swapped from red to the existing `oltremare` blue family (a re-tuned blue as `segnale`/`segnaleD`). Demonstrates an accent-only variant cheaply (only signal roles differ). |
| `signalAmber` | **Signal Amber** (dark accent variant) | dark | Same idea — Dark Bauhaus surfaces, an amber/gold signal accent. (If a reviewer wants only **3** themes, drop this one; it is the lowest-value member and the easiest cut.) |

> **Light Bauhaus contrast caveat (load-bearing — flag for design + QA).** A
> light theme is **not** an inversion of the dark palette. Every role must be
> **re-derived** for adequate contrast on light surfaces, not flipped:
> - **Text** (`chalk`/`chalkDim`/`mute`/`muteDim`): today these are light-on-dark
>   (`chalk = #F5F7FA`). On a light surface they must become **dark inks** with a
>   deliberate hierarchy — a naive invert yields muddy, low-contrast greys.
> - **Surfaces** (`void_`/`slate`/`slate2`/`slateDim`/`slate3`/`slate4`): six
>   near-black tones today; need six **near-white/paper** tones whose *relative*
>   ordering (page < card < panel) is preserved while each clears the text above
>   it at WCAG AA.
> - **Signals** (`segnale`/`oltremare`/`success`/`amber`): the dark-mode neons
>   (`success = #10FF8A`, `segnale = #FF3B5C`) are **too light** to read as text or
>   thin rules on white — they must be **darkened/desaturated** so they hold
>   contrast against paper, while staying recognisably the same hue.
> - **Borders** (`rule`/`ruleSoft`): hairlines that are *lighter* than the dark
>   surfaces today must become *darker* than the light surfaces.
>
> This is genuine design work, not a transform. The spec mandates each Light role
> be chosen for ≥ WCAG AA contrast against the surface it sits on, and that the
> **full-screen Light-mode visual audit** is the headline manual-QA item (below).

---

## The picker UI (Settings)

`settings_screen.dart` is today a read-only `ListView` of `_section(...)` groups.
Add an **`APPEARANCE`** section above `ABOUT`, consistent with the existing
`_section`/`_row` Bauhaus styling:

- A **theme selector**: a list (or segmented control) of the four themes, each row
  showing the theme **name** + a **live preview swatch** — a tiny sample
  rendering its `void_`/`slate` surface with its `segnale`/`success` signal dots,
  so the user sees the palette before choosing.
- The current selection is **checked/highlighted**.
- Tapping a row calls `context.read<ThemeController>().select(id)` →
  **applies app-wide immediately** (the `ListenableBuilder` root rebuilds; the
  Settings screen itself re-themes live, giving instant feedback) and **persists**.
- No "Apply"/"Save" button — selection is the commit (matches the app's other
  one-tap interactions).

---

## Verification

- **Widget test — apply + persist:** with an `InMemoryThemeStore` fake and the
  controller, render Settings, tap a non-default theme, and assert a **sampled
  widget's resolved colour changes** (e.g. a probe `Db.segnale` / a known themed
  element goes from the Dark to the selected value). Then assert the store now
  holds the selected id, construct a **fresh** controller over the **same** fake
  store, `await load()`, and assert `Db._current` is the persisted theme — i.e.
  the choice **survives a restart**.
- **Widget test — no-flash startup:** with the fake store pre-seeded to a
  non-default theme, run the `load()`-before-`runApp` path and assert the **first**
  built frame already resolves the persisted palette (no default-then-swap).
- **Smoke — every screen renders under each theme:** pump each top-level screen
  (browse, poll detail, the per-type poll screens, live host/vote, identity,
  create, settings) under each of the four palettes and assert no exceptions /
  no overflow. This catches missed const-drops and any colour that hard-codes a
  Dark assumption.
- **`flutter analyze` clean** — in particular **zero** `invalid_constant` /
  `non_constant_default_value` / `const_initialized_with_non_constant_value`
  errors remain (the 209 measured here must all be resolved; this command is the
  authoritative checklist for the migration).
- **Honesty bar — manual QA is the real cost.** Automated tests prove *switching
  works and persists* and that screens *render without crashing*; they do **not**
  prove every screen *looks right* under **Light Bauhaus**. A **full visual audit
  of every screen in Light mode** — contrast of every text/surface/signal pairing,
  the painters (`dot_grid_background`, `watermark`), disabled/empty/error states,
  and the decorative `.withValues(alpha:)` overlays in `watermark.dart:55–57` —
  is the **headline manual-QA item** and is **not** covered by the widget tests.
  This is called out so it is scheduled, not discovered.

---

## Out of scope (explicitly)

- **User-custom colours** — no colour pickers, no per-role overrides, no
  user-defined themes in v1. Themes are a curated, finite set. (A future "custom
  palette" feature would extend `DbPalette` construction to a user editor — the
  `DbPalette` object is the seam, but it is not built here.)
- **Per-poll / per-category theming** — one app-wide theme; polls don't carry
  their own theme.
- **Animated theme transitions** — the swap is an immediate rebuild, not a
  cross-fade/tween.
- **Theming the typography** (`fontSans`/`fontMono`) or **category metadata**
  (`categoryLabels`/`categoryFor`) — fonts and categories stay const in v1.
- **System / auto (follow-OS) theme** — v1 is an **explicit** user choice only;
  a "Match system" option is a natural follow-up (read `MediaQuery.platformBrightness`)
  but is not v1.

## Done-when

- Settings has an **Appearance** section with the four-theme picker (name +
  live swatch, current selection highlighted); tapping a theme applies it
  **app-wide immediately** and **persists**.
- The chosen theme **loads before first paint** on startup (no flash); default is
  **Dark Bauhaus** and a fresh install looks identical to today.
- All **209** const edit-sites resolved; **`flutter analyze` clean**; the apply +
  persist + no-flash widget tests are green; every top-level screen smoke-renders
  under all four themes.
- The Light-Bauhaus full-screen visual audit is logged as the tracked manual-QA
  item.

## Open calls flagged for the reviewer

- **Exact v1 theme set (guessed).** The brief asked for "3–4 curated themes,
  e.g. Dark Bauhaus + Light Bauhaus + 1–2 accent variants" but did not name the
  accent hues. This spec proposes **Dark Bauhaus (default) + Light Bauhaus +
  Signal Blue + Signal Amber**. The two accent variants are reuse-cheap (only the
  signal roles change). Flip to **3 themes** by dropping Signal Amber, or swap the
  accent hues, with no structural impact — the set is data, not architecture.
- **Persistence backend (decided: reuse `flutter_secure_storage`, zero new deps).**
  The theme id is not secret; `shared_preferences` would be the conventional store
  but is **not** a current dependency. Reusing the existing `IdentityStore`-shaped
  secure store keeps the dependency set unchanged. Flip to adding
  `shared_preferences` only if a non-secure prefs store is explicitly wanted.
- **Roadmap premise correction (flagged).** `ROADMAP.md:96` lists Settings as
  persisting "network/relayer/theme"; network/relayer are **compile-time env**,
  not persisted, and Settings is read-only today. The theme is the **first**
  runtime-persisted preference — this spec builds that persistence layer rather
  than mirroring a non-existent one.
</content>
