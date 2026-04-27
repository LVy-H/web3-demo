import { Check, Clock } from 'lucide-react'
import { Countdown } from './Countdown'

/**
 * Reveal-phase card. Renders the reveal-deadline countdown plus one of three
 * states: voter has a pending reveal (button), voter has already revealed
 * (success row), or voter never committed (info text).
 */
export function RevealCard(props: {
    revealDeadline: number
    hasCommitted: boolean
    hasRevealed: boolean
    onReveal: () => void
    isProcessing: boolean
    disabled: boolean
}) {
    const { revealDeadline, hasCommitted, hasRevealed, onReveal, isProcessing, disabled } = props

    return (
        <div className="animate-fade-in-up bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
            <h2 className="text-base font-semibold text-stone-900 dark:text-stone-100 mb-1">Reveal Phase</h2>
            <p className="text-xs text-stone-500 dark:text-stone-400 mb-4">
                Voting has ended. Reveal your vote before the deadline to have it counted.
            </p>

            {revealDeadline > 0 && (
                <div className="flex flex-col items-center gap-2 mb-5 px-4 py-4 bg-stone-900 dark:bg-stone-950 rounded-xl">
                    <div className="flex items-center gap-2">
                        <Clock className="w-5 h-5 text-stone-400 flex-shrink-0" />
                        <span className="text-xs font-semibold text-stone-400 uppercase tracking-wider">Reveal Deadline</span>
                    </div>
                    <Countdown deadline={revealDeadline} />
                </div>
            )}

            {hasCommitted && !hasRevealed ? (
                <button
                    onClick={onReveal}
                    disabled={disabled}
                    className="w-full py-4 bg-amber-500 hover:bg-amber-600 active:bg-amber-700 text-white transition-colors rounded-xl text-base font-bold disabled:opacity-50 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-500 focus-visible:ring-offset-2"
                >
                    {isProcessing ? 'Processing...' : 'Reveal Vote'}
                </button>
            ) : hasRevealed ? (
                <div className="flex items-center gap-2 px-4 py-3 bg-teal-50 dark:bg-teal-900/30 border border-teal-200 dark:border-teal-700 text-teal-700 dark:text-teal-400 rounded-xl text-sm font-medium">
                    <Check className="w-4 h-4" />
                    Your vote has been revealed and counted.
                </div>
            ) : (
                <p className="text-sm text-stone-500 dark:text-stone-400">You did not commit a vote in this poll.</p>
            )}
        </div>
    )
}
