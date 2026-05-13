/**
 * Dark Bauhaus per-option-index palette for the CreatePoll form-builder.
 *
 * Used by the form's option list and live-preview sidebar to colour the
 * per-index numeral. Cycles every 4 entries: success-green → segnale-red →
 * oltremare-blue → amber.
 *
 * Returns FULL Tailwind utility strings (not tokens) so the Tailwind v4 JIT
 * scanner can pick them up — dynamic `text-${token}` interpolation does NOT
 * survive class extraction.
 *
 * Distinct from any per-option palette the Poll/BlindPoll result charts may
 * eventually consume — the result-chart variant needs `Icon` + `bgTint`
 * fields this helper does not surface. Keeping them in separate modules
 * avoids a contract clash.
 */

export interface OptionTone {
    /** Tailwind text-color utility, e.g. `text-db-success`. */
    text: string
    /** Tailwind background-color utility, e.g. `bg-db-success`. */
    bg: string
    /** Tailwind border-color utility (left-rule etc), e.g. `border-db-success`. */
    border: string
}

const PALETTE: readonly OptionTone[] = [
    { text: 'text-db-success', bg: 'bg-db-success', border: 'border-db-success' },
    { text: 'text-db-segnale', bg: 'bg-db-segnale', border: 'border-db-segnale' },
    { text: 'text-db-oltremare', bg: 'bg-db-oltremare', border: 'border-db-oltremare' },
    { text: 'text-amber-400', bg: 'bg-amber-400', border: 'border-amber-400' },
] as const

export function getOptionTone(index: number): OptionTone {
    // Defensive — % can be negative for negative ints; clamp.
    const i = ((index % PALETTE.length) + PALETTE.length) % PALETTE.length
    return PALETTE[i]!
}
