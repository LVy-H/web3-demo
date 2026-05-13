export type StatusType = 'info' | 'success' | 'error'

/**
 * Dark-Bauhaus status banner — hairline-bordered slate panel with a 2-px
 * left accent stripe and an 8 px leading square indicator. Variants drive
 * the accent + square colour. Returns `null` when there's nothing to show.
 */
export function PollStatusBanner({
    msg,
    type,
    isTxConfirming,
    isTxSuccess,
}: {
    msg: string
    type: StatusType
    isTxConfirming: boolean
    isTxSuccess: boolean
}) {
    if (msg) {
        const variant =
            type === 'success'
                ? { stripe: 'border-db-success', sq: 'bg-db-success', pulse: '' }
                : type === 'error'
                    ? { stripe: 'border-db-segnale', sq: 'bg-db-segnale', pulse: '' }
                    : { stripe: 'border-db-mute', sq: 'bg-db-mute', pulse: 'animate-pulse' }
        return (
            <div
                className={`flex items-start gap-3 px-5 py-3 bg-db-slate border-l-2 ${variant.stripe}`}
                role="status"
                aria-live="polite"
            >
                <span
                    className={`mt-1.5 w-2 h-2 flex-shrink-0 ${variant.sq} ${variant.pulse}`}
                    aria-hidden="true"
                />
                <p className="font-mono text-[12px] text-db-chalk tracking-[0.02em] leading-relaxed">
                    {msg}
                </p>
            </div>
        )
    }
    if (isTxConfirming) {
        return (
            <p className="font-mono text-[11px] text-db-oltremare tracking-[0.05em] uppercase px-1 animate-pulse">
                Transaction pending…
            </p>
        )
    }
    if (isTxSuccess) {
        return (
            <p className="font-mono text-[11px] text-db-success tracking-[0.05em] uppercase px-1">
                Transaction confirmed
            </p>
        )
    }
    return null
}
