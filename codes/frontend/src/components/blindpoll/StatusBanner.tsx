export type StatusType = 'info' | 'success' | 'error'

/**
 * Colored status banner with a leading dot and an aria-live region. Variants
 * (info/success/error) drive the color palette; the info dot pulses to hint
 * at in-flight work.
 */
export function StatusBanner({
    msg, type, isTxConfirming, isTxSuccess,
}: {
    msg: string
    type: StatusType
    isTxConfirming: boolean
    isTxSuccess: boolean
}) {
    if (msg) {
        return (
            <div
                className={`px-5 py-4 rounded-xl flex items-start gap-3 text-sm font-medium border ${
                    type === 'success'
                        ? 'bg-emerald-50 dark:bg-emerald-900/30 border-emerald-200 dark:border-emerald-700 text-emerald-800 dark:text-emerald-300'
                        : type === 'error'
                            ? 'bg-rose-50 dark:bg-rose-900/30 border-rose-200 dark:border-rose-700 text-rose-800 dark:text-rose-300'
                            : 'bg-stone-50 dark:bg-stone-800 border-stone-200 dark:border-stone-700 text-stone-800 dark:text-stone-300'
                }`}
                role="status"
                aria-live="polite"
            >
                <div className={`mt-0.5 h-2.5 w-2.5 rounded-full flex-shrink-0 ${
                    type === 'success'
                        ? 'bg-emerald-500'
                        : type === 'error'
                            ? 'bg-rose-500'
                            : 'bg-stone-400 animate-pulse'
                }`} />
                <p>{msg}</p>
            </div>
        )
    }
    if (isTxConfirming) {
        return <p className="text-amber-600 dark:text-amber-400 text-sm font-medium animate-pulse px-1">Transaction pending...</p>
    }
    if (isTxSuccess) {
        return <p className="text-emerald-600 dark:text-emerald-400 text-sm font-medium px-1">Transaction confirmed!</p>
    }
    return null
}
