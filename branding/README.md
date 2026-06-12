# Tessera Brand Identity

A *tessera* is a single square tile in a mosaic — small on its own, meaningful
in aggregate. That is exactly how private voting works: each ballot is one
anonymous tile, and only the assembled mosaic (the tally) is ever visible.

## The mark

`tessera-mark.svg` — a 3×3 grid of square tiles on ink. Eight tiles sit flush
in the grid (chalk and mute); **exactly one tile is segnale red, nudged out of
the grid and rotated 8°** — the one anonymous voice that still counts. The
grid stays orderly; the individual stays unidentifiable.

Constraints honored:

- **Pure `<rect>` elements.** No gradients, no curves, no paths. The only
  transform is the 8° rotation on the segnale tile.
- **Legible at 16 px and 512 px** (verified by rasterizing with resvg): at
  16 px it reads as a tile grid with a red corner dot; at 512 px the offset
  and rotation are explicit.
- Square geometry throughout — Dark Bauhaus has no rounded corners.

## Files

| File | Use |
| --- | --- |
| `tessera-mark.svg` | Primary mark, light-on-ink. Favicons, app icons, avatars. |
| `tessera-mark-inverse.svg` | Dark-on-chalk for light surfaces / print. Segnale stays segnale. |
| `tessera-logo.svg` | Horizontal lockup: mark + TESSERA wordmark. Headers, splash, docs. |

## Wordmark: rect letterforms (documented choice)

The wordmark is **hand-built rect letterforms**, not text-to-path. Each glyph
sits on a squared 5×7 stencil grid (unit u = 14 px, tracking 3u — the wide
tracking mirrors `dbLabel`'s 0.18 em). The S and R are squared off; the R's
leg is a rect staircase (stepped diagonal) so it cannot be misread as A.

Why rects instead of text-to-path:

1. Zero font dependency — renders identically everywhere, no Inter outlines
   embedded, no license ambiguity about converted glyphs.
2. The letterforms themselves are tesserae: type built from the same square
   atoms as the mark. The brand is the construction method.

## Color tokens (source of truth: `codes/app/packages/design_system/lib/theme.dart`)

| Token | Hex | Role in the brand |
| --- | --- | --- |
| `Db.void_` (ink) | `#0A0C10` | Background of mark and logo; web theme/background color |
| `Db.chalk` | `#F5F7FA` | Tile fill, wordmark, inverse background |
| `Db.mute` | `#7A8599` | Two quieter tiles — mosaic texture |
| `Db.segnale` | `#FF3B5C` | The one offset tile. Never more than one red tile. |
| `Db.slate` | `#1A1F2E` | Surface color in-app (too low-contrast on ink for icon tiles) |

## Usage rules

- Exactly **one** segnale tile, always at the top-right, always offset/rotated.
  Do not recolor other tiles red; do not straighten it.
- Keep the mark on `#0A0C10` (or `#F5F7FA` for inverse). No other backgrounds.
- Maskable / safe-zone icons: scale the 9-tile grid to ≤ 60 % of the canvas,
  centered, ink background bleed to the edges.
- In-app, use the `TesseraMark` widget from `design_system` (paints the same
  geometry from `Db` tokens — no SVG asset dependency).
- The wordmark is always uppercase, always wide-tracked. Body copy uses
  "Tessera" in Inter.

## Geometry reference (512 viewBox)

- Tile: 112×112, gap 24, grid origin (64, 64).
- Segnale tile: grid position (row 0, col 2) translated (+10, −14), rotated 8°
  about its own center (402, 106).
