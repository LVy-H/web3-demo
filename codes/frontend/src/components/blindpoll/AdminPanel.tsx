import { Plus, Settings } from 'lucide-react'

/**
 * Owner-only control panel for a blind poll, restyled in the Dark Bauhaus
 * grammar (see `.tmp/impl-specs/impl-3-blind-vote-page.md` §2.7).
 *
 * THREE lifecycle buttons (Start / End / Finalize) sit in a hairline-gap
 * strip, mirroring the v8 admin-row pattern: each cell is a slate tile
 * that flips to segnale on hover when enabled. While the poll is still
 * in registration (state 0), the option-management UI surfaces below the
 * lifecycle row.
 *
 * Behavioural surface and prop interface are preserved verbatim — only
 * the JSX/CSS layer changes.
 */
export function AdminPanel(props: {
    currentPollState: number
    finalized: boolean
    isConnected: boolean
    isWrongNetwork: boolean
    isPending: boolean
    pollOptions: string[]
    newOptionLabel: string
    onChangeNewOptionLabel: (v: string) => void
    onStartVoting: () => void
    onEndVoting: () => void
    onFinalizeResults: () => void
    onAddOption: () => void
}) {
    const {
        currentPollState, finalized, isConnected, isWrongNetwork, isPending,
        pollOptions, newOptionLabel, onChangeNewOptionLabel,
        onStartVoting, onEndVoting, onFinalizeResults, onAddOption,
    } = props

    const cellBase = 'flex-1 py-3 font-display font-extrabold text-[11px] tracking-[0.18em] uppercase transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-db-segnale focus-visible:ring-offset-1 focus-visible:ring-offset-db-void'
    const cellEnabled = 'bg-db-slate text-db-segnale hover:bg-db-segnale hover:text-db-void'
    const cellDisabled = 'bg-db-slate text-db-mute opacity-40 cursor-not-allowed'

    const startDisabled = currentPollState !== 0 || !isConnected || isWrongNetwork
    const endDisabled = currentPollState !== 1 || !isConnected || isWrongNetwork
    const finalizeDisabled = currentPollState !== 2 || finalized || !isConnected || isWrongNetwork

    return (
        <div className="animate-fade-in-up bg-db-slate border-2 border-db-segnale p-6">
            <h2 className="flex items-center gap-2 mb-6">
                <Settings className="w-3.5 h-3.5 text-db-segnale" aria-hidden="true" />
                <span className="font-display font-extrabold text-[11px] tracking-[0.20em] uppercase text-db-segnale">
                    Admin Panel
                </span>
            </h2>

            {/* Lifecycle row — 3 cells separated by 1px rule */}
            <div className="flex gap-px bg-db-rule mb-6">
                <button
                    onClick={onStartVoting}
                    disabled={startDisabled}
                    className={`${cellBase} ${startDisabled ? cellDisabled : cellEnabled}`}
                >
                    Start Voting
                </button>
                <button
                    onClick={onEndVoting}
                    disabled={endDisabled}
                    className={`${cellBase} ${endDisabled ? cellDisabled : cellEnabled}`}
                >
                    End Voting
                </button>
                <button
                    onClick={onFinalizeResults}
                    disabled={finalizeDisabled}
                    className={`${cellBase} ${finalizeDisabled ? cellDisabled : cellEnabled}`}
                >
                    Finalize
                </button>
            </div>

            {/* Manage Options — registration phase only */}
            {currentPollState === 0 && (
                <div className="border-t border-db-rule pt-5">
                    <h3 className="font-display font-extrabold text-[11px] tracking-[0.18em] uppercase text-db-chalk-dim mb-3">
                        Manage Options
                    </h3>
                    {pollOptions.length > 0 && (
                        <div className="mb-4 flex flex-col gap-px bg-db-rule border border-db-rule">
                            {pollOptions.map((opt, i) => (
                                <div
                                    key={i}
                                    className="flex items-center gap-3 px-3 py-2 bg-db-void font-mono text-[12px] text-db-chalk"
                                >
                                    <span className="font-mono text-[10px] text-db-mute tracking-[0.18em] uppercase tabular-nums">
                                        option · {String(i + 1).padStart(2, '0')}
                                    </span>
                                    <span className="ml-2 text-db-chalk">{opt}</span>
                                </div>
                            ))}
                        </div>
                    )}
                    <div className="flex gap-px bg-db-rule border border-db-rule">
                        <input
                            type="text"
                            placeholder="New option label"
                            value={newOptionLabel}
                            onChange={e => onChangeNewOptionLabel(e.target.value)}
                            className="flex-1 bg-db-void border-0 px-3 py-2.5 font-mono text-[12px] text-db-chalk placeholder:text-db-mute focus:outline-none focus:ring-2 focus:ring-inset focus:ring-db-segnale"
                            aria-label="New option label"
                        />
                        <button
                            onClick={onAddOption}
                            disabled={!newOptionLabel.trim() || !isConnected || isWrongNetwork || isPending}
                            className="inline-flex items-center gap-2 px-4 py-2.5 bg-db-segnale text-db-void font-display font-extrabold text-[11px] tracking-[0.18em] uppercase hover:bg-db-segnale/90 disabled:bg-db-slate disabled:text-db-mute disabled:opacity-40 disabled:cursor-not-allowed transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-db-segnale focus-visible:ring-offset-1 focus-visible:ring-offset-db-void"
                        >
                            <Plus className="w-3.5 h-3.5" aria-hidden="true" />
                            {isPending ? '…' : 'Add'}
                        </button>
                    </div>
                </div>
            )}
        </div>
    )
}
