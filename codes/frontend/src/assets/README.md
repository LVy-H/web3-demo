# Image Asset Manifest — Dark Bauhaus

Curated for `ZK·BALLOT` UI. All assets are open-licence, no attribution required,
suitable for commercial use in this project.

## Illustrations — 18 SVGs, unDraw open licence

Source: <https://undraw.co/illustrations> — licence <https://undraw.co/license>
(open, free for commercial use, no attribution required; not MIT, not CC0).

Each SVG was downloaded from `cdn.undraw.co` and recoloured from undraw's default
purple (`#6c63ff`) plus dark line art to the Dark Bauhaus palette. See
`illustrations/recolor.sh` for the full colour map.

### Batch 1 — 8 illustrations (foundation set)

| File | unDraw slug | Primary recolour | Secondary recolours | App use |
|---|---|---|---|---|
| `voting.svg` | `voting_3ygx` | `#6c63ff → #ff3b5c` (segnale) | line art `#2f2e41 → #f5f7fa`; tint `#575a89 → #cc2e49`; green `#57b894 → #10ff8a` | Home hero — voting illustration occupies left columns of the landing grid |
| `secure-login.svg` | `secure-login_m11a` | `#6c63ff → #ff3b5c` | line art `→ #f5f7fa`; light bg `→ #2a3140` | Generate-identity state — identity & key flow |
| `verified.svg` | `verified_m721` | `#6c63ff → #ff3b5c` | line art `→ #f5f7fa`; light bg `→ #2a3140` | Privacy-receipt panel — ZK proof verified |
| `team.svg` | `team_85hs` | `#6c63ff → #ff3b5c` | line art `→ #f5f7fa`; light bg `→ #2a3140` | "About the pool" sidebar — community / connected voters |
| `empty.svg` | `empty_4zx0` | `#6c63ff → #4d7cff` (oltremare) | line art `→ #f5f7fa`; secondary line `#3f3d56 → #c9d0db`; light bg `→ #2a3140` | "No polls yet" empty state |
| `celebration.svg` | `celebration_wtm8` | `#6c63ff → #10ff8a` (success) | line art `→ #f5f7fa`; light bg `→ #2a3140` | After-vote success state |
| `mobile-encryption.svg` | `mobile-encryption_flk2` | `#6c63ff → #ff3b5c` | line art `→ #f5f7fa`; light bg `→ #2a3140` | Locked-feature placeholder — encryption / private detail |
| `loading.svg` | `loading_3kqt` | `#6c63ff → #4d7cff` (oltremare) | dark `#090814 → #f5f7fa`; light bg `→ #2a3140` | Confirming-on-chain state |

### Batch 2 — 10 illustrations (global-style expansion, P3-batch-2)

Selected so that every major app surface — browse, create, anon-vote, blind-vote
commit, blind-vote reveal, connect, results dashboard, DAO/group, docs, error —
has its own recoloured illustration. Sizing is context-sensitive (see below).

| File | unDraw slug | Primary recolour | Secondary recolours | App use |
|---|---|---|---|---|
| `browsing.svg` | `browsing_z5g5` | `#6c63ff → #ff3b5c` (segnale) | line art `#2f2e43 → #f5f7fa`; tint `→ #cc2e49`; light bg `#cbcbcb → #2a3140` | Browse polls page — small hero accent left of poll list |
| `creative-designer.svg` | `creative-designer_sctu` | `#6c63ff → #ff3b5c` | line art `→ #f5f7fa`; light bg `→ #2a3140`; pink accent `#ff6584` preserved | Create poll (admin) — hero illustration in form header |
| `authentication.svg` | `authentication_1evl` | `#6c63ff → #ff3b5c` | line art `→ #f5f7fa`; light bg `→ #2a3140` | Anon Vote (Poll.tsx) — privacy / shield accent in sidebar info panel |
| `alarm-clock.svg` | `alarm-clock_zgtg` | `#6c63ff → #4d7cff` (oltremare) | line art `→ #f5f7fa`; light bg `→ #2a3140` | Blind Vote — commit phase (time-lock visual) |
| `unlock.svg` | `unlock_m0yr` | `#6c63ff → #10ff8a` (success) | line art `→ #f5f7fa`; light bg `→ #2a3140` | Blind Vote — reveal phase (unlock visual) |
| `empty-wallet.svg` | `empty-wallet_j0kn` | `#6c63ff → #ff3b5c` | line art `→ #f5f7fa`; light bg `→ #2a3140` | Connect / onboarding hero — wallet illustration |
| `product-explainer.svg` | `product-explainer_b7ft` | `#6c63ff → #4d7cff` (oltremare) | line art `→ #f5f7fa`; light bg `→ #2a3140` | About / docs page — tutorial illustration |
| `alarm-ringing.svg` | `alarm-ringing_4deu` | `#6c63ff → #ff3b5c` | line art `→ #f5f7fa`; light bg `→ #2a3140` | Error / 404 state — alert visual |
| `collaboration.svg` | `collaboration_hkrb` | `#6c63ff → #ff3b5c` | line art `→ #f5f7fa`; light bg `→ #2a3140`; tint `→ #cc2e49` | DAO / group page — collaboration / team visual |
| `data-analysis.svg` | `data-analysis_b7cp` | `#6c63ff → #4d7cff` (oltremare) | line art `→ #f5f7fa`; light bg `→ #2a3140` | Results / dashboard page — analytics visual |

Skin tones (`#ffb6b6`, `#ffb7b7`, `#ffb8b8`, `#ffb9b9`, `#9e616a`, `#a0616a`,
`#9f616a`, `#ed9da0`, `#f8a8ab`, `#f1a1a4`) were intentionally left unchanged —
they read fine on the void background and replacing them would lose the human
warmth that distinguishes undraw illustrations from generic vector clip art.

Combined total size: ~158 KB across 18 SVG files.

## Per-app-state mapping (where each illustration appears)

The "global-style with contextual sizing" rule — same visual language everywhere,
scaled per page importance:

- **Hero / empty / success states** — large (300–500 px wide), illustration is the focus.
- **Functional pages** (vote decision, browse list, create form) — small accent (120–180 px), illustration is garnish.
- **Sidebar panels / info cards** — tiny (80–120 px), illustration is identification.

| App page / state | Illustration | Size class | Pattern backdrop |
|---|---|---|---|
| Home / dashboard hero | `voting.svg` | LARGE (400 px) | `dots-grid` |
| Browse polls — page header | `browsing.svg` | SMALL (160 px) | `diagonal-hairlines` |
| Browse polls — "treasury" row | `voting.svg` (reuse) | TINY (80 px) | — |
| Browse polls — "governance" row | `collaboration.svg` | TINY (80 px) | — |
| Browse polls — "tech" row | `data-analysis.svg` | TINY (80 px) | — |
| Browse polls — "community" row | `team.svg` | TINY (80 px) | — |
| Anon Vote (Poll.tsx) — privacy panel | `authentication.svg` | TINY (120 px) | `hex-grid` |
| Blind Vote — commit phase | `alarm-clock.svg` | MEDIUM (260 px) | `isometric-cube` |
| Blind Vote — reveal phase | `unlock.svg` | MEDIUM (260 px) | `isometric-cube` |
| Create Poll (admin) | `creative-designer.svg` | MEDIUM (300 px) | `diagonal-hairlines` |
| Connect / onboarding | `empty-wallet.svg` | LARGE (380 px) | `dots-grid` |
| Voted success | `celebration.svg` | LARGE (420 px) | `dots-grid` |
| Empty state — no polls | `empty.svg` | LARGE (400 px) | `dots-grid` |
| Empty state — no votes yet | `empty.svg` (variant) | MEDIUM (260 px) | `dots-grid` |
| Loading / confirming on-chain | `loading.svg` | MEDIUM (260 px) | `noise` |
| About / docs — hero | `product-explainer.svg` | MEDIUM (320 px) | `hex-grid` |
| About / docs — how-it-works card 1 | `secure-login.svg` | TINY (100 px) | — |
| About / docs — how-it-works card 2 | `verified.svg` | TINY (100 px) | — |
| About / docs — how-it-works card 3 | `mobile-encryption.svg` | TINY (100 px) | — |
| DAO / group page (future) | `collaboration.svg` | MEDIUM (300 px) | `hex-grid` |
| Error / 404 state (future) | `alarm-ringing.svg` | MEDIUM (260 px) | `diagonal-hairlines` |

The discipline is: every page gets ONE pattern from the 5-pattern set, rotated
across pages so the app has visual variety without breaking consistency.
Pattern opacity stays `0.04 – 0.08` (background, not decoration).

## Patterns — 5 inline SVGs, hand-authored (no source attribution needed)

All patterns use `--rule` (`#2a3140`) at low opacity (`0.55 – 0.9` on a `0.05 – 0.15`
visual range against the `--void` background). Each can be referenced as
`background-image: url('./patterns/<name>.svg')` with `background-repeat: repeat`,
or embedded inline in JSX.

| File | Pattern | Tile size | Visual density | Best for |
|---|---|---|---|---|
| `dots-grid.svg` | Single dot, centred | 40×40 | Lowest (sparse) | Hero backdrops, empty states, success states |
| `diagonal-hairlines.svg` | 45° hairlines | 24×24 | Medium | Section dividers, sidebars, create form |
| `hex-grid.svg` | Honeycomb outline | 56×100 | Medium | "ZK / privacy" themed sections, docs |
| `noise.svg` | Procedural film grain (`feTurbulence`) | 300×300 non-tiled | Variable, see opacity | Loading / processing overlays |
| `isometric-cube.svg` | Wireframe cube | 60×70 | Medium-high | Confirming-on-chain, blind-vote phases, technical panels |

## How to use in React (Vite)

```ts
// As <img src> — works out of the box, no plugin:
import votingHero from '@/assets/illustrations/voting.svg';
<img src={votingHero} alt="" role="presentation" />

// As component, recolourable via currentColor (requires vite-plugin-svgr or ?react suffix):
import VotingHero from '@/assets/illustrations/voting.svg?react';
<VotingHero className="hero-illo" />

// As CSS background:
.empty-state {
  background-image: url('@/assets/patterns/dots-grid.svg');
  background-repeat: repeat;
  background-size: 40px 40px;
}
```

## Recoloring later

The recolor script `illustrations/recolor.sh` is the single source of truth for
the colour map. To swap palettes (e.g. light theme), edit the `PRIMARY` /
`PRIMARY_TINT` arrays and re-run against the `.raw` originals (re-download with
`curl` from `cdn.undraw.co/illustration/<slug>.svg`).

The script handles two batches of source palettes:

- **Batch 1** (older undraw assets): `#2f2e41` line art, `#3f3d56` secondary,
  `#e6e6e6 / #f2f2f2 / #cacaca` light fills.
- **Batch 2** (newer undraw assets): `#2f2e43` line art, `#33323d / #464353`
  secondary, `#cbcbcb / #d6d6e3` light fills, `#514e7f` tint, `#707070` mid grey.

Both are mapped to the same destination palette so all 18 illustrations look
visually consistent on the void background.

For per-component runtime swaps, prefer the `?react` import + `currentColor`
strategy — but that requires editing the SVGs to use `currentColor` instead of
hex values, which is not done here (these are fixed-palette assets).

## Color tokens used (Dark Bauhaus)

```css
--void:      #0a0c10;  /* background */
--slate:     #1a1f2e;  /* surface */
--chalk:     #f5f7fa;  /* text + line art in illustrations */
--chalk-dim: #c9d0db;  /* secondary line art */
--rule:      #2a3140;  /* dividers + light backgrounds in illustrations */
--mute:      #7a8599;  /* mid-grey accents */
--segnale:   #ff3b5c;  /* primary accent */
--oltremare: #4d7cff;  /* secondary accent (empty / loading / time states) */
--success:   #10ff8a;  /* success state (reveal / celebration) */
```
