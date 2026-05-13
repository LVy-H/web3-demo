export type StatusType = 'info' | 'success' | 'error'

/**
 * Status banner with a square indicator and a hairline left-border tinted
 * per variant, in the Dark Bauhaus grammar (see
 * `.tmp/impl-specs/impl-3-blind-vote-page.md` §2.3 / Impl-2 PollStatusBanner).
 *
 * Variants drive the indicator + border colour:
 *   - success → db-success
 *   - error   → db-segnale
 *   - info    → db-oltremare (pulsing indicator while in-flight)
 *
 * Falls back to compact one-line tx-state strings when no `msg` is set
 * but a transaction is pending or confirmed.
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
        const borderColor =
            type === 'success' ? 'border-db-success'
                : type === 'error' ? 'border-db-segnale'
                    : 'border-db-oltremare'
        const dotColor =
            type === 'success' ? 'bg-db-success'
                : type === 'error' ? 'bg-db-segnale'
                    : 'bg-db-oltremare animate-pulse'

        return (
            <div
                className={`bg-db-slate border-l-2 ${borderColor} px-4 py-3 flex items-start gap-3`}
                role="status"
                aria-live="polite"
            >
                <span className={`mt-1 h-2.5 w-2.5 flex-shrink-0 ${dotColor}`} aria-hidden="true" />
                <p className="font-mono text-[12px] text-db-chalk leading-relaxed">{msg}</p>
            </div>
        )
    }
    if (isTxConfirming) {
        return (
            <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-db-oltremare animate-pulse px-1">
                Transaction pending…
            </p>
        )
    }
    if (isTxSuccess) {
        return (
            <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-db-success px-1">
                Transaction confirmed
            </p>
        )
    }
    return null
}
