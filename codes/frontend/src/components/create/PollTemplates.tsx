import { Sparkles } from 'lucide-react'

/**
 * Poll templates — pre-fills title/description/options for common poll
 * archetypes. Defeats the blank-page anxiety on /create.
 *
 * Selecting a template REPLACES the current form state. Apply prompts
 * (in the parent) handle that confirmation when needed.
 */
export type PollTemplate = {
    id: string
    label: string
    pollType: 'anon-vote' | 'blind-vote'
    title: string
    description: string
    options: string[]
}

export const POLL_TEMPLATES: ReadonlyArray<PollTemplate> = [
    {
        id: 'treasury',
        label: 'Treasury allocation',
        pollType: 'anon-vote',
        title: 'Q? Treasury Allocation',
        description: 'How should the treasury be allocated this quarter? Each line item is a discrete spending bucket; the option with the highest vote count is funded.',
        options: ['Engineering & infra', 'Marketing & growth', 'Grants programme', 'Reserve / runway'],
    },
    {
        id: 'member-admission',
        label: 'Member admission',
        pollType: 'anon-vote',
        title: 'Admit new member',
        description: 'Should we admit the proposed candidate? See the discussion thread for context (KYC, prior contributions, references).',
        options: ['Yes, admit', 'No, reject', 'Abstain'],
    },
    {
        id: 'bug-priority',
        label: 'Bug priority',
        pollType: 'blind-vote',
        title: 'Which bug should we fix first?',
        description: 'Pick ONE bug we should prioritise next sprint. Blind voting prevents anchoring on early popular choices.',
        options: ['Critical: data loss', 'High: performance regression', 'Medium: UI polish', 'Low: docs/typos'],
    },
    {
        id: 'governance',
        label: 'Governance proposal',
        pollType: 'anon-vote',
        title: 'Adopt proposal #',
        description: 'Vote to adopt or reject this governance proposal. Quorum and execution rules apply per the charter.',
        options: ['Adopt', 'Reject', 'Defer to next round'],
    },
    {
        id: 'yes-no',
        label: 'Quick yes/no',
        pollType: 'anon-vote',
        title: '',
        description: '',
        options: ['Yes', 'No'],
    },
] as const

interface Props {
    onApply: (template: PollTemplate) => void
}

export function PollTemplatesPicker({ onApply }: Props) {
    return (
        <div className="flex flex-col gap-3 pb-6 border-b border-db-rule">
            <span className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em] flex items-center gap-2">
                <Sparkles className="w-3.5 h-3.5" />
                <span>00 · TEMPLATES</span>
                <span className="font-mono text-[10px] text-db-mute normal-case opacity-60">(start from a preset)</span>
            </span>
            <div className="flex flex-wrap gap-px bg-db-rule">
                {POLL_TEMPLATES.map(t => (
                    <button
                        key={t.id}
                        type="button"
                        onClick={() => onApply(t)}
                        className="px-3 py-2 bg-db-void hover:bg-db-slate text-db-chalk-dim hover:text-db-chalk font-mono text-[11px] uppercase tracking-[0.12em] transition-colors cursor-pointer"
                        title={`${t.pollType === 'blind-vote' ? 'Blind ·' : 'Anon ·'} ${t.options.length} options · ${t.description.slice(0, 60)}…`}
                    >
                        {t.label}
                    </button>
                ))}
            </div>
        </div>
    )
}
