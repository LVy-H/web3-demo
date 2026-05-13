import { getOptionColor } from '../../lib/pollOptionPalette'

/**
 * Single option card inside the binary `VoteShowdownCard` (showdown variant)
 * or the ranked-row fallback when ≥3 options (row variant). Colour + stamp
 * icon come from {@link getOptionColor} keyed by the option's index, so
 * options stay visually stable across rerenders.
 *
 * - `selected`: this is the picked option (full border + tinted bg + PICKED ribbon).
 * - `hasSelection` + `!selected`: dim to 50% to focus the picked option.
 */
export function OptionShowdownCard({
    index,
    label,
    count,
    pct,
    selected,
    hasSelection,
    onClick,
    variant,
    pollAddrShort,
}: {
    index: number
    label: string
    count: number
    pct: number
    selected: boolean
    hasSelection: boolean
    onClick: () => void
    variant: 'showdown' | 'row'
    pollAddrShort: string
}) {
    const palette = getOptionColor(index)
    const Icon = palette.Icon

    const dim = hasSelection && !selected ? 'opacity-50' : ''
    const stateBg = selected ? palette.bgTint : 'bg-db-void'
    const stateBorder = selected
        ? `${palette.border} border-2`
        : 'border border-db-rule'

    if (variant === 'row') {
        return (
            <button
                type="button"
                onClick={onClick}
                role="radio"
                aria-checked={selected}
                className={`relative w-full grid grid-cols-[48px_1fr_auto] gap-4 items-center p-4 text-left transition-colors ${stateBg} ${stateBorder} ${dim} focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-db-chalk`}
            >
                {selected && (
                    <span
                        className={`absolute top-0 right-0 px-2 py-1 ${palette.bg} text-db-void font-sans font-extrabold text-[10px] tracking-[0.18em] uppercase`}
                    >
                        Picked
                    </span>
                )}
                <span
                    className={`w-12 h-12 border-2 ${palette.border} ${palette.text} flex items-center justify-center`}
                >
                    <Icon className="w-6 h-6" />
                </span>
                <span className="min-w-0">
                    <span className="block font-sans font-extrabold text-[18px] leading-[1.1] tracking-[-0.01em] text-db-chalk truncate">
                        {label}
                    </span>
                    <span className="block font-mono text-[10px] text-db-mute tracking-[0.04em] mt-1">
                        option · {String(index).padStart(2, '0')} · {pollAddrShort}
                    </span>
                </span>
                <span className="text-right">
                    <span className="block font-mono text-[18px] font-bold text-db-chalk tabular-nums tracking-[-0.02em]">
                        {count}
                    </span>
                    <span className="block font-mono text-[10px] text-db-mute tracking-[0.05em]">
                        {pct.toFixed(1)}%
                    </span>
                </span>
            </button>
        )
    }

    // Showdown variant — full block-style card with 32-40px label.
    return (
        <button
            type="button"
            onClick={onClick}
            role="radio"
            aria-checked={selected}
            className={`relative p-5 text-left cursor-pointer transition-colors ${stateBg} ${stateBorder} ${dim} focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-db-chalk`}
        >
            {selected && (
                <span
                    className={`absolute top-0 right-0 px-2 py-1 ${palette.bg} text-db-void font-sans font-extrabold text-[10px] tracking-[0.18em] uppercase`}
                >
                    Picked
                </span>
            )}
            <span
                className={`w-12 h-12 border-2 ${palette.border} ${palette.text} flex items-center justify-center mb-4`}
            >
                <Icon className="w-6 h-6" />
            </span>
            <h3
                className="font-sans font-extrabold leading-[1.05] tracking-[-0.01em] text-db-chalk mb-2 break-words"
                style={{ fontSize: 'clamp(20px, 4vw, 40px)' }}
            >
                {label}
            </h3>
            <p className="font-mono text-[10px] text-db-mute tracking-[0.04em]">
                option · {String(index).padStart(2, '0')} · {pollAddrShort}
            </p>
            <div className="mt-4 h-2 bg-db-rule overflow-hidden">
                <div
                    className={`h-full ${palette.bg} transition-[width] duration-200 ease-linear`}
                    style={{ width: `${pct}%` }}
                />
            </div>
            <p className="font-mono text-[10px] text-db-mute tracking-[0.05em] mt-1.5">
                {count} votes · {pct.toFixed(1)}%
            </p>
        </button>
    )
}
