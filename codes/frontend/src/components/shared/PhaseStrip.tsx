/**
 * PhaseStrip — generic N-step lifecycle strip in the Dark Bauhaus grammar.
 *
 * Shared between `Poll.tsx` (3 steps: Registration / Voting / Ended) and
 * `BlindPoll.tsx` (4 steps: Registration / Commit / Reveal / Ended). The
 * component is intentionally dumb: callers pre-compute the active step and
 * pass it as `current`.
 *
 * Per-step visual state:
 *   - DONE    (i < current)   : bg-db-slate / text-db-mute, Check icon
 *   - CURRENT (i === current) : bg-db-segnale / text-db-void, step icon,
 *                                 pulsing db-success square indicator
 *   - PENDING (i > current)   : bg-db-void / text-db-mute, numeric prefix
 *
 * Layout: outer hairline frame, equal-width columns with `border-l` on
 * every block except the first. Labels collapse to a tighter 10px size at
 * the `<sm` breakpoint so 4-step strips don't overflow on mobile.
 *
 * See `.tmp/impl-specs/impl-3-blind-vote-page.md` §2.1 and
 * `.tmp/ui-proposals/05-dark-bauhaus.md`.
 */

import { Check, type LucideIcon } from 'lucide-react'

export interface PhaseStripStep {
    label: string
    icon: LucideIcon
}

export function PhaseStrip({
    steps,
    current,
}: {
    steps: PhaseStripStep[]
    /** Zero-based index of the active step. Values outside `[0, steps.length)`
     *  render every block as pending (current < 0) or done (current >=
     *  steps.length). */
    current: number
}) {
    return (
        <div
            className="grid border border-db-rule"
            style={{ gridTemplateColumns: `repeat(${steps.length}, minmax(0, 1fr))` }}
            role="list"
            aria-label="Poll lifecycle phases"
        >
            {steps.map((step, i) => {
                const StepIcon = step.icon
                const isDone = i < current
                const isCurrent = i === current
                const borderL = i > 0 ? 'border-l border-db-rule' : ''

                if (isCurrent) {
                    return (
                        <div
                            key={i}
                            role="listitem"
                            aria-current="step"
                            className={`relative flex items-center justify-center gap-2 px-3 sm:px-4 py-3 font-display font-extrabold text-[10px] sm:text-[11px] tracking-[0.18em] uppercase bg-db-segnale text-db-void ${borderL}`}
                        >
                            <StepIcon className="w-3.5 h-3.5 flex-shrink-0" aria-hidden="true" />
                            <span>{step.label}</span>
                            <span
                                className="absolute right-2 top-1/2 -translate-y-1/2 w-1.5 h-1.5 bg-db-success animate-pulse"
                                aria-hidden="true"
                            />
                        </div>
                    )
                }

                if (isDone) {
                    return (
                        <div
                            key={i}
                            role="listitem"
                            className={`flex items-center justify-center gap-2 px-3 sm:px-4 py-3 font-display font-extrabold text-[10px] sm:text-[11px] tracking-[0.18em] uppercase bg-db-slate text-db-mute ${borderL}`}
                        >
                            <Check className="w-3.5 h-3.5 flex-shrink-0" aria-hidden="true" />
                            <span>{step.label}</span>
                        </div>
                    )
                }

                // Pending
                return (
                    <div
                        key={i}
                        role="listitem"
                        className={`flex items-center justify-center gap-2 px-3 sm:px-4 py-3 font-display font-extrabold text-[10px] sm:text-[11px] tracking-[0.18em] uppercase bg-db-void text-db-mute ${borderL}`}
                    >
                        <span className="font-mono tabular-nums opacity-60" aria-hidden="true">
                            {String(i + 1).padStart(2, '0')}
                        </span>
                        <span>{step.label}</span>
                    </div>
                )
            })}
        </div>
    )
}
