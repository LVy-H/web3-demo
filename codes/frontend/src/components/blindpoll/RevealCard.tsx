import { ArrowRight, Check, Clock, Loader2 } from 'lucide-react'
import unlockUrl from '../../assets/illustrations/unlock.svg'
import { Countdown } from './Countdown'

/**
 * Reveal-phase hero card — wide block with a prominent countdown to the
 * reveal deadline and one of three per-state branches:
 *
 *   1. has committed but not yet revealed → green Reveal CTA
 *   2. has revealed                       → success chip
 *   3. never committed                    → muted info text
 *
 * The `unlock.svg` watermark (reveal phase, success-tint per MANIFEST)
 * sits bottom-right on md+ viewports. See
 * `.tmp/impl-specs/impl-3-blind-vote-page.md` §2.5.
 *
 * Prop interface preserved verbatim.
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
        <div className="animate-fade-in-up bg-db-slate border border-db-rule p-8 relative overflow-hidden">
            <img
                src={unlockUrl}
                alt=""
                aria-hidden="true"
                className="absolute right-6 bottom-6 w-[240px] opacity-15 pointer-events-none hidden md:block select-none"
            />

            <div className="relative">
                <h2 className="font-display font-extrabold text-[28px] leading-[1.05] tracking-[-0.01em] text-db-chalk uppercase mb-1">
                    Reveal Phase
                </h2>
                <div className="w-12 h-px bg-db-success mb-4" aria-hidden="true" />

                <p className="font-mono text-[12px] text-db-mute leading-[1.6] max-w-[520px] mb-6">
                    Voting has ended. Reveal your committed vote before the
                    deadline — unrevealed votes are excluded from the final tally.
                </p>

                {revealDeadline > 0 && (
                    <div className="bg-db-void border border-db-rule p-5 mb-6 max-w-[480px]">
                        <div className="flex items-center gap-2 mb-2">
                            <Clock className="w-3.5 h-3.5 text-db-mute" aria-hidden="true" />
                            <span className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em]">
                                Reveal Deadline
                            </span>
                        </div>
                        <Countdown deadline={revealDeadline} />
                    </div>
                )}

                {hasCommitted && !hasRevealed && (
                    <button
                        onClick={onReveal}
                        disabled={disabled}
                        className="w-full max-w-[640px] inline-flex items-center justify-center gap-3 px-6 py-4 bg-db-success hover:bg-db-success/90 text-db-void font-display font-extrabold text-[12px] tracking-[0.20em] uppercase disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-db-success focus-visible:ring-offset-2 focus-visible:ring-offset-db-void"
                    >
                        {isProcessing && <Loader2 className="w-3.5 h-3.5 animate-spin" aria-hidden="true" />}
                        <span>{isProcessing ? 'Revealing…' : 'Reveal Vote'}</span>
                        {!isProcessing && <ArrowRight className="w-3.5 h-3.5" aria-hidden="true" />}
                    </button>
                )}

                {hasRevealed && (
                    <span className="inline-flex items-center gap-2 px-4 py-2 bg-db-success/15 border border-db-success text-db-success font-display font-extrabold text-[11px] tracking-[0.18em] uppercase">
                        <Check className="w-3.5 h-3.5" aria-hidden="true" />
                        Revealed · Vote Counted
                    </span>
                )}

                {!hasCommitted && !hasRevealed && (
                    <p className="font-mono text-[12px] text-db-mute">
                        You did not commit a vote in this poll.
                    </p>
                )}
            </div>
        </div>
    )
}
