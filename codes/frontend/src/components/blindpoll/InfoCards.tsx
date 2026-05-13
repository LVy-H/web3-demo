import { Key, Lock } from 'lucide-react'

/**
 * Two `PhaseGate`-style cards used by BlindPoll when a phase or wallet
 * condition blocks normal interaction. Restyled per
 * `.tmp/impl-specs/impl-3-blind-vote-page.md` §2.6:
 *
 *   - 1px slate card with a 2px hairline left-border (tone per state)
 *   - 40×40 icon box with a hairline border
 *   - uppercase display-extrabold title + mono leading-relaxed body
 *
 * The earlier `TrustBanner` export is dropped — the trust message moves
 * into a hairline metadata strip inlined in `BlindPoll.tsx` (spec §2.2).
 */

export function FinalizedCard() {
    return (
        <div className="animate-fade-in-up bg-db-slate border-l-2 border-db-mute p-5 flex items-start gap-4 max-w-[640px]">
            <div className="w-10 h-10 border border-db-rule flex items-center justify-center flex-shrink-0">
                <Lock className="w-5 h-5 text-db-mute" aria-hidden="true" />
            </div>
            <div>
                <p className="font-display font-extrabold text-[14px] tracking-[0.02em] text-db-chalk uppercase">
                    Results Finalized
                </p>
                <p className="font-mono text-[11px] text-db-mute leading-relaxed mt-1">
                    The reveal window has closed and results are final. Unrevealed
                    votes were excluded.
                </p>
            </div>
        </div>
    )
}

export function NotConnectedCard() {
    return (
        <div className="animate-fade-in-up bg-db-slate border-l-2 border-db-segnale p-5 flex items-start gap-4 max-w-[640px]">
            <div className="w-10 h-10 border border-db-rule flex items-center justify-center flex-shrink-0">
                <Key className="w-5 h-5 text-db-segnale" aria-hidden="true" />
            </div>
            <div>
                <p className="font-display font-extrabold text-[14px] tracking-[0.02em] text-db-chalk uppercase">
                    Wallet Not Connected
                </p>
                <p className="font-mono text-[11px] text-db-mute leading-relaxed mt-1">
                    Connect your wallet to register, vote, or reveal.
                </p>
            </div>
        </div>
    )
}
