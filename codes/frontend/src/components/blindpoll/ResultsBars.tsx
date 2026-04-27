import { BarChart3, Users } from 'lucide-react'
import { OPTION_BAR_COLORS } from '../../lib/optionColors'

/**
 * Live results card: per-option bar chart of revealed votes plus a summary
 * footer with the registered-voter count. The header label adapts to the
 * current poll phase / finalization state.
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

    const headerLabel = finalized
        ? 'Final Results'
        : currentPollState === 2
            ? 'Results (updating as reveals come in)'
            : 'Options'

    return (
        <div className="animate-fade-in-up animate-fade-in-up-4 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
            <div className="flex items-center justify-between mb-5">
                <h2 className="text-base font-semibold text-stone-900 dark:text-stone-100 flex items-center gap-2">
                    <BarChart3 className="w-4 h-4 text-stone-400 dark:text-stone-500" />
                    {headerLabel}
                </h2>
                {totalVotes > 0 && (
                    <span className="text-xs font-semibold text-stone-500 dark:text-stone-400 bg-stone-100 dark:bg-stone-800 px-3 py-1 rounded-full font-mono tabular-nums">
                        {totalVotes} revealed
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
                                    <span className="text-sm font-medium text-stone-700 dark:text-stone-300">{opt}</span>
                                    <div className="flex items-baseline gap-2">
                                        <span className="text-xs text-stone-400 dark:text-stone-500 font-mono tabular-nums">
                                            {totalVotes > 0 ? `${pct.toFixed(1)}%` : '--'}
                                        </span>
                                        <span className="text-xl font-bold text-stone-900 dark:text-stone-100 font-mono tabular-nums">{count}</span>
                                    </div>
                                </div>
                                <div className="w-full bg-stone-100 dark:bg-stone-800 rounded-full h-2.5 overflow-hidden">
                                    <div
                                        className={`${barColor} h-2.5 rounded-full transition-all duration-700 ease-out`}
                                        style={{ width: `${pct}%` }}
                                    />
                                </div>
                            </div>
                        )
                    })}
                </div>
            ) : (
                <div className="text-center py-8">
                    <BarChart3 className="w-8 h-8 text-stone-300 dark:text-stone-600 mx-auto mb-2" />
                    <p className="text-sm text-stone-400 dark:text-stone-500">No options configured yet.</p>
                </div>
            )}

            {/* Participant info */}
            <div className="mt-4 pt-4 border-t border-stone-100 dark:border-stone-800 flex items-center gap-2 text-xs text-stone-400 dark:text-stone-500">
                <Users className="w-3.5 h-3.5" />
                <span className="font-mono tabular-nums text-sm font-bold text-teal-600 dark:text-teal-400">{participantCount}</span>
                registered voter{participantCount !== 1 ? 's' : ''}
            </div>
        </div>
    )
}
