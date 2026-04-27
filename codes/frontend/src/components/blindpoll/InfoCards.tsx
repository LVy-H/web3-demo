import { Key, Lock } from 'lucide-react'

/**
 * Static teal trust-signal banner shown at the top of every BlindPoll page.
 */
export function TrustBanner() {
    return (
        <div className="animate-fade-in-up animate-fade-in-up-2 bg-teal-50 dark:bg-teal-900/30 border border-teal-200 dark:border-teal-800 rounded-xl px-5 py-4 flex items-center gap-3">
            <Lock className="w-5 h-5 text-teal-600 dark:text-teal-400 flex-shrink-0" />
            <p className="text-sm text-teal-800 dark:text-teal-300 font-medium">
                Your vote is sealed with a cryptographic commitment. No one can see your choice until the reveal phase.
            </p>
        </div>
    )
}

/**
 * Card shown when the reveal window has closed and results are final.
 */
export function FinalizedCard() {
    return (
        <div className="animate-fade-in-up bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
            <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-stone-100 dark:bg-stone-800 flex items-center justify-center flex-shrink-0">
                    <Lock className="w-5 h-5 text-stone-500 dark:text-stone-400" />
                </div>
                <div>
                    <p className="text-sm font-semibold text-stone-700 dark:text-stone-300">Results Finalized</p>
                    <p className="text-xs text-stone-500 dark:text-stone-400 mt-0.5">
                        The reveal window has closed and results are final. Unrevealed votes were excluded.
                    </p>
                </div>
            </div>
        </div>
    )
}

/**
 * Card prompting the visitor to connect their wallet.
 */
export function NotConnectedCard() {
    return (
        <div className="animate-fade-in-up bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
            <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-stone-100 dark:bg-stone-800 flex items-center justify-center flex-shrink-0">
                    <Key className="w-5 h-5 text-stone-400 dark:text-stone-500" />
                </div>
                <div>
                    <p className="text-sm font-semibold text-stone-700 dark:text-stone-300">Wallet Not Connected</p>
                    <p className="text-xs text-stone-500 dark:text-stone-400 mt-0.5">
                        Connect your wallet to register, vote, or reveal.
                    </p>
                </div>
            </div>
        </div>
    )
}
