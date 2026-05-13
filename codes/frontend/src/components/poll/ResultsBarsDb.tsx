import { BarChart3 } from 'lucide-react'
import { getOptionColor } from '../../lib/pollOptionPalette'

/**
 * Right-column live tally, Dark Bauhaus flavour. Block-bar variant: flat
 * fills, no rounded corners, tabular-nums for the count column. Bar colour
 * cycles through the 4-rotation palette keyed by option index.
 */
export function ResultsBarsDb({
    pollOptions,
    voteCounts,
    totalVotes,
}: {
    pollOptions: string[]
    voteCounts: number[]
    totalVotes: number
}) {
    return (
        <div className="bg-db-slate border border-db-rule p-6">
            <div className="flex items-center justify-between mb-5">
                <div className="flex items-center gap-2">
                    <BarChart3 className="w-4 h-4 text-db-mute" />
                    <h2 className="font-sans font-extrabold text-base tracking-[0.05em] uppercase text-db-chalk">
                        Live Results
                    </h2>
                </div>
                {totalVotes > 0 && (
                    <span className="font-mono text-[11px] text-db-mute tracking-[0.05em] uppercase">
                        {totalVotes} VOTE{totalVotes !== 1 ? 'S' : ''}
                    </span>
                )}
            </div>

            {pollOptions.length > 0 ? (
                <div className="space-y-4">
                    {pollOptions.map((opt, i) => {
                        const count = voteCounts[i] ?? 0
                        const pct = totalVotes > 0 ? (count / totalVotes) * 100 : 0
                        const palette = getOptionColor(i)
                        return (
                            <div key={i}>
                                <div className="flex justify-between items-baseline">
                                    <span className="font-sans font-extrabold text-[14px] tracking-[0.02em] text-db-chalk truncate min-w-0 pr-3">
                                        {opt}
                                    </span>
                                    <span className="flex items-baseline gap-2 flex-shrink-0">
                                        <span className="font-mono text-[20px] font-bold text-db-chalk tabular-nums tracking-[-0.02em]">
                                            {count}
                                        </span>
                                        <span className="font-mono text-[11px] text-db-mute">
                                            {totalVotes > 0 ? `${pct.toFixed(1)}%` : '—'}
                                        </span>
                                    </span>
                                </div>
                                <div className="w-full h-2 bg-db-rule mt-2 overflow-hidden">
                                    <div
                                        className={`h-full ${palette.bg} transition-[width] duration-200 ease-linear`}
                                        style={{ width: `${pct}%` }}
                                    />
                                </div>
                            </div>
                        )
                    })}
                </div>
            ) : (
                <div className="text-center py-8">
                    <BarChart3 className="w-8 h-8 text-db-mute mx-auto mb-2 opacity-40" />
                    <p className="font-mono text-[11px] text-db-mute tracking-[0.05em] uppercase">
                        No options configured yet
                    </p>
                </div>
            )}
        </div>
    )
}
