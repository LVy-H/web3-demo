import { Check } from 'lucide-react'
import type { Identity } from '@semaphore-protocol/identity'
import secureLoginSvg from '../../assets/illustrations/secure-login.svg'

/**
 * Identity panel. Two states:
 *
 * - **Identity loaded** — green-success "IDENTITY READY" chip, two mono
 *   metadata lines (commitment short hash, scope short hash), and a CLEAR
 *   ghost action.
 * - **No identity** — invite-token input + LOAD IDENTITY CTA. All key handling
 *   stays in the parent; this component just emits change/click events.
 *
 * Background watermark: `secure-login.svg` at bottom-right, 15% opacity.
 */
export function IdentityCard({
    localIdentity,
    inviteToken,
    onInviteTokenChange,
    onLoadIdentity,
    onClearIdentity,
    pollAddress,
}: {
    localIdentity: Identity | null
    inviteToken: string
    onInviteTokenChange: (v: string) => void
    onLoadIdentity: () => void
    onClearIdentity: () => void
    pollAddress: string | undefined
}) {
    const shortPoll = pollAddress
        ? `${pollAddress.slice(0, 8)}…${pollAddress.slice(-6)}`
        : '0x…'
    const commitmentShort = localIdentity
        ? `${localIdentity.commitment.toString().slice(0, 6)}…${localIdentity.commitment.toString().slice(-4)}`
        : ''

    return (
        <div className="relative overflow-hidden bg-db-slate border border-db-rule p-6">
            <h2 className="font-sans font-extrabold text-base tracking-[0.05em] uppercase text-db-chalk mb-1">
                Identity
            </h2>
            <p className="font-mono text-[11px] text-db-mute leading-relaxed mb-4">
                Your private key stays in your browser. It is mathematically
                impossible to link your identity to your vote.
            </p>

            {localIdentity ? (
                <div className="flex items-start justify-between gap-4 flex-wrap">
                    <div className="space-y-2 min-w-0">
                        <span className="inline-flex items-center gap-2 px-3 py-1.5 bg-db-success/15 border border-db-success text-db-success font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase">
                            <Check className="w-3.5 h-3.5" />
                            Identity Ready
                        </span>
                        <p className="font-mono text-[11px] text-db-mute tracking-[0.04em]">
                            commitment {commitmentShort}
                        </p>
                        <p className="font-mono text-[11px] text-db-mute tracking-[0.04em]">
                            scope {shortPoll}
                        </p>
                    </div>
                    <button
                        type="button"
                        onClick={onClearIdentity}
                        className="text-[11px] font-mono text-db-mute hover:text-db-segnale uppercase tracking-[0.12em] transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-db-chalk"
                    >
                        [ Clear ↵ ]
                    </button>
                </div>
            ) : (
                <div className="flex flex-col sm:flex-row gap-2">
                    <input
                        type="text"
                        placeholder="paste your invite token…"
                        value={inviteToken}
                        onChange={(e) => onInviteTokenChange(e.target.value)}
                        aria-label="Invite token"
                        className="flex-1 bg-db-void border border-db-rule focus:border-db-segnale focus:outline-none px-4 py-3 text-db-chalk placeholder:text-db-mute font-mono text-[12px]"
                    />
                    <button
                        type="button"
                        onClick={onLoadIdentity}
                        className="bg-db-segnale hover:bg-db-segnale/90 text-db-void font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase px-5 py-3 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-db-chalk"
                    >
                        Load Identity →
                    </button>
                </div>
            )}

            <img
                src={secureLoginSvg}
                alt=""
                aria-hidden="true"
                className="absolute right-0 bottom-0 w-[140px] opacity-[0.15] pointer-events-none select-none"
            />
        </div>
    )
}
