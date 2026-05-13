import { Radio, Zap } from 'lucide-react'
import { OptionShowdownCard } from './OptionShowdownCard'
import { ShowdownDivider } from './ShowdownDivider'
import { getOptionColor } from '../../lib/pollOptionPalette'
import authenticationSvg from '../../assets/illustrations/authentication.svg'

/**
 * Centerpiece of the Poll page. Renders the "cast a vote" UI as either:
 *
 * - **showdown** layout (when there are exactly 2 options): side-by-side
 *   colour-coded cards with a central `VS` column and a live delta;
 * - **ranked-rows** layout (when ≥3 options): vertically-stacked rows where
 *   each row is the same `OptionShowdownCard` with `variant="row"`.
 *
 * The cast button is **dormant** (`[ SELECT AN OPTION ]`) until the voter picks
 * an option; this is the headline UX change for Dark Bauhaus. When an option
 * is picked, the button background swaps to the picked option's colour.
 *
 * Render only when `localIdentity && currentPollState === 1 && !hasVoted`.
 * All wallet / relay / proof handling stays in the parent — this component
 * is pure presentation.
 */
export function VoteShowdownCard({
    pollOptions,
    selectedOption,
    onSelectOption,
    voteCounts,
    totalVotes,
    useRelay,
    onSetUseRelay,
    onCast,
    voteButtonLabel,
    voteDisabled,
    voteHintText,
    pollAddress,
}: {
    pollOptions: string[]
    selectedOption: number | null
    onSelectOption: (i: number) => void
    voteCounts: number[]
    totalVotes: number
    useRelay: boolean
    onSetUseRelay: (v: boolean) => void
    onCast: () => void
    voteButtonLabel: string
    voteDisabled: boolean
    voteHintText?: string
    pollAddress: string | undefined
}) {
    const isBinary = pollOptions.length === 2
    const pollAddrShort = pollAddress
        ? `${pollAddress.slice(0, 6)}…${pollAddress.slice(-4)}`
        : '0x…'
    const hasSelection = selectedOption !== null
    const dormant = selectedOption === null
    const selectedPalette =
        selectedOption !== null ? getOptionColor(selectedOption) : null

    const castButtonClasses = dormant
        ? 'bg-db-void border border-db-rule text-db-mute cursor-not-allowed font-mono text-[12px] tracking-[0.20em] uppercase'
        : `${selectedPalette!.bg} text-db-void font-sans font-extrabold text-[14px] tracking-[0.20em] uppercase`

    const castLabel = dormant
        ? '[ SELECT AN OPTION ]'
        : `CAST VOTE → ${pollAddrShort}`

    const optionPercent = (i: number) => {
        const c = voteCounts[i] ?? 0
        return totalVotes > 0 ? (c / totalVotes) * 100 : 0
    }

    return (
        <div className="bg-db-slate border border-db-rule p-6 relative overflow-hidden">
            <h2 className="font-sans font-extrabold text-base tracking-[0.05em] uppercase text-db-chalk mb-4">
                Cast Your Vote
            </h2>

            {/* Mode toggle — Direct vs Relayer */}
            <div className="flex border border-db-rule mb-6">
                <button
                    type="button"
                    onClick={() => onSetUseRelay(false)}
                    aria-pressed={!useRelay}
                    className={`flex-1 flex items-center justify-center gap-2 py-2.5 font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase transition-colors ${
                        !useRelay
                            ? 'bg-db-chalk text-db-void'
                            : 'bg-db-void text-db-mute hover:text-db-chalk'
                    }`}
                >
                    <Radio className="w-3.5 h-3.5" />
                    Direct · Wallet
                </button>
                <button
                    type="button"
                    onClick={() => onSetUseRelay(true)}
                    aria-pressed={useRelay}
                    className={`flex-1 flex items-center justify-center gap-2 py-2.5 font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase transition-colors ${
                        useRelay
                            ? 'bg-db-chalk text-db-void'
                            : 'bg-db-void text-db-mute hover:text-db-chalk'
                    }`}
                >
                    <Zap className="w-3.5 h-3.5" />
                    Relayer · No Wallet
                </button>
            </div>

            {pollOptions.length === 0 ? (
                <p className="font-mono text-[11px] text-db-mute tracking-[0.05em]">
                    No options configured yet.
                </p>
            ) : (
                <fieldset className="border-0 p-0 m-0">
                    <legend className="sr-only">Select a voting option</legend>

                    {isBinary ? (
                        <div className="grid grid-cols-[1fr_60px_1fr] gap-0 mb-6">
                            <OptionShowdownCard
                                index={0}
                                label={pollOptions[0] ?? ''}
                                count={voteCounts[0] ?? 0}
                                pct={optionPercent(0)}
                                selected={selectedOption === 0}
                                hasSelection={hasSelection}
                                onClick={() => onSelectOption(0)}
                                variant="showdown"
                                pollAddrShort={pollAddrShort}
                            />
                            <ShowdownDivider
                                countA={voteCounts[0] ?? 0}
                                countB={voteCounts[1] ?? 0}
                            />
                            <OptionShowdownCard
                                index={1}
                                label={pollOptions[1] ?? ''}
                                count={voteCounts[1] ?? 0}
                                pct={optionPercent(1)}
                                selected={selectedOption === 1}
                                hasSelection={hasSelection}
                                onClick={() => onSelectOption(1)}
                                variant="showdown"
                                pollAddrShort={pollAddrShort}
                            />
                        </div>
                    ) : (
                        <div className="flex flex-col gap-px bg-db-rule mb-6">
                            {pollOptions.map((opt, i) => (
                                <OptionShowdownCard
                                    key={i}
                                    index={i}
                                    label={opt}
                                    count={voteCounts[i] ?? 0}
                                    pct={optionPercent(i)}
                                    selected={selectedOption === i}
                                    hasSelection={hasSelection}
                                    onClick={() => onSelectOption(i)}
                                    variant="row"
                                    pollAddrShort={pollAddrShort}
                                />
                            ))}
                        </div>
                    )}

                    {/* Cast button */}
                    <button
                        type="button"
                        onClick={onCast}
                        disabled={voteDisabled || dormant}
                        aria-disabled={voteDisabled || dormant}
                        className={`w-full py-5 px-6 flex items-center justify-between transition-colors disabled:opacity-60 disabled:cursor-not-allowed focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-db-chalk ${castButtonClasses}`}
                    >
                        <span>{castLabel}</span>
                        {!dormant && (
                            <span className="font-mono text-[11px] text-db-void/70 tracking-[0.12em] normal-case">
                                {voteHintText ?? voteButtonLabel}
                            </span>
                        )}
                    </button>

                    {/* Sub-caption */}
                    <p className="mt-3 font-mono text-[11px] text-db-mute tracking-[0.05em]">
                        prover ready · scope {pollAddrShort} · waits for block
                        inclusion
                    </p>
                </fieldset>
            )}

            {/* Watermark illustration */}
            <img
                src={authenticationSvg}
                alt=""
                aria-hidden="true"
                className="absolute right-0 bottom-0 w-[180px] opacity-[0.15] pointer-events-none select-none"
            />
        </div>
    )
}
