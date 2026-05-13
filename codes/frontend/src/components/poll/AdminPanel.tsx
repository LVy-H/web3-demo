import { Settings, Users, Copy, Plus } from 'lucide-react'

/**
 * Owner-only control panel for an anonymous Poll. Three sub-panels:
 *
 * 1. Lifecycle — Start Voting / End Voting buttons.
 * 2. Manage Options — list + add-option input (Registration phase only).
 * 3. Generate Tokens — bulk-create invite tokens + on-chain register
 *    (Registration phase only).
 *
 * All transactions are delegated to the parent via the `on*` callbacks; this
 * component only owns its presentation.
 */
export function AdminPanel(props: {
    currentPollState: number
    isConnected: boolean
    isWrongNetwork: boolean
    isPending: boolean
    pollOptions: string[]
    newOptionLabel: string
    onChangeNewOptionLabel: (v: string) => void
    tokenCount: number
    onChangeTokenCount: (n: number) => void
    generatedTokens: string[]
    copiedIndex: number | null
    onCopyToken: (token: string, index: number) => void
    onCopyAllTokens: () => void
    onStartVoting: () => void
    onEndVoting: () => void
    onAddOption: () => void
    onGenerateTokens: () => void
}) {
    const {
        currentPollState,
        isConnected,
        isWrongNetwork,
        isPending,
        pollOptions,
        newOptionLabel,
        onChangeNewOptionLabel,
        tokenCount,
        onChangeTokenCount,
        generatedTokens,
        copiedIndex,
        onCopyToken,
        onCopyAllTokens,
        onStartVoting,
        onEndVoting,
        onAddOption,
        onGenerateTokens,
    } = props

    const baseBlocked = !isConnected || isWrongNetwork

    return (
        <div className="bg-db-slate border-2 border-db-segnale p-6">
            <div className="flex items-center gap-2 mb-4">
                <Settings className="w-3.5 h-3.5 text-db-segnale" />
                <h2 className="font-sans font-extrabold text-[11px] tracking-[0.20em] uppercase text-db-segnale">
                    Admin Panel
                </h2>
            </div>

            {/* Lifecycle */}
            <div className="flex gap-px bg-db-rule mb-6">
                <button
                    type="button"
                    onClick={onStartVoting}
                    disabled={currentPollState !== 0 || baseBlocked}
                    className="flex-1 py-3 bg-db-slate text-db-segnale hover:bg-db-segnale hover:text-db-void font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase transition-colors disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-db-slate disabled:hover:text-db-segnale focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-db-chalk"
                >
                    Start Voting
                </button>
                <button
                    type="button"
                    onClick={onEndVoting}
                    disabled={currentPollState !== 1 || baseBlocked}
                    className="flex-1 py-3 bg-db-slate text-db-segnale hover:bg-db-segnale hover:text-db-void font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase transition-colors disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-db-slate disabled:hover:text-db-segnale focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-db-chalk"
                >
                    Close Poll
                </button>
            </div>

            {/* Manage Options (Registration only) */}
            {currentPollState === 0 && (
                <div className="mb-6">
                    <h3 className="font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase text-db-chalk mb-3">
                        Manage Options
                    </h3>
                    {pollOptions.length > 0 && (
                        <div className="mb-3 space-y-1">
                            {pollOptions.map((opt, i) => (
                                <div
                                    key={i}
                                    className="bg-db-void border border-db-rule p-3 flex items-center gap-3 font-mono text-[12px] text-db-chalk"
                                >
                                    <span className="w-5 h-5 bg-db-segnale text-db-void font-sans font-extrabold text-[10px] flex items-center justify-center">
                                        {i + 1}
                                    </span>
                                    <span className="truncate">{opt}</span>
                                </div>
                            ))}
                        </div>
                    )}
                    <div className="flex flex-col sm:flex-row gap-2">
                        <input
                            type="text"
                            placeholder="new option label…"
                            value={newOptionLabel}
                            onChange={(e) => onChangeNewOptionLabel(e.target.value)}
                            aria-label="New option label"
                            className="flex-1 bg-db-void border border-db-rule focus:border-db-segnale focus:outline-none px-4 py-3 text-db-chalk placeholder:text-db-mute font-mono text-[12px]"
                        />
                        <button
                            type="button"
                            onClick={onAddOption}
                            disabled={!newOptionLabel.trim() || baseBlocked || isPending}
                            className="inline-flex items-center justify-center gap-1.5 bg-db-segnale hover:bg-db-segnale/90 text-db-void font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase px-5 py-3 transition-colors disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-db-chalk"
                        >
                            <Plus className="w-3.5 h-3.5" />
                            {isPending ? '…' : 'Add'}
                        </button>
                    </div>
                </div>
            )}

            {/* Generate Tokens (Registration only) */}
            {currentPollState === 0 && (
                <div className="border-t border-db-rule pt-4">
                    <div className="flex items-center gap-2 mb-2">
                        <Users className="w-4 h-4 text-db-segnale" />
                        <h3 className="font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase text-db-chalk">
                            Generate Vote Tokens
                        </h3>
                    </div>
                    <p className="font-mono text-[11px] text-db-mute leading-relaxed mb-3">
                        Create anonymous invite tokens and register them on-chain.
                        Distribute token strings privately to voters.
                    </p>
                    <div className="flex gap-2 mb-4">
                        <input
                            type="number"
                            min={1}
                            max={50}
                            value={tokenCount}
                            onChange={(e) => onChangeTokenCount(Number(e.target.value))}
                            aria-label="Number of tokens to generate"
                            className="w-20 bg-db-void border border-db-rule focus:border-db-segnale focus:outline-none px-3 py-3 text-db-chalk text-center font-mono text-[12px]"
                        />
                        <button
                            type="button"
                            onClick={onGenerateTokens}
                            disabled={baseBlocked || isPending}
                            className="flex-1 bg-db-segnale hover:bg-db-segnale/90 text-db-void font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase px-5 py-3 transition-colors disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-db-chalk"
                        >
                            {isPending ? 'Generating…' : `Generate ${tokenCount} Tokens`}
                        </button>
                    </div>

                    {generatedTokens.length > 0 && (
                        <div className="bg-db-void border border-db-rule p-4 max-h-60 overflow-y-auto">
                            <div className="flex items-center justify-between mb-3">
                                <span className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em]">
                                    Invite tokens · distribute privately
                                </span>
                                <button
                                    type="button"
                                    onClick={onCopyAllTokens}
                                    className="font-mono text-[10px] text-db-mute hover:text-db-chalk uppercase tracking-[0.12em] px-2 py-1 border border-db-rule hover:border-db-chalk transition-colors"
                                >
                                    Copy All
                                </button>
                            </div>
                            {generatedTokens.map((t, i) => (
                                <button
                                    type="button"
                                    key={i}
                                    onClick={() => onCopyToken(t, i)}
                                    className={`w-full flex items-center gap-3 px-2 py-1.5 font-mono text-[11px] hover:bg-db-slate cursor-pointer text-left transition-colors ${
                                        copiedIndex === i ? 'bg-db-success/10' : ''
                                    }`}
                                >
                                    <span className="text-db-mute w-6 tabular-nums">
                                        {String(i + 1).padStart(2, '0')}
                                    </span>
                                    <code className="text-db-success break-all flex-1">
                                        {t}
                                    </code>
                                    {copiedIndex === i ? (
                                        <span className="text-db-success shrink-0 uppercase tracking-[0.12em] text-[10px]">
                                            Copied
                                        </span>
                                    ) : (
                                        <Copy className="w-3.5 h-3.5 text-db-mute shrink-0" />
                                    )}
                                </button>
                            ))}
                        </div>
                    )}
                </div>
            )}
        </div>
    )
}
