import { ShieldCheck, Check, X } from 'lucide-react'
import verifiedSvg from '../../assets/illustrations/verified.svg'
import celebrationSvg from '../../assets/illustrations/celebration.svg'

type Variant = 'pre-vote' | 'post-vote' | 'post-close'

/**
 * Two-column "RECORDED ON-CHAIN vs NEVER" privacy receipt. Variants only
 * affect the watermark choice:
 *
 * - `pre-vote` / `post-close`: `verified.svg` at 120px / 15% opacity.
 * - `post-vote`              : `celebration.svg` at 160px / 20% opacity.
 */
export function PrivacyReceiptPanel({
    variant = 'pre-vote',
}: {
    variant?: Variant
    blockNumber?: number | null
}) {
    const watermark = variant === 'post-vote' ? celebrationSvg : verifiedSvg
    const watermarkClass =
        variant === 'post-vote'
            ? 'w-[160px] opacity-[0.20]'
            : 'w-[120px] opacity-[0.15]'

    return (
        <div className="relative overflow-hidden bg-db-slate border border-db-rule p-6">
            <div className="flex items-center gap-2 mb-4">
                <ShieldCheck className="w-5 h-5 text-db-success" />
                <h2 className="font-sans font-extrabold text-base tracking-[0.05em] uppercase text-db-chalk">
                    Privacy Receipt
                </h2>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-px bg-db-rule">
                <div className="bg-db-slate p-4">
                    <p className="font-mono text-[10px] text-db-success uppercase tracking-[0.18em] mb-3">
                        Recorded on-chain
                    </p>
                    <ul className="space-y-2">
                        {[
                            'vote choice (proof message)',
                            'nullifier hash',
                            'merkle root proof',
                        ].map((line) => (
                            <li
                                key={line}
                                className="flex items-start gap-2 font-mono text-[11px] text-db-mute"
                            >
                                <Check className="w-3 h-3 text-db-success mt-0.5 shrink-0" />
                                <span>{line}</span>
                            </li>
                        ))}
                    </ul>
                </div>
                <div className="bg-db-slate p-4">
                    <p className="font-mono text-[10px] text-db-segnale uppercase tracking-[0.18em] mb-3">
                        Never recorded
                    </p>
                    <ul className="space-y-2">
                        {[
                            'wallet address',
                            'private key',
                            'identity ↔ vote linkage',
                        ].map((line) => (
                            <li
                                key={line}
                                className="flex items-start gap-2 font-mono text-[11px] text-db-mute"
                            >
                                <X className="w-3 h-3 text-db-segnale mt-0.5 shrink-0" />
                                <span>{line}</span>
                            </li>
                        ))}
                    </ul>
                </div>
            </div>

            <div className="mt-4 pt-4 border-t border-db-rule flex items-center gap-3 font-mono text-[10px] text-db-mute tracking-[0.08em] uppercase">
                <span
                    className="w-1.5 h-1.5 bg-db-success"
                    aria-hidden="true"
                />
                {/* TODO(impl-2): wire to receipt.blockNumber once exposed */}
                Verified on-chain · Block #—
            </div>

            <img
                src={watermark}
                alt=""
                aria-hidden="true"
                className={`absolute right-0 bottom-0 pointer-events-none select-none ${watermarkClass}`}
            />
        </div>
    )
}
