import { Link } from 'react-router-dom'
import { ArrowLeft } from 'lucide-react'

/**
 * Page-top breadcrumb + label row for the BlindPoll page, restyled in the
 * Dark Bauhaus grammar (see `.tmp/impl-specs/impl-3-blind-vote-page.md`
 * §2.10). Distinguishes blind-vote from anon-vote by tagging the right
 * cluster with `bg-db-oltremare` (blue) rather than segnale (red, used
 * by the anon-vote page header).
 */
export function PageHeader({ pollAddress }: { pollAddress: string | undefined }) {
    const shortAddr = pollAddress ? `${pollAddress.slice(0, 6)}…${pollAddress.slice(-4)}` : '0x…'

    return (
        <div className="flex items-center justify-between py-4 border-b border-db-rule animate-fade-in-up">
            <Link
                to="/"
                className="inline-flex items-center gap-2 px-2 py-1 font-mono text-[11px] tracking-[0.18em] uppercase text-db-mute hover:text-db-chalk transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-db-oltremare focus-visible:ring-offset-1 focus-visible:ring-offset-db-void"
            >
                <ArrowLeft className="w-3.5 h-3.5" aria-hidden="true" />
                Back to Polls
            </Link>
            <div className="flex items-stretch gap-px bg-db-rule border border-db-rule">
                <span className="bg-db-oltremare text-db-void px-3 py-1.5 font-display font-extrabold text-[11px] tracking-[0.20em] uppercase">
                    Blind·Vote
                </span>
                <span className="bg-db-void text-db-chalk-dim px-3 py-1.5 font-mono text-[11px] tabular-nums tracking-[0.05em]">
                    {shortAddr}
                </span>
            </div>
        </div>
    )
}
