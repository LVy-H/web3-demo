import { Check } from 'lucide-react'

/**
 * Voting-phase card. When the voter has not yet committed, shows the option
 * picker + commit button. When already committed, shows a confirmation panel.
 */
export function CommitCard(props: {
    pollOptions: string[]
    selectedOption: number
    onSelectOption: (i: number) => void
    onCommit: () => void
    hasCommitted: boolean
    hasSavedCommit: boolean
    isConnected: boolean
    isProcessing: boolean
    disabled: boolean
}) {
    const {
        pollOptions, selectedOption, onSelectOption, onCommit,
        hasCommitted, hasSavedCommit, isConnected, isProcessing, disabled,
    } = props

    if (!hasCommitted) {
        return (
            <div className="animate-fade-in-up bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                <h2 className="text-base font-semibold text-stone-900 dark:text-stone-100 mb-4">Cast Your Vote</h2>

                {pollOptions.length === 0 ? (
                    <p className="text-sm text-stone-400 dark:text-stone-500">No options available.</p>
                ) : (
                    <fieldset>
                        <legend className="sr-only">Select a voting option</legend>
                        <div className="flex flex-col gap-2 mb-6">
                            {pollOptions.map((opt, i) => (
                                <button
                                    key={i}
                                    onClick={() => onSelectOption(i)}
                                    role="radio"
                                    aria-checked={selectedOption === i}
                                    className={`w-full min-h-[48px] py-3 px-4 rounded-xl border transition-all duration-200 text-left flex items-center gap-3 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2 ${
                                        selectedOption === i
                                            ? 'border-teal-500 bg-teal-50 dark:bg-teal-900/30 text-teal-800 dark:text-teal-300 font-semibold'
                                            : 'border-stone-200 dark:border-stone-700 hover:border-teal-300 dark:hover:border-teal-600 text-stone-700 dark:text-stone-300'
                                    }`}
                                >
                                    <span className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-all ${
                                        selectedOption === i
                                            ? 'border-teal-600 bg-teal-600'
                                            : 'border-stone-300 dark:border-stone-600'
                                    }`}>
                                        {selectedOption === i && (
                                            <Check className="w-3 h-3 text-white" />
                                        )}
                                    </span>
                                    <span>{opt}</span>
                                </button>
                            ))}
                        </div>

                        <button
                            onClick={onCommit}
                            disabled={disabled}
                            className="w-full py-4 bg-teal-600 hover:bg-teal-700 active:bg-teal-800 text-white transition-colors rounded-xl text-base font-bold disabled:opacity-50 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
                        >
                            {!isConnected ? 'Connect Wallet First' : isProcessing ? 'Processing...' : 'Commit Vote'}
                        </button>
                    </fieldset>
                )}
            </div>
        )
    }

    // Already committed
    return (
        <div className="animate-fade-in-up bg-white dark:bg-stone-900 border border-emerald-200 dark:border-emerald-700 rounded-xl shadow-sm p-6">
            <div className="flex items-center gap-3 mb-3">
                <div className="w-10 h-10 rounded-xl bg-emerald-100 dark:bg-emerald-900/30 flex items-center justify-center flex-shrink-0">
                    <Check className="w-5 h-5 text-emerald-600 dark:text-emerald-400" />
                </div>
                <div>
                    <p className="text-sm font-semibold text-emerald-800 dark:text-emerald-300">Vote Committed</p>
                    <p className="text-xs text-stone-500 dark:text-stone-400 mt-0.5">
                        Your vote is sealed. You will need to reveal it after voting ends.
                    </p>
                </div>
            </div>
            {hasSavedCommit && (
                <div className="bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-100 dark:border-emerald-800 rounded-xl px-3 py-2 mt-2">
                    <p className="text-xs text-emerald-700 dark:text-emerald-400 font-medium">
                        Reveal data is saved in this browser. Do not clear your browser data before revealing.
                    </p>
                </div>
            )}
        </div>
    )
}
