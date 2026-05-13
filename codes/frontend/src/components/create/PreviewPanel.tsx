import { FileText } from 'lucide-react'
import { getOptionTone } from '../../lib/createOptionTone'

export type PollType = 'anon-vote' | 'blind-vote'

interface Props {
    title: string
    description: string
    pollType: PollType
    validOptions: string[]
}

/**
 * Live preview sidebar block — mirrors what the form is building so the
 * creator can see their poll headline / type-chip / option-grid forming as
 * they type. Pure presentational; consumes the form's controlled state.
 */
export function PreviewPanel({ title, description, pollType, validOptions }: Props) {
    return (
        <div className="bg-db-slate border border-db-rule p-5">
            <h3 className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em] mb-4 flex items-center gap-2">
                <FileText className="w-3.5 h-3.5" /> LIVE PREVIEW
            </h3>

            <div className="space-y-4">
                <div>
                    <p className="font-mono text-[9px] text-db-mute uppercase tracking-[0.18em] mb-1">TITLE</p>
                    <p className="font-sans font-extrabold text-[18px] leading-tight tracking-[-0.01em] text-db-chalk break-words">
                        {title || <span className="text-db-mute italic font-normal">untitled poll</span>}
                    </p>
                </div>

                {description && (
                    <div>
                        <p className="font-mono text-[9px] text-db-mute uppercase tracking-[0.18em] mb-1">DESCRIPTION</p>
                        <p className="font-mono text-[11px] text-db-chalk leading-relaxed break-words">{description}</p>
                    </div>
                )}

                <div>
                    <p className="font-mono text-[9px] text-db-mute uppercase tracking-[0.18em] mb-1">TYPE</p>
                    <span
                        className={`inline-block font-sans font-extrabold text-[10px] tracking-[0.18em] uppercase px-2 py-1 ${
                            pollType === 'blind-vote' ? 'bg-db-oltremare text-db-void' : 'bg-db-segnale text-db-void'
                        }`}
                    >
                        {pollType === 'blind-vote' ? 'BLIND · COMMIT-REVEAL' : 'ANONYMOUS · ZK'}
                    </span>
                </div>

                {validOptions.length > 0 && (
                    <div>
                        <p className="font-mono text-[9px] text-db-mute uppercase tracking-[0.18em] mb-2">
                            OPTIONS · {String(validOptions.length).padStart(2, '0')}
                        </p>
                        <div className="flex flex-col gap-px bg-db-rule">
                            {validOptions.map((opt, i) => {
                                const tone = getOptionTone(i)
                                return (
                                    <div key={i} className="flex items-center gap-3 bg-db-void px-3 py-2">
                                        <span className={`font-sans font-extrabold text-[11px] tabular-nums w-6 ${tone.text}`}>
                                            {String(i + 1).padStart(2, '0')}
                                        </span>
                                        <span className="font-mono text-[11px] text-db-chalk truncate">{opt}</span>
                                    </div>
                                )
                            })}
                        </div>
                    </div>
                )}
            </div>
        </div>
    )
}
