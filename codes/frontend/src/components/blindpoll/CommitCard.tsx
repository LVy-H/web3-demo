import { ArrowRight, Loader2, Lock, Radio, Zap } from 'lucide-react'
import alarmClockUrl from '../../assets/illustrations/alarm-clock.svg'

/**
 * Voting-phase hero card. State A (not yet committed) shows the mode
 * toggle (Direct active, Relayer disabled — see existing `useBlindVote`
 * wiring; the relayer endpoint does not exist yet), the option list as a
 * hairline-divided mono stack with `( )` / `(•)` glyphs, and a wide
 * commit CTA. State B (already committed) collapses into a sealed-status
 * card with a "saved locally" callout when `hasSavedCommit` is true.
 *
 * Both states share the `alarm-clock.svg` watermark (commit phase →
 * time-locked illustration per MANIFEST). See
 * `.tmp/impl-specs/impl-3-blind-vote-page.md` §2.4.
 *
 * Prop interface is preserved verbatim.
 */
export function CommitCard(props: {
    pollOptions: string[]
    selectedOption: number
    onSelectOption: (i: number) => void
    onCommit: () => void
    hasCommitted: boolean
    hasSavedCommit: boolean
    isConnected: boolean
    isProcessing: boolean
    disabled: boolean
}) {
    const {
        pollOptions, selectedOption, onSelectOption, onCommit,
        hasCommitted, hasSavedCommit, isConnected, isProcessing, disabled,
    } = props

    if (hasCommitted) {
        return (
            <div className="animate-fade-in-up bg-db-slate border-l-2 border-db-oltremare p-8 relative overflow-hidden">
                <img
                    src={alarmClockUrl}
                    alt=""
                    aria-hidden="true"
                    className="absolute right-6 bottom-6 w-[180px] opacity-15 pointer-events-none hidden md:block select-none"
                />
                <div className="relative">
                    <div className="flex items-center gap-3 mb-2">
                        <Lock className="w-5 h-5 text-db-oltremare" aria-hidden="true" />
                        <h2 className="font-display font-extrabold text-[20px] leading-[1.05] tracking-[-0.01em] text-db-chalk uppercase">
                            Vote Committed
                        </h2>
                    </div>
                    <div className="w-12 h-px bg-db-oltremare mb-4" aria-hidden="true" />
                    <p className="font-mono text-[12px] text-db-mute leading-[1.6] max-w-[480px] mb-4">
                        Your vote is sealed. Return to this poll after voting closes
                        to reveal your choice.
                    </p>
                    {hasSavedCommit && (
                        <div className="bg-db-void border border-db-rule p-3 max-w-[640px]">
                            <p className="font-mono text-[10px] text-db-success uppercase tracking-[0.18em] mb-1">
                                Saved Locally
                            </p>
                            <p className="font-mono text-[11px] text-db-chalk leading-relaxed">
                                reveal data stored in this browser · do not clear cache before reveal
                            </p>
                        </div>
                    )}
                </div>
            </div>
        )
    }

    // State A — not yet committed
    let ctaLabel: string
    if (!isConnected) ctaLabel = 'Connect Wallet First'
    else if (isProcessing) ctaLabel = 'Sealing Commitment…'
    else ctaLabel = 'Commit Vote — Seal Choice'

    return (
        <div className="animate-fade-in-up bg-db-slate border border-db-rule p-8 relative overflow-hidden">
            <img
                src={alarmClockUrl}
                alt=""
                aria-hidden="true"
                className="absolute right-6 bottom-6 w-[240px] opacity-15 pointer-events-none hidden md:block select-none"
            />

            <div className="relative">
                <h2 className="font-display font-extrabold text-[28px] leading-[1.05] tracking-[-0.01em] text-db-chalk uppercase mb-1">
                    Commit Your Vote
                </h2>
                <div className="w-12 h-px bg-db-oltremare mb-4" aria-hidden="true" />

                <p className="font-mono text-[12px] text-db-mute leading-[1.6] max-w-[520px] mb-6">
                    Pick one option. We hash your choice with a per-vote salt and
                    submit only the hash. Your selection stays sealed until the
                    reveal phase.
                </p>

                {/*
                    Direct/Relayer mode toggle. The blind-vote relayer endpoint
                    does not exist yet, so the Relayer cell stays disabled with
                    a tooltip. Flip this once the endpoint ships.
                */}
                <div className="flex border border-db-rule mb-6 max-w-[480px]">
                    <button
                        type="button"
                        aria-pressed="true"
                        className="flex-1 bg-db-chalk text-db-void font-display font-extrabold text-[11px] tracking-[0.18em] uppercase py-2.5 inline-flex items-center justify-center gap-2"
                    >
                        <Radio className="w-3.5 h-3.5" aria-hidden="true" />
                        Direct (Wallet)
                    </button>
                    <button
                        type="button"
                        aria-pressed="false"
                        disabled
                        title="Relayer support for blind-vote commits is coming soon."
                        className="flex-1 bg-db-void text-db-mute opacity-40 cursor-not-allowed font-display font-extrabold text-[11px] tracking-[0.18em] uppercase py-2.5 inline-flex items-center justify-center gap-2 border-l border-db-rule"
                    >
                        <Zap className="w-3.5 h-3.5" aria-hidden="true" />
                        Relayer (Soon)
                    </button>
                </div>

                {pollOptions.length === 0 ? (
                    <p className="font-mono text-[12px] text-db-mute">No options configured yet.</p>
                ) : (
                    <fieldset>
                        <legend className="sr-only">Select a voting option</legend>
                        <div className="flex flex-col gap-px bg-db-rule border border-db-rule mb-6 max-w-[640px]">
                            {pollOptions.map((opt, i) => {
                                const selected = selectedOption === i
                                return (
                                    <button
                                        key={i}
                                        type="button"
                                        onClick={() => onSelectOption(i)}
                                        role="radio"
                                        aria-checked={selected}
                                        className={`text-left p-4 flex items-center gap-4 font-mono transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-db-oltremare ${
                                            selected
                                                ? 'bg-db-oltremare/15 border-l-2 border-db-oltremare text-db-chalk'
                                                : 'bg-db-void hover:bg-db-slate text-db-chalk'
                                        }`}
                                    >
                                        <span className="font-mono text-[14px] text-db-oltremare" aria-hidden="true">
                                            {selected ? '(•)' : '( )'}
                                        </span>
                                        <span
                                            className={
                                                selected
                                                    ? 'font-display font-extrabold text-[16px] tracking-[0.02em] text-db-chalk uppercase'
                                                    : 'text-[14px] text-db-chalk'
                                            }
                                        >
                                            {opt}
                                        </span>
                                        <span className="ml-auto font-mono text-[10px] text-db-mute tracking-[0.18em] uppercase tabular-nums">
                                            option · {String(i + 1).padStart(2, '0')}
                                        </span>
                                    </button>
                                )
                            })}
                        </div>

                        <button
                            onClick={onCommit}
                            disabled={disabled}
                            className="w-full max-w-[640px] inline-flex items-center justify-center gap-3 px-6 py-4 bg-db-oltremare hover:bg-db-oltremare/90 text-db-void font-display font-extrabold text-[12px] tracking-[0.20em] uppercase disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-db-oltremare focus-visible:ring-offset-2 focus-visible:ring-offset-db-void"
                        >
                            {isProcessing && <Loader2 className="w-3.5 h-3.5 animate-spin" aria-hidden="true" />}
                            <span>{ctaLabel}</span>
                            {!isProcessing && isConnected && <ArrowRight className="w-3.5 h-3.5" aria-hidden="true" />}
                        </button>

                        <p className="font-mono text-[10px] text-db-mute mt-3 tracking-[0.05em]">
                            [ salt: 32 random bytes · hash: keccak256(option, salt) · reveal required before deadline ]
                        </p>
                    </fieldset>
                )}
            </div>
        </div>
    )
}
