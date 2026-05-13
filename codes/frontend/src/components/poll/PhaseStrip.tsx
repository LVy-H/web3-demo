import { Fragment } from 'react'
import { Check, Radio } from 'lucide-react'

/**
 * Three-block lifecycle strip in the Dark Bauhaus grammar. Replaces the
 * legacy rounded-pill `StateProgress`. Steps are hard-coded:
 * Registration / Voting / Ended.
 *
 * Per-state styling:
 * - DONE    (i < current): bg-db-slate + text-db-mute + Check prefix.
 * - CURRENT (i === current): bg-db-segnale + text-db-void + pulsing success square.
 * - PENDING (i > current): bg-db-void + text-db-mute + index numeral.
 */
const STEPS = ['Registration', 'Voting', 'Ended'] as const

export function PhaseStrip({ current }: { current: number }) {
    return (
        <div
            className="grid grid-cols-3 border border-db-rule"
            role="list"
            aria-label="Poll lifecycle phases"
        >
            {STEPS.map((label, i) => {
                const isDone = i < current
                const isCurrent = i === current
                const borderL = i > 0 ? 'border-l border-db-rule' : ''

                if (isCurrent) {
                    return (
                        <Fragment key={i}>
                            <div
                                role="listitem"
                                aria-current="step"
                                className={`relative flex items-center justify-center gap-2 px-4 py-3 bg-db-segnale text-db-void font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase ${borderL}`}
                            >
                                <Radio className="w-3.5 h-3.5" aria-hidden="true" />
                                <span>{label}</span>
                                <span
                                    className="absolute right-2 top-1/2 -translate-y-1/2 w-1.5 h-1.5 bg-db-success animate-pulse"
                                    aria-hidden="true"
                                />
                            </div>
                        </Fragment>
                    )
                }

                if (isDone) {
                    return (
                        <div
                            key={i}
                            role="listitem"
                            className={`flex items-center justify-center gap-2 px-4 py-3 bg-db-slate text-db-mute font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase ${borderL}`}
                        >
                            <Check className="w-3.5 h-3.5" aria-hidden="true" />
                            <span>{label}</span>
                        </div>
                    )
                }

                return (
                    <div
                        key={i}
                        role="listitem"
                        className={`flex items-center justify-center gap-2 px-4 py-3 bg-db-void text-db-mute font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase ${borderL}`}
                    >
                        <span className="font-mono tabular-nums opacity-60" aria-hidden="true">
                            {String(i + 1).padStart(2, '0')}
                        </span>
                        <span>{label}</span>
                    </div>
                )
            })}
        </div>
    )
}
