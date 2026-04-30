import { Link } from 'react-router-dom'
import { useAllPolls } from '../hooks/useRegistry'
import type { PollInfo } from '../hooks/useRegistry'
import {
    ShieldCheck,
    Zap,
    ClipboardList,
    FileText,
    ArrowRight,
    Plus,
    Users,
    Activity,
    Clock,
    Vote,
    ChevronRight,
} from 'lucide-react'

export default function Home() {
    const { data: polls } = useAllPolls()
    const pollsArray = (polls as PollInfo[]) || []

    /* -- Derived stats ---------------------------------------------------- */
    const totalPolls = pollsArray.length
    const anonPolls = pollsArray.filter(p => p.moduleType === 'anon-vote').length
    const blindPolls = pollsArray.filter(p => p.moduleType === 'blind-vote').length
    const uniqueCreators = new Set(pollsArray.map(p => p.creator)).size

    /* -- Activity feed (derived from poll data) --------------------------- */
    const recentActivity = [...pollsArray]
        .sort((a, b) => Number(b.createdAt) - Number(a.createdAt))
        .slice(0, 5)
        .map(poll => {
            const ts = Number(poll.createdAt)
            const now = Math.floor(Date.now() / 1000)
            const diff = now - ts
            let timeAgo: string
            if (diff < 60) timeAgo = 'just now'
            else if (diff < 3600) timeAgo = `${Math.floor(diff / 60)}m ago`
            else if (diff < 86400) timeAgo = `${Math.floor(diff / 3600)}h ago`
            else timeAgo = `${Math.floor(diff / 86400)}d ago`
            return { ...poll, timeAgo }
        })

    return (
        <div className="space-y-10">

            {/* -- Hero -------------------------------------------------------- */}
            <section className="animate-fade-in-up relative overflow-hidden rounded-2xl bg-stone-900 dark:bg-stone-800 px-8 py-14 md:px-12 md:py-20 shadow-sm">
                <div className="relative flex flex-col md:flex-row items-center justify-between gap-8">
                    <div className="text-left md:max-w-lg">
                        <h1 className="text-4xl md:text-5xl font-extrabold tracking-tight text-white leading-tight">
                            Anonymous Voting
                        </h1>
                        <p className="mt-4 text-lg text-stone-400 font-normal leading-relaxed">
                            Create and participate in provably fair polls. Your identity stays private, secured by zero-knowledge cryptography.
                        </p>
                        <div className="mt-8 flex flex-wrap gap-3">
                            <Link
                                to="/create"
                                className="inline-flex items-center gap-2 px-7 py-3.5 bg-teal-600 hover:bg-teal-700 active:bg-teal-800 text-white rounded-xl text-sm font-semibold transition-colors min-h-[44px] no-underline"
                            >
                                <Plus className="w-5 h-5" />
                                Create Poll
                            </Link>
                            {pollsArray.length > 0 && (
                                <a
                                    href="#polls"
                                    className="inline-flex items-center gap-2 px-6 py-3.5 bg-white/10 hover:bg-white/20 text-white rounded-xl text-sm font-semibold transition-colors min-h-[44px] no-underline"
                                >
                                    View All Polls
                                    <ArrowRight className="w-4 h-4" />
                                </a>
                            )}
                        </div>
                    </div>
                    <div className="hidden md:flex flex-shrink-0 items-center justify-center">
                        <ShieldCheck className="w-48 h-48 text-white/10" strokeWidth={0.75} />
                    </div>
                </div>
            </section>

            {/* -- Stats Row --------------------------------------------------- */}
            <section className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                <div className="animate-fade-in-up animate-fade-in-up-1 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl p-5 hover:shadow-md hover:border-stone-300 dark:hover:border-stone-600 transition-all duration-200">
                    <div className="flex items-center gap-3 mb-3">
                        <div className="w-10 h-10 rounded-xl bg-stone-100 dark:bg-stone-800 flex items-center justify-center">
                            <ClipboardList className="w-5 h-5 text-stone-500 dark:text-stone-400" />
                        </div>
                        <span className="text-xs font-semibold text-stone-500 dark:text-stone-400 uppercase tracking-wider">Total Polls</span>
                    </div>
                    <p className="text-3xl font-bold font-mono tabular-nums text-teal-600 dark:text-teal-400 animate-count-up">{totalPolls}</p>
                </div>

                <div className="animate-fade-in-up animate-fade-in-up-2 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl p-5 hover:shadow-md hover:border-stone-300 dark:hover:border-stone-600 transition-all duration-200">
                    <div className="flex items-center gap-3 mb-3">
                        <div className="w-10 h-10 rounded-xl bg-stone-100 dark:bg-stone-800 flex items-center justify-center">
                            <Zap className="w-5 h-5 text-stone-500 dark:text-stone-400" />
                        </div>
                        <span className="text-xs font-semibold text-stone-500 dark:text-stone-400 uppercase tracking-wider">ZK Polls</span>
                    </div>
                    <p className="text-3xl font-bold font-mono tabular-nums text-teal-600 dark:text-teal-400 animate-count-up">{anonPolls}</p>
                </div>

                <div className="animate-fade-in-up animate-fade-in-up-3 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl p-5 hover:shadow-md hover:border-stone-300 dark:hover:border-stone-600 transition-all duration-200">
                    <div className="flex items-center gap-3 mb-3">
                        <div className="w-10 h-10 rounded-xl bg-stone-100 dark:bg-stone-800 flex items-center justify-center">
                            <Vote className="w-5 h-5 text-stone-500 dark:text-stone-400" />
                        </div>
                        <span className="text-xs font-semibold text-stone-500 dark:text-stone-400 uppercase tracking-wider">Blind Polls</span>
                    </div>
                    <p className="text-3xl font-bold font-mono tabular-nums text-teal-600 dark:text-teal-400 animate-count-up">{blindPolls}</p>
                </div>

                <div className="animate-fade-in-up animate-fade-in-up-4 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl p-5 hover:shadow-md hover:border-stone-300 dark:hover:border-stone-600 transition-all duration-200">
                    <div className="flex items-center gap-3 mb-3">
                        <div className="w-10 h-10 rounded-xl bg-stone-100 dark:bg-stone-800 flex items-center justify-center">
                            <Users className="w-5 h-5 text-stone-500 dark:text-stone-400" />
                        </div>
                        <span className="text-xs font-semibold text-stone-500 dark:text-stone-400 uppercase tracking-wider">Creators</span>
                    </div>
                    <p className="text-3xl font-bold font-mono tabular-nums text-teal-600 dark:text-teal-400 animate-count-up">{uniqueCreators}</p>
                </div>
            </section>

            {/* -- Main content area: Polls + Sidebar ------------------------- */}
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
                {/* -- Poll grid (2 columns) ---------------------------------- */}
                <section id="polls" className="lg:col-span-2">
                    <div className="flex items-center justify-between mb-6">
                        <h2 className="text-xl font-extrabold tracking-tight text-stone-900 dark:text-stone-100">All Polls</h2>
                        {pollsArray.length > 0 && (
                            <span className="text-xs font-semibold text-stone-400 dark:text-stone-500 bg-stone-100 dark:bg-stone-800 px-3 py-1.5 rounded-full">
                                {pollsArray.length} poll{pollsArray.length !== 1 ? 's' : ''}
                            </span>
                        )}
                    </div>

                    {pollsArray.length === 0 ? (
                        <div className="flex flex-col items-center justify-center py-16 px-8 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl">
                            <FileText className="w-16 h-16 text-stone-300 dark:text-stone-600 mb-4" />
                            <h3 className="text-lg font-extrabold tracking-tight text-stone-900 dark:text-stone-100 mb-2 text-center">No polls yet</h3>
                            <p className="text-sm text-stone-500 dark:text-stone-400 mb-6 text-center max-w-sm">
                                Be the first to create a poll. It only takes a few seconds and your voters stay completely anonymous.
                            </p>
                            <Link
                                to="/create"
                                className="inline-flex items-center gap-2 px-6 py-3 bg-teal-600 hover:bg-teal-700 text-white rounded-xl text-sm font-semibold transition-colors min-h-[44px] no-underline"
                            >
                                <Plus className="w-4 h-4" />
                                Create Your First Poll
                            </Link>
                        </div>
                    ) : (
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
                            {[...pollsArray].reverse().map((poll: PollInfo, idx: number) => {
                                const pillColor = poll.moduleType === 'blind-vote'
                                    ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                                    : 'bg-teal-100 text-teal-700 dark:bg-teal-900/30 dark:text-teal-400'
                                const delayClass = `animate-fade-in-up-${Math.min(idx + 1, 8)}`

                                // Derived metadata
                                const ts = Number(poll.createdAt)
                                const createdDate = ts > 0 ? new Date(ts * 1000).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : null

                                return (
                                    <Link
                                        key={poll.pollAddress}
                                        to={`/poll/${poll.pollAddress}`}
                                        className={`animate-fade-in-up ${delayClass} group flex flex-col bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl hover:border-teal-300 dark:hover:border-teal-600 hover:shadow-md transition-all duration-200 p-6 no-underline`}
                                    >
                                        {/* Top: badges */}
                                        <div className="flex items-center gap-2 mb-3">
                                            <span className={`text-xs font-semibold px-2.5 py-1 rounded-full uppercase tracking-wide ${pillColor}`}>
                                                {poll.moduleType}
                                            </span>
                                        </div>

                                        {/* Title + description */}
                                        <h3 className="text-lg font-semibold text-stone-900 dark:text-stone-100 group-hover:text-teal-600 dark:group-hover:text-teal-400 transition-colors leading-snug">
                                            {poll.title}
                                        </h3>
                                        {poll.description && (
                                            <p className="text-sm text-stone-500 dark:text-stone-400 mt-1.5 line-clamp-2 font-normal">
                                                {poll.description}
                                            </p>
                                        )}

                                        {/* Metadata row */}
                                        <div className="mt-3 flex items-center gap-3 text-xs text-stone-400 dark:text-stone-500">
                                            {createdDate && (
                                                <span className="flex items-center gap-1">
                                                    <Clock className="w-3.5 h-3.5" />
                                                    {createdDate}
                                                </span>
                                            )}
                                            <span className="flex items-center gap-1 font-mono">
                                                <Users className="w-3.5 h-3.5" />
                                                {poll.creator.slice(0, 6)}...
                                            </span>
                                        </div>

                                        {/* Footer */}
                                        <div className="mt-auto pt-4 border-t border-stone-100 dark:border-stone-800 flex justify-between items-center">
                                            <span className="text-xs font-mono text-stone-400 dark:text-stone-500 bg-stone-50 dark:bg-stone-800 px-2 py-1 rounded-md border border-stone-100 dark:border-stone-700">
                                                {poll.pollAddress.slice(0, 6)}...{poll.pollAddress.slice(-4)}
                                            </span>
                                            <span className="text-teal-600 dark:text-teal-400 text-sm font-semibold group-hover:translate-x-1 transition-transform inline-flex items-center gap-1">
                                                View Poll
                                                <ChevronRight className="w-4 h-4" />
                                            </span>
                                        </div>
                                    </Link>
                                )
                            })}
                        </div>
                    )}
                </section>

                {/* -- Sidebar ------------------------------------------------- */}
                <aside className="space-y-6">
                    {/* Quick Actions */}
                    <div className="animate-fade-in-up animate-fade-in-up-2 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                        <h3 className="text-xs font-bold text-stone-500 dark:text-stone-400 uppercase tracking-widest mb-4">Quick Actions</h3>
                        <div className="space-y-2">
                            <Link
                                to="/create"
                                className="flex items-center gap-3 px-4 py-3 bg-teal-50 dark:bg-teal-900/30 hover:bg-teal-100 dark:hover:bg-teal-900/50 border border-teal-200 dark:border-teal-700 rounded-xl transition-colors no-underline group"
                            >
                                <div className="w-8 h-8 rounded-lg bg-teal-600 flex items-center justify-center">
                                    <Plus className="w-4 h-4 text-white" />
                                </div>
                                <div className="flex-1">
                                    <p className="text-sm font-semibold text-teal-800 dark:text-teal-300">New ZK Poll</p>
                                    <p className="text-xs text-teal-600/70 dark:text-teal-400/60">Anonymous voting with proofs</p>
                                </div>
                                <ChevronRight className="w-4 h-4 text-teal-400 group-hover:translate-x-0.5 transition-transform" />
                            </Link>
                            <Link
                                to="/create"
                                className="flex items-center gap-3 px-4 py-3 bg-amber-50 dark:bg-amber-900/30 hover:bg-amber-100 dark:hover:bg-amber-900/50 border border-amber-200 dark:border-amber-700 rounded-xl transition-colors no-underline group"
                            >
                                <div className="w-8 h-8 rounded-lg bg-amber-500 flex items-center justify-center">
                                    <Plus className="w-4 h-4 text-white" />
                                </div>
                                <div className="flex-1">
                                    <p className="text-sm font-semibold text-amber-800 dark:text-amber-300">New Blind Poll</p>
                                    <p className="text-xs text-amber-600/70 dark:text-amber-400/60">Commit-reveal scheme</p>
                                </div>
                                <ChevronRight className="w-4 h-4 text-amber-400 group-hover:translate-x-0.5 transition-transform" />
                            </Link>
                        </div>
                    </div>

                    {/* Recent Activity */}
                    <div className="animate-fade-in-up animate-fade-in-up-3 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                        <h3 className="text-xs font-bold text-stone-500 dark:text-stone-400 uppercase tracking-widest mb-4 flex items-center gap-2">
                            <Activity className="w-4 h-4" />
                            Recent Activity
                        </h3>
                        {recentActivity.length === 0 ? (
                            <p className="text-xs text-stone-400 dark:text-stone-500">No activity yet.</p>
                        ) : (
                            <div className="space-y-3">
                                {recentActivity.map((item, i) => (
                                    <Link
                                        key={i}
                                        to={`/poll/${item.pollAddress}`}
                                        className="flex items-start gap-3 no-underline group"
                                    >
                                        <div className={`w-2 h-2 rounded-full mt-1.5 flex-shrink-0 ${
                                            item.moduleType === 'blind-vote' ? 'bg-amber-400' : 'bg-teal-400'
                                        }`} />
                                        <div className="flex-1 min-w-0">
                                            <p className="text-sm text-stone-700 dark:text-stone-300 font-medium truncate group-hover:text-teal-600 dark:group-hover:text-teal-400 transition-colors">
                                                {item.title}
                                            </p>
                                            <p className="text-xs text-stone-400 dark:text-stone-500">
                                                Created by {item.creator.slice(0, 6)}... {item.timeAgo}
                                            </p>
                                        </div>
                                    </Link>
                                ))}
                            </div>
                        )}
                    </div>

                    {/* Security Info */}
                    <div className="animate-fade-in-up animate-fade-in-up-4 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                        <h3 className="text-xs font-bold text-stone-500 dark:text-stone-400 uppercase tracking-widest mb-4 flex items-center gap-2">
                            <ShieldCheck className="w-4 h-4" />
                            Security
                        </h3>
                        <div className="space-y-3">
                            <div className="flex items-start gap-3">
                                <div className="w-8 h-8 rounded-lg bg-teal-100 dark:bg-teal-900/50 flex items-center justify-center flex-shrink-0">
                                    <ShieldCheck className="w-4 h-4 text-teal-600 dark:text-teal-400" />
                                </div>
                                <div>
                                    <p className="text-sm font-medium text-stone-700 dark:text-stone-300">ZK Proofs</p>
                                    <p className="text-xs text-stone-400 dark:text-stone-500">Semaphore + Groth16</p>
                                </div>
                            </div>
                            <div className="flex items-start gap-3">
                                <div className="w-8 h-8 rounded-lg bg-teal-100 dark:bg-teal-900/50 flex items-center justify-center flex-shrink-0">
                                    <Zap className="w-4 h-4 text-teal-600 dark:text-teal-400" />
                                </div>
                                <div>
                                    <p className="text-sm font-medium text-stone-700 dark:text-stone-300">On-Chain</p>
                                    <p className="text-xs text-stone-400 dark:text-stone-500">Verifiable & immutable</p>
                                </div>
                            </div>
                            <div className="flex items-start gap-3">
                                <div className="w-8 h-8 rounded-lg bg-teal-100 dark:bg-teal-900/50 flex items-center justify-center flex-shrink-0">
                                    <Users className="w-4 h-4 text-teal-600 dark:text-teal-400" />
                                </div>
                                <div>
                                    <p className="text-sm font-medium text-stone-700 dark:text-stone-300">Private</p>
                                    <p className="text-xs text-stone-400 dark:text-stone-500">No identity linkage</p>
                                </div>
                            </div>
                        </div>
                    </div>
                </aside>
            </div>
        </div>
    )
}
