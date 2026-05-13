import { Vote } from 'lucide-react'

export type PollType = 'anon-vote' | 'blind-vote'

interface Props {
    pollType: PollType
}

const ANON_STEPS: readonly string[] = [
    'Admin generates invite tokens and distributes them privately to voters.',
    'Voters load their token and cast a vote using a ZK proof — no identity revealed.',
    'Results are tallied on-chain. The contract guarantees each token votes once.',
]

const BLIND_STEPS: readonly string[] = [
    'Voters register their wallet address during the registration phase.',
    'During voting, each voter commits a hash of their choice — nobody can see votes.',
    'After voting ends, voters reveal their choices. Unrevealed votes are excluded.',
]

/**
 * Sidebar pedagogical card explaining the post-deploy lifecycle for the
 * currently-selected poll type. Step numerals carry the type's signal hue
 * (segnale for anon, oltremare for blind) so the card reads at a glance.
 */
export function HowItWorks({ pollType }: Props) {
    const steps = pollType === 'blind-vote' ? BLIND_STEPS : ANON_STEPS
    const stepColor = pollType === 'blind-vote' ? 'text-db-oltremare' : 'text-db-segnale'

    return (
        <div className="bg-db-slate border border-db-rule p-5">
            <h3 className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em] mb-4 flex items-center gap-2">
                <Vote className="w-3.5 h-3.5" /> HOW IT WORKS
            </h3>
            <ol className="space-y-3">
                {steps.map((step, i) => (
                    <li key={i} className="flex gap-3">
                        <span className={`font-sans font-extrabold text-[14px] tabular-nums w-6 shrink-0 ${stepColor}`}>
                            {String(i + 1).padStart(2, '0')}
                        </span>
                        <p className="font-mono text-[11px] text-db-mute leading-relaxed flex-1">{step}</p>
                    </li>
                ))}
            </ol>
        </div>
    )
}
