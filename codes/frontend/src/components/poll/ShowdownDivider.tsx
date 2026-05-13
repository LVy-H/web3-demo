import { getOptionColor } from '../../lib/pollOptionPalette'

/**
 * Centre column of the binary showdown — renders the `VS` label and the live
 * numeric delta. The delta colour follows whichever option is leading; if
 * tied, falls back to `text-db-mute`.
 */
export function ShowdownDivider({
    countA,
    countB,
}: {
    countA: number
    countB: number
}) {
    const delta = Math.abs(countA - countB)
    const leader = countA === countB ? null : countA > countB ? 0 : 1
    const leaderColor =
        leader === null ? 'text-db-mute' : getOptionColor(leader).text
    const sign = leader === null ? '±' : '+'

    return (
        <div className="flex flex-col items-center justify-center bg-db-slate-2 border-y border-db-rule py-6">
            <span className="font-sans font-extrabold text-[14px] tracking-[0.18em] text-db-mute uppercase">
                VS
            </span>
            <span
                className={`font-mono text-[11px] mt-2 tabular-nums ${leaderColor}`}
            >
                {sign}
                {delta}
            </span>
        </div>
    )
}
