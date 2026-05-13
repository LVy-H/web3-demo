import { ArrowRight, Loader2, Users } from 'lucide-react'
import teamUrl from '../../assets/illustrations/team.svg'

/**
 * Registration-phase hero card — wide poster-style block in the Dark
 * Bauhaus grammar (see `.tmp/impl-specs/impl-3-blind-vote-page.md` §2.3).
 *
 * Shows a brief explanation of the commit-reveal flow, the current voter
 * count in a hairline strip, and a single wide CTA. A `team.svg`
 * watermark sits in the right gutter on `md+` viewports.
 *
 * Prop interface is preserved verbatim.
 */
export function RegisterCard(props: {
    participantCount: number
    isConnected: boolean
    isProcessing: boolean
    disabled: boolean
    onRegister: () => void
}) {
    const { participantCount, isConnected, isProcessing, disabled, onRegister } = props

    let ctaLabel: string
    if (!isConnected) ctaLabel = 'Connect Wallet First'
    else if (isProcessing) ctaLabel = 'Registering…'
    else ctaLabel = 'Register as Voter'

    return (
        <div className="animate-fade-in-up bg-db-slate border border-db-rule p-8 relative overflow-hidden">
            {/* Watermark — right gutter, md+ only */}
            <img
                src={teamUrl}
                alt=""
                aria-hidden="true"
                className="absolute right-8 top-1/2 -translate-y-1/2 w-[200px] opacity-15 pointer-events-none hidden md:block select-none"
            />

            <div className="relative">
                <h2 className="font-display font-extrabold text-[28px] leading-[1.05] tracking-[-0.01em] text-db-chalk uppercase mb-1">
                    Registration
                </h2>
                <div className="w-12 h-px bg-db-segnale mb-4" aria-hidden="true" />

                <p className="font-mono text-[12px] text-db-mute leading-[1.6] max-w-[480px] mb-6">
                    Sign up to vote in this commit-reveal poll. Your wallet address
                    is added to the voter registry. Once voting opens you can submit
                    one sealed commitment.
                </p>

                <div className="inline-flex items-center gap-3 px-4 py-2 bg-db-void border-l-2 border-db-segnale mb-6">
                    <Users className="w-4 h-4 text-db-segnale" aria-hidden="true" />
                    <span className="font-mono text-[14px] text-db-chalk tabular-nums">
                        <strong className="font-mono font-bold text-db-chalk">{participantCount}</strong>{' '}
                        voter{participantCount === 1 ? '' : 's'} registered
                    </span>
                </div>

                <button
                    onClick={onRegister}
                    disabled={disabled}
                    className="w-full max-w-[640px] inline-flex items-center justify-center gap-3 px-6 py-4 bg-db-segnale hover:bg-db-segnale/90 text-db-void font-display font-extrabold text-[12px] tracking-[0.20em] uppercase disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-db-segnale focus-visible:ring-offset-2 focus-visible:ring-offset-db-void"
                >
                    {isProcessing && <Loader2 className="w-3.5 h-3.5 animate-spin" aria-hidden="true" />}
                    <span>{ctaLabel}</span>
                    {!isProcessing && isConnected && <ArrowRight className="w-3.5 h-3.5" aria-hidden="true" />}
                </button>

                <p className="mt-4 font-mono text-[10px] text-db-mute tracking-[0.08em] uppercase">
                    [ prover ready · scope locked to this poll ]
                </p>
            </div>
        </div>
    )
}
