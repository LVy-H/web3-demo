import { Plus, Settings } from 'lucide-react'

/**
 * Owner-only control panel for a blind poll. Shows the lifecycle buttons
 * (start / end / finalize) and, while still in the registration phase,
 * the option-management UI. All transactions are delegated to the parent.
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

    return (
        <div className="animate-fade-in-up animate-fade-in-up-5 bg-white dark:bg-stone-900 border-2 border-amber-200 dark:border-amber-700 rounded-xl shadow-sm p-6">
            <h2 className="text-xs font-bold text-amber-600 dark:text-amber-400 uppercase tracking-widest mb-4 flex items-center gap-2">
                <div className="w-6 h-6 rounded-lg bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center">
                    <Settings className="w-3.5 h-3.5 text-amber-600 dark:text-amber-400" />
                </div>
                Admin Panel
            </h2>

            {/* Poll Lifecycle Buttons */}
            <div className="flex flex-col sm:flex-row gap-2 mb-6">
                <button
                    onClick={onStartVoting}
                    disabled={currentPollState !== 0 || !isConnected || isWrongNetwork}
                    className="flex-1 py-2.5 bg-amber-50 dark:bg-amber-900/30 hover:bg-amber-100 dark:hover:bg-amber-900/50 text-amber-700 dark:text-amber-400 transition-all border border-amber-200 dark:border-amber-700 rounded-xl text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
                >
                    Start Voting
                </button>
                <button
                    onClick={onEndVoting}
                    disabled={currentPollState !== 1 || !isConnected || isWrongNetwork}
                    className="flex-1 py-2.5 bg-amber-50 dark:bg-amber-900/30 hover:bg-amber-100 dark:hover:bg-amber-900/50 text-amber-700 dark:text-amber-400 transition-all border border-amber-200 dark:border-amber-700 rounded-xl text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
                >
                    End Voting
                </button>
                <button
                    onClick={onFinalizeResults}
                    disabled={currentPollState !== 2 || finalized || !isConnected || isWrongNetwork}
                    className="flex-1 py-2.5 bg-amber-50 dark:bg-amber-900/30 hover:bg-amber-100 dark:hover:bg-amber-900/50 text-amber-700 dark:text-amber-400 transition-all border border-amber-200 dark:border-amber-700 rounded-xl text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
                >
                    Finalize Results
                </button>
            </div>

            {/* Manage Options (Registration only) */}
            {currentPollState === 0 && (
                <div className="border-t border-amber-100 dark:border-amber-800 pt-4">
                    <h3 className="text-sm font-semibold text-amber-700 dark:text-amber-400 mb-3">Manage Options</h3>
                    {pollOptions.length > 0 && (
                        <div className="mb-3 space-y-1">
                            {pollOptions.map((opt, i) => (
                                <div key={i} className="flex items-center gap-2 px-3 py-2 bg-amber-50 dark:bg-amber-900/30 rounded-lg text-sm text-amber-800 dark:text-amber-300 border border-amber-100 dark:border-amber-800">
                                    <span className="w-5 h-5 rounded-full bg-amber-500 text-white text-xs flex items-center justify-center font-bold">{i + 1}</span>
                                    {opt}
                                </div>
                            ))}
                        </div>
                    )}
                    <div className="flex gap-2">
                        <input
                            type="text"
                            placeholder="New option label"
                            value={newOptionLabel}
                            onChange={e => onChangeNewOptionLabel(e.target.value)}
                            className="flex-1 bg-white dark:bg-stone-800 border border-amber-200 dark:border-amber-700 rounded-xl px-3 py-2 text-sm text-stone-900 dark:text-stone-100 focus:outline-none focus:ring-2 focus:ring-amber-400 transition-all"
                            aria-label="New option label"
                        />
                        <button
                            onClick={onAddOption}
                            disabled={!newOptionLabel.trim() || !isConnected || isWrongNetwork || isPending}
                            className="inline-flex items-center gap-1 px-4 py-2 bg-amber-500 hover:bg-amber-600 text-white rounded-xl text-sm font-medium transition-colors disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
                        >
                            <Plus className="w-3.5 h-3.5" />
                            {isPending ? '...' : 'Add'}
                        </button>
                    </div>
                </div>
            )}
        </div>
    )
}
