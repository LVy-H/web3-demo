/**
 * Dark Bauhaus 4-rotation palette for per-option colour coding on the
 * anonymous-vote Poll page. Used by `VoteShowdownCard`, `OptionShowdownCard`,
 * `ResultsBarsDb`.
 *
 * Rotation: green-success → red-segnale → blue-oltremare → amber. Indexed by
 * option position (mod 4). Returns FULL Tailwind utility strings so the
 * Tailwind v4 JIT class scanner picks them up — dynamic `text-${token}`
 * interpolation does NOT survive class extraction.
 *
 * The legacy 10-colour `OPTION_BAR_COLORS` (in `optionColors.ts`) remains in
 * the codebase for `BlindPoll.tsx`.
 */

import { Check, X, Triangle, Circle, type LucideIcon } from 'lucide-react'

export interface OptionColor {
    /** Tailwind text-color utility, e.g. `text-db-success`. */
    text: string
    /** Tailwind background-color utility, e.g. `bg-db-success`. */
    bg: string
    /** Tailwind border-color utility, e.g. `border-db-success`. */
    border: string
    /** Tinted background utility for "selected" card fill, e.g. `bg-db-success/15`. */
    bgTint: string
    /** Raw hex value (useful for inline-styled SVG fills). */
    hex: string
    /** Lucide stamp icon shown in the top-left of an option card. */
    Icon: LucideIcon
}

const PALETTE: ReadonlyArray<OptionColor> = [
    {
        text: 'text-db-success',
        bg: 'bg-db-success',
        border: 'border-db-success',
        bgTint: 'bg-db-success/15',
        hex: '#10ff8a',
        Icon: Check,
    },
    {
        text: 'text-db-segnale',
        bg: 'bg-db-segnale',
        border: 'border-db-segnale',
        bgTint: 'bg-db-segnale/15',
        hex: '#ff3b5c',
        Icon: X,
    },
    {
        text: 'text-db-oltremare',
        bg: 'bg-db-oltremare',
        border: 'border-db-oltremare',
        bgTint: 'bg-db-oltremare/15',
        hex: '#4d7cff',
        Icon: Triangle,
    },
    {
        text: 'text-amber-500',
        bg: 'bg-amber-500',
        border: 'border-amber-500',
        bgTint: 'bg-amber-500/15',
        hex: '#f59e0b',
        Icon: Circle,
    },
]

export function getOptionColor(index: number): OptionColor {
    // Defensive — JS `%` can be negative for negative ints; clamp.
    const i = ((index % PALETTE.length) + PALETTE.length) % PALETTE.length
    return PALETTE[i]!
}
