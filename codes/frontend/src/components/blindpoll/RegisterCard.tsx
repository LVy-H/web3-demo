import { Users } from 'lucide-react'

/**
 * Registration-phase card. Shows the current voter count and a "Register"
 * button. The actual transaction is delegated to the parent via `onRegister`.
 */
export function RegisterCard(props: {
    participantCount: number
    isConnected: boolean
    isProcessing: boolean
    disabled: boolean
    onRegister: () => void
}) {
    const { participantCount, isConnected, isProcessing, disabled, onRegister } = props

    return (
        <div className="animate-fade-in-up animate-fade-in-up-3 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
            <h2 className="text-base font-semibold text-stone-900 dark:text-stone-100 mb-1">Register to Vote</h2>
            <p className="text-xs text-stone-500 dark:text-stone-400 mb-4">
                Connect your wallet and register. Your address will be added to the voter list.
            </p>
            <div className="flex items-center gap-3">
                <Users className="w-4 h-4 text-teal-600 dark:text-teal-400" />
                <span className="text-sm text-stone-600 dark:text-stone-400 font-mono tabular-nums">
                    <span className="text-lg font-bold text-teal-600 dark:text-teal-400">{participantCount}</span>{' '}
                    voter{participantCount !== 1 ? 's' : ''} registered
                </span>
            </div>
            <button
                onClick={onRegister}
                disabled={disabled}
                className="mt-4 w-full py-3 bg-teal-600 hover:bg-teal-700 active:bg-teal-800 text-white transition-colors rounded-xl text-sm font-bold disabled:opacity-50 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
            >
                {!isConnected ? 'Connect Wallet First' : isProcessing ? 'Processing...' : 'Register to Vote'}
            </button>
        </div>
    )
}
