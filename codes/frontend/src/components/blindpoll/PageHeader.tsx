import { Link } from 'react-router-dom'
import { ArrowLeft } from 'lucide-react'

/**
 * Page-top breadcrumb + label row for the BlindPoll page. Shows the back-link,
 * a "Blind Vote" tag, and the truncated poll address.
 */
export function PageHeader({ pollAddress }: { pollAddress: string | undefined }) {
    return (
        <div className="flex items-center justify-between animate-fade-in-up">
            <Link
                to="/"
                className="text-teal-600 dark:text-teal-400 hover:text-teal-800 dark:hover:text-teal-300 text-sm font-medium flex items-center gap-1.5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2 rounded-lg px-2 py-1 hover:bg-teal-50 dark:hover:bg-teal-900/30 transition-colors"
            >
                <ArrowLeft className="w-4 h-4" />
                Back to Polls
            </Link>
            <div className="flex items-center gap-2">
                <span className="text-xs font-semibold px-2.5 py-1 bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 rounded-full uppercase tracking-wide">
                    Blind Vote
                </span>
                <span className="text-xs font-mono text-stone-400 dark:text-stone-500 bg-stone-50 dark:bg-stone-800 px-2 py-1 rounded-lg border border-stone-200 dark:border-stone-700">
                    {pollAddress?.slice(0, 6)}...{pollAddress?.slice(-4)}
                </span>
            </div>
        </div>
    )
}
