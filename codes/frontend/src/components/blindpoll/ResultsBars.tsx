import { BarChart3, Users } from 'lucide-react'
import { OPTION_BAR_COLORS } from '../../lib/optionColors'

/**
 * Per-option revealed-vote bar chart for the blind-poll page, restyled in
 * the Dark Bauhaus grammar (see `.tmp/impl-specs/impl-3-blind-vote-page.md`
 * §2.8). Heading label adapts to lifecycle:
 *
 *   - finalized                  → "Final Results"
 *   - state===2 && !finalized    → "Results (Reveal Window Open)"
 *   - else                       → "Options"
 *
 * The footer adds the blind-specific reveal-vs-registered ratio plus a
 * LIVE / FINAL pill keyed off `finalized`.
 *
 * Style duplicated inline (rather than imported from a shared poll bar
 * primitive) because the anon-poll restyle is happening in a parallel
 * worktree and the shared component is not yet on `dev/lvh`.
 */
export function ResultsBars(props: {
    pollOptions: string[]
    voteCounts: number[]
    totalVotes: number
    participantCount: number
    currentPollState: number
    finalized: boolean
}) {
    const { pollOptions, voteCounts, totalVotes, participantCount, currentPollState, finalized } = props

    let headerLabel: string
    if (finalized) headerLabel = 'Final Results'
    else if (currentPollState === 2) headerLabel = 'Results (Reveal Window Open)'
    else headerLabel = 'Options'

    return (
        <div className="animate-fade-in-up bg-db-slate border border-db-rule p-6">
            <div className="flex items-center justify-between mb-5">
                <h2 className="inline-flex items-center gap-2">
                    <BarChart3 className="w-3.5 h-3.5 text-db-mute" aria-hidden="true" />
                    <span className="font-display font-extrabold text-[12px] tracking-[0.20em] uppercase text-db-chalk">
                        {headerLabel}
                    </span>
                </h2>
                {totalVotes > 0 && (
                    <span className="font-mono text-[11px] text-db-mute tracking-[0.05em] tabular-nums">
                        <strong className="text-db-chalk">{totalVotes}</strong> revealed
                    </span>
                )}
            </div>

            {pollOptions.length > 0 ? (
                <div className="space-y-5">
                    {pollOptions.map((opt, i) => {
                        const count = voteCounts[i] || 0
                        const pct = totalVotes > 0 ? (count / totalVotes) * 100 : 0
                        const barColor = OPTION_BAR_COLORS[i % OPTION_BAR_COLORS.length]
                        return (
                            <div key={i}>
                                <div className="flex justify-between items-baseline mb-2">
                                    <span className="font-mono text-[12px] text-db-chalk">{opt}</span>
                                    <div className="flex items-baseline gap-2">
                                        <span className="font-mono text-[10px] text-db-mute tracking-[0.05em] tabular-nums">
                                            {totalVotes > 0 ? `${pct.toFixed(1)}%` : '—'}
                                        </span>
                                        <span className="font-display font-extrabold text-[20px] text-db-chalk tabular-nums">
                                            {count}
                                        </span>
                                    </div>
                                </div>
                                <div className="w-full bg-db-void h-1.5 overflow-hidden">
                                    <div
                                        className={`${barColor} h-1.5 transition-all duration-700 ease-out`}
                                        style={{ width: `${pct}%` }}
                                    />
                                </div>
                            </div>
                        )
                    })}
                </div>
            ) : (
                <div className="text-center py-8">
                    <BarChart3 className="w-8 h-8 text-db-mute-dim mx-auto mb-2" aria-hidden="true" />
                    <p className="font-mono text-[12px] text-db-mute">No options configured yet.</p>
                </div>
            )}

            <div className="mt-5 pt-4 border-t border-db-rule flex items-center gap-3 font-mono text-[11px] text-db-mute tracking-[0.05em]">
                <Users className="w-3.5 h-3.5" aria-hidden="true" />
                <span>
                    <strong className="text-db-chalk tabular-nums">{totalVotes}</strong> revealed
                </span>
                <span className="text-db-rule" aria-hidden="true">·</span>
                <span>
                    <strong className="text-db-chalk tabular-nums">{participantCount}</strong> registered
                </span>
                <span className="text-db-rule" aria-hidden="true">·</span>
                <span>
                    <strong className={finalized ? 'text-db-success' : 'text-db-segnale'}>
                        {finalized ? 'FINAL' : 'LIVE'}
                    </strong>
                </span>
            </div>
        </div>
    )
}
