import { useState, useRef } from 'react'
import { Link } from 'react-router-dom'
import { useAccount } from 'wagmi'
import { encodeFunctionData } from 'viem'
import { SEMAPHORE_ADDRESS } from '../config'
import { useAllPolls, useCreatePoll } from '../hooks/useRegistry'
import type { PollInfo } from '../hooks/useRegistry'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'
import ZkBlindVotingABI from '../abi/ZkBlindVoting.json'

type PollType = 'anon-vote' | 'blind-vote'

/* ── Inline SVG illustrations ────────────────────────────────────── */

function HeroIllustration() {
    return (
        <svg viewBox="0 0 200 200" fill="none" stroke="currentColor" strokeWidth="1.5" className="w-48 h-48 text-white/20">
            {/* Shield outline */}
            <path d="M100 20 L160 50 L160 110 Q160 160 100 185 Q40 160 40 110 L40 50 Z" />
            {/* Ballot lines inside */}
            <line x1="70" y1="80" x2="130" y2="80" />
            <line x1="70" y1="100" x2="120" y2="100" />
            <line x1="70" y1="120" x2="110" y2="120" />
            {/* Checkmark */}
            <path d="M65 100 L75 110 L95 85" strokeWidth="2.5" />
        </svg>
    )
}

function EmptyStateIllustration() {
    return (
        <svg viewBox="0 0 120 120" fill="none" stroke="currentColor" strokeWidth="1.5" className="w-24 h-24 text-stone-300">
            <rect x="25" y="20" width="50" height="65" rx="4" transform="rotate(-5 50 52)" />
            <rect x="35" y="25" width="50" height="65" rx="4" transform="rotate(3 60 57)" />
            <line x1="45" y1="45" x2="75" y2="45" />
            <line x1="45" y1="55" x2="70" y2="55" />
            <line x1="45" y1="65" x2="60" y2="65" />
        </svg>
    )
}

/* ── Feedback message component ───────────────────────────────── */
function FeedbackMessage({ type, children }: { type: 'success' | 'error' | 'pending'; children: React.ReactNode }) {
    const styles = {
        success: 'bg-emerald-50 border-emerald-200 text-emerald-800',
        error: 'bg-rose-50 border-rose-200 text-rose-800',
        pending: 'bg-amber-50 border-amber-200 text-amber-800',
    }
    const icons = {
        success: (
            <svg className="w-5 h-5 text-emerald-500 shrink-0" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
                <path strokeLinecap="round" strokeLinejoin="round" d="m4.5 12.75 6 6 9-13.5" />
            </svg>
        ),
        error: (
            <svg className="w-5 h-5 text-rose-500 shrink-0" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
                <path strokeLinecap="round" strokeLinejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
        ),
        pending: (
            <svg className="w-5 h-5 text-amber-500 shrink-0 animate-spin" fill="none" viewBox="0 0 24 24" aria-hidden="true">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
            </svg>
        ),
    }
    return (
        <div className={`flex items-center gap-3 px-4 py-3 border rounded-xl text-sm font-semibold ${styles[type]}`} role="alert">
            {icons[type]}
            {children}
        </div>
    )
}


export default function Home() {
    const { address, isConnected } = useAccount()
    const [title, setTitle] = useState('')
    const [description, setDescription] = useState('')
    const [options, setOptions] = useState<string[]>(['', ''])
    const [formOpen, setFormOpen] = useState(false)
    const [errorMsg, setErrorMsg] = useState('')
    const [pollType, setPollType] = useState<PollType>('anon-vote')
    const [revealDuration, setRevealDuration] = useState(3600)
    const formRef = useRef<HTMLDivElement>(null)

    const { data: polls } = useAllPolls()
    const { createPoll, isPending, isConfirming, isSuccess } = useCreatePoll()

    const pollsArray = (polls as PollInfo[]) || []

    /* ── Form handlers ──────────────────────────────────────── */
    async function handleCreatePoll(e: React.FormEvent) {
        e.preventDefault()
        setErrorMsg('')
        if (!address) return
        const validOptions = options.filter(o => o.trim() !== '')
        if (validOptions.length < 2) {
            setErrorMsg('Please provide at least 2 options.')
            return
        }

        try {
            let initData: `0x${string}`
            if (pollType === 'blind-vote') {
                initData = encodeFunctionData({
                    abi: ZkBlindVotingABI.abi,
                    functionName: 'initialize',
                    args: [address, validOptions, BigInt(revealDuration)],
                }) as `0x${string}`
            } else {
                initData = encodeFunctionData({
                    abi: ZkAnonVotingABI.abi,
                    functionName: 'initialize',
                    args: [SEMAPHORE_ADDRESS, address, validOptions],
                }) as `0x${string}`
            }

            await createPoll(pollType, title, description, initData)
            setTitle('')
            setDescription('')
            setOptions(['', ''])
        } catch (err: unknown) {
            const e = err as { shortMessage?: string; message?: string }
            setErrorMsg(e.shortMessage ?? e.message ?? 'Transaction failed.')
        }
    }

    const updateOption = (index: number, value: string) => {
        const updated = [...options]
        updated[index] = value
        setOptions(updated)
    }

    const addOption = () => setOptions([...options, ''])

    const removeOption = (index: number) => {
        if (options.length <= 2) return
        setOptions(options.filter((_, i) => i !== index))
    }

    const scrollToForm = () => {
        setFormOpen(true)
        // Allow DOM to render the section before scrolling
        setTimeout(() => formRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 50)
    }

    /* ── Derived stats ──────────────────────────────────────── */
    const totalPolls = pollsArray.length
    const activePolls = pollsArray.length // Could filter by state if available

    return (
        <div className="space-y-12">

            {/* ── Hero ────────────────────────────────────────── */}
            <section className="animate-fade-in-up relative overflow-hidden rounded-2xl bg-stone-900 px-8 py-14 md:px-12 md:py-20 shadow-sm">
                <div className="relative flex flex-col md:flex-row items-center justify-between gap-8">
                    <div className="text-left md:max-w-lg">
                        <h1 className="text-4xl md:text-5xl font-extrabold tracking-tight text-white leading-tight">
                            Anonymous Voting
                        </h1>
                        <p className="mt-4 text-lg text-stone-400 font-normal leading-relaxed">
                            Create and participate in provably fair polls. Your identity stays private, secured by zero-knowledge cryptography.
                        </p>
                        <button
                            onClick={scrollToForm}
                            className="mt-8 inline-flex items-center gap-2 px-7 py-3.5 bg-teal-600 hover:bg-teal-700 active:bg-teal-800 text-white rounded-xl text-sm font-semibold transition-colors min-h-[44px] cursor-pointer"
                        >
                            {/* Plus icon */}
                            <svg className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
                                <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                            </svg>
                            Create Poll
                        </button>
                    </div>
                    <div className="hidden md:block flex-shrink-0">
                        <HeroIllustration />
                    </div>
                </div>
            </section>

            {/* ── Stats Row ──────────────────────────────────────── */}
            <section className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                {/* Total Polls */}
                <div className="animate-fade-in-up animate-fade-in-up-1 bg-white border border-stone-200 rounded-xl p-6 hover:shadow-md hover:border-stone-300 transition-all duration-200">
                    <div className="flex items-center gap-3 mb-3">
                        <div className="w-10 h-10 rounded-xl bg-stone-100 flex items-center justify-center">
                            <svg className="w-5 h-5 text-stone-500" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" d="M9 12h3.75M9 15h3.75M9 18h3.75m3 .75H18a2.25 2.25 0 0 0 2.25-2.25V6.108c0-1.135-.845-2.098-1.976-2.192a48.424 48.424 0 0 0-1.123-.08m-5.801 0c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 0 0 .75-.75 2.25 2.25 0 0 0-.1-.664m-5.8 0A2.251 2.251 0 0 1 13.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m0 0H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V9.375c0-.621-.504-1.125-1.125-1.125H8.25Z" />
                            </svg>
                        </div>
                        <span className="text-xs font-semibold text-stone-500 uppercase tracking-wider">Total Polls</span>
                    </div>
                    <p className="text-3xl font-bold font-mono tabular-nums text-teal-600 animate-count-up">{totalPolls}</p>
                </div>

                {/* Active Polls */}
                <div className="animate-fade-in-up animate-fade-in-up-2 bg-white border border-stone-200 rounded-xl p-6 hover:shadow-md hover:border-stone-300 transition-all duration-200">
                    <div className="flex items-center gap-3 mb-3">
                        <div className="w-10 h-10 rounded-xl bg-stone-100 flex items-center justify-center">
                            <svg className="w-5 h-5 text-stone-500" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 13.5l10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75z" />
                            </svg>
                        </div>
                        <span className="text-xs font-semibold text-stone-500 uppercase tracking-wider">Active Polls</span>
                    </div>
                    <div className="flex items-baseline gap-2">
                        <p className="text-3xl font-bold font-mono tabular-nums text-teal-600 animate-count-up">{activePolls}</p>
                        {activePolls > 0 && (
                            <span className="relative flex h-2.5 w-2.5">
                                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-teal-400 opacity-75" />
                                <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-teal-500" />
                            </span>
                        )}
                    </div>
                </div>

                {/* Secured by ZK */}
                <div className="animate-fade-in-up animate-fade-in-up-3 bg-white border border-stone-200 rounded-xl p-6 hover:shadow-md hover:border-stone-300 transition-all duration-200">
                    <div className="flex items-center gap-3 mb-3">
                        <div className="w-10 h-10 rounded-xl bg-stone-100 flex items-center justify-center">
                            <svg className="w-5 h-5 text-stone-500" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" d="M9 12.75 11.25 15 15 9.75m-3-7.036A11.959 11.959 0 0 1 3.598 6 11.99 11.99 0 0 0 3 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285Z" />
                            </svg>
                        </div>
                        <span className="text-xs font-semibold text-stone-500 uppercase tracking-wider">Security</span>
                    </div>
                    <p className="text-lg font-bold text-stone-900">Secured by ZK</p>
                    <p className="text-xs text-stone-500 mt-0.5">Semaphore + Groth16 proofs</p>
                </div>
            </section>


            {/* ── Poll grid ───────────────────────────────────── */}
            <section>
                <div className="flex items-center justify-between mb-6">
                    <h2 className="text-xl font-extrabold tracking-tight text-stone-900">Active Polls</h2>
                    {pollsArray.length > 0 && (
                        <span className="text-xs font-semibold text-stone-400 bg-stone-100 px-3 py-1.5 rounded-full">
                            {pollsArray.length} poll{pollsArray.length !== 1 ? 's' : ''}
                        </span>
                    )}
                </div>

                {pollsArray.length === 0 ? (
                    /* Empty state */
                    <div className="flex flex-col items-center justify-center py-16 px-8 bg-white border border-stone-200 rounded-xl">
                        <EmptyStateIllustration />
                        <h3 className="text-lg font-extrabold tracking-tight text-stone-900 mb-2 text-center mt-6">No polls yet</h3>
                        <p className="text-sm text-stone-500 mb-6 text-center max-w-sm">
                            Be the first to create a poll. It only takes a few seconds and your voters stay completely anonymous.
                        </p>
                        <button
                            onClick={scrollToForm}
                            className="inline-flex items-center gap-2 px-6 py-3 bg-teal-600 hover:bg-teal-700 text-white rounded-xl text-sm font-semibold transition-colors min-h-[44px] cursor-pointer"
                        >
                            Create Your First Poll
                        </button>
                    </div>
                ) : (
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
                        {[...pollsArray].reverse().map((poll: PollInfo, idx: number) => {
                            const pillColor = poll.moduleType === 'blind-vote'
                                ? 'bg-amber-100 text-amber-700'
                                : 'bg-teal-100 text-teal-700'
                            const delayClass = `animate-fade-in-up-${Math.min(idx + 1, 8)}`
                            return (
                                <Link
                                    key={poll.pollAddress}
                                    to={`/poll/${poll.pollAddress}`}
                                    className={`animate-fade-in-up ${delayClass} group flex flex-col bg-white border border-stone-200 rounded-xl hover:border-teal-300 hover:shadow-md transition-all duration-200 p-6 no-underline`}
                                >
                                    {/* Top: badges */}
                                    <div className="flex items-center gap-2 mb-3">
                                        <span className={`text-xs font-semibold px-2.5 py-1 rounded-full uppercase tracking-wide ${pillColor}`}>
                                            {poll.moduleType}
                                        </span>
                                    </div>

                                    {/* Title + description */}
                                    <h3 className="text-lg font-semibold text-stone-900 group-hover:text-teal-600 transition-colors leading-snug">
                                        {poll.title}
                                    </h3>
                                    {poll.description && (
                                        <p className="text-sm text-stone-500 mt-1.5 line-clamp-2 font-normal">
                                            {poll.description}
                                        </p>
                                    )}

                                    {/* Footer */}
                                    <div className="mt-auto pt-4 border-t border-stone-100 flex justify-between items-center">
                                        <span className="text-xs font-mono text-stone-400 bg-stone-50 px-2 py-1 rounded-md border border-stone-100">
                                            {poll.pollAddress.slice(0, 6)}...{poll.pollAddress.slice(-4)}
                                        </span>
                                        <span className="text-teal-600 text-sm font-semibold group-hover:translate-x-1 transition-transform inline-flex items-center gap-1">
                                            View Poll
                                            <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
                                                <path strokeLinecap="round" strokeLinejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
                                            </svg>
                                        </span>
                                    </div>
                                </Link>
                            )
                        })}
                    </div>
                )}
            </section>


            {/* ── Create Poll form (collapsible) ──────────────── */}
            <section ref={formRef}>
                <button
                    onClick={() => setFormOpen(prev => !prev)}
                    className="flex items-center gap-2 text-lg font-extrabold tracking-tight text-stone-900 mb-4 cursor-pointer bg-transparent border-none p-0"
                    aria-expanded={formOpen}
                    aria-controls="create-poll-form"
                >
                    {/* Chevron */}
                    <svg
                        className={`w-5 h-5 text-stone-400 transition-transform duration-200 ${formOpen ? 'rotate-90' : ''}`}
                        fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true"
                    >
                        <path strokeLinecap="round" strokeLinejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
                    </svg>
                    Create a New Poll
                </button>

                {formOpen && (
                    <div
                        id="create-poll-form"
                        className="animate-fade-in-up bg-white border border-stone-200 rounded-xl shadow-sm p-6 md:p-8"
                    >
                        {/* Feedback messages */}
                        <div className="space-y-3 mb-6">
                            {isPending && <FeedbackMessage type="pending">Submitting transaction...</FeedbackMessage>}
                            {isConfirming && <FeedbackMessage type="pending">Waiting for confirmation...</FeedbackMessage>}
                            {isSuccess && <FeedbackMessage type="success">Poll created successfully!</FeedbackMessage>}
                            {errorMsg && <FeedbackMessage type="error">{errorMsg}</FeedbackMessage>}
                        </div>

                        <form onSubmit={handleCreatePoll} className="space-y-6">
                            {/* Title */}
                            <div className="flex flex-col gap-2">
                                <label htmlFor="poll-title" className="text-sm font-semibold text-stone-700">
                                    Poll Title <span className="text-rose-500">*</span>
                                </label>
                                <input
                                    id="poll-title"
                                    type="text"
                                    placeholder="e.g., Q3 Board Election"
                                    value={title}
                                    onChange={e => setTitle(e.target.value)}
                                    className="bg-stone-50 border border-stone-200 rounded-xl px-4 py-3 text-sm text-stone-900 placeholder:text-stone-400 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-teal-500 min-h-[44px] transition-all"
                                    required
                                />
                            </div>

                            {/* Description */}
                            <div className="flex flex-col gap-2">
                                <label htmlFor="poll-description" className="text-sm font-semibold text-stone-700">
                                    Description <span className="text-stone-400 font-normal">(optional)</span>
                                </label>
                                <textarea
                                    id="poll-description"
                                    placeholder="What is this poll about?"
                                    value={description}
                                    onChange={e => setDescription(e.target.value)}
                                    rows={3}
                                    className="bg-stone-50 border border-stone-200 rounded-xl px-4 py-3 text-sm text-stone-900 placeholder:text-stone-400 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-teal-500 resize-y transition-all"
                                />
                            </div>

                            {/* Poll Type Selector -- Rich Option Cards */}
                            <div className="flex flex-col gap-2">
                                <span className="text-sm font-semibold text-stone-700">Poll Type</span>
                                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                    <button
                                        type="button"
                                        onClick={() => setPollType('anon-vote')}
                                        className={`flex items-start gap-4 px-5 py-4 rounded-xl border-2 transition-all text-left cursor-pointer ${
                                            pollType === 'anon-vote'
                                                ? 'border-teal-500 bg-teal-50'
                                                : 'border-stone-200 hover:border-stone-300 bg-white'
                                        }`}
                                    >
                                        <div className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 ${
                                            pollType === 'anon-vote'
                                                ? 'bg-teal-600'
                                                : 'bg-stone-100'
                                        }`}>
                                            <svg className={`w-5 h-5 ${pollType === 'anon-vote' ? 'text-white' : 'text-stone-400'}`} fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
                                                <path strokeLinecap="round" strokeLinejoin="round" d="M9 12.75 11.25 15 15 9.75m-3-7.036A11.959 11.959 0 0 1 3.598 6 11.99 11.99 0 0 0 3 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285Z" />
                                            </svg>
                                        </div>
                                        <div>
                                            <span className={`text-sm font-semibold ${pollType === 'anon-vote' ? 'text-teal-800' : 'text-stone-600'}`}>
                                                Anonymous (ZK)
                                            </span>
                                            <span className={`block text-xs font-normal mt-0.5 ${pollType === 'anon-vote' ? 'text-teal-600/70' : 'text-stone-400'}`}>
                                                Zero-knowledge proofs. No one can link your identity to your vote.
                                            </span>
                                        </div>
                                    </button>
                                    <button
                                        type="button"
                                        onClick={() => setPollType('blind-vote')}
                                        className={`flex items-start gap-4 px-5 py-4 rounded-xl border-2 transition-all text-left cursor-pointer ${
                                            pollType === 'blind-vote'
                                                ? 'border-amber-500 bg-amber-50'
                                                : 'border-stone-200 hover:border-stone-300 bg-white'
                                        }`}
                                    >
                                        <div className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 ${
                                            pollType === 'blind-vote'
                                                ? 'bg-amber-500'
                                                : 'bg-stone-100'
                                        }`}>
                                            <svg className={`w-5 h-5 ${pollType === 'blind-vote' ? 'text-white' : 'text-stone-400'}`} fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
                                                <path strokeLinecap="round" strokeLinejoin="round" d="M3.98 8.223A10.477 10.477 0 001.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88" />
                                            </svg>
                                        </div>
                                        <div>
                                            <span className={`text-sm font-semibold ${pollType === 'blind-vote' ? 'text-amber-800' : 'text-stone-600'}`}>
                                                Blind (Commit-Reveal)
                                            </span>
                                            <span className={`block text-xs font-normal mt-0.5 ${pollType === 'blind-vote' ? 'text-amber-600/70' : 'text-stone-400'}`}>
                                                Votes are hidden until the reveal phase. Address-based registration.
                                            </span>
                                        </div>
                                    </button>
                                </div>
                            </div>

                            {/* Reveal Duration (blind-vote only) */}
                            {pollType === 'blind-vote' && (
                                <div className="flex flex-col gap-2 animate-fade-in-up">
                                    <label htmlFor="reveal-duration" className="text-sm font-semibold text-stone-700">
                                        Reveal Window (seconds)
                                    </label>
                                    <p className="text-xs text-stone-400">
                                        How long voters have to reveal their vote after voting ends. Default: 3600 (1 hour).
                                    </p>
                                    <input
                                        id="reveal-duration"
                                        type="number"
                                        min={60}
                                        value={revealDuration}
                                        onChange={e => setRevealDuration(Number(e.target.value))}
                                        className="w-40 bg-stone-50 border border-stone-200 rounded-xl px-4 py-3 text-sm text-stone-900 placeholder:text-stone-400 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-teal-500 min-h-[44px] transition-all"
                                    />
                                </div>
                            )}

                            {/* Options */}
                            <fieldset className="flex flex-col gap-3">
                                <legend className="text-sm font-semibold text-stone-700 mb-1">
                                    Voting Options <span className="text-stone-400 font-normal">(min 2)</span>
                                </legend>

                                <div className="space-y-2">
                                    {options.map((opt, i) => (
                                        <div key={i} className="flex items-center gap-2">
                                            <label htmlFor={`option-${i}`} className="sr-only">
                                                Option {i + 1}
                                            </label>
                                            <input
                                                id={`option-${i}`}
                                                type="text"
                                                placeholder={`Option ${i + 1}`}
                                                value={opt}
                                                onChange={e => updateOption(i, e.target.value)}
                                                className="flex-1 bg-stone-50 border border-stone-200 rounded-xl px-4 py-2.5 text-sm text-stone-900 placeholder:text-stone-400 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-teal-500 min-h-[44px] transition-all"
                                                required
                                            />
                                            {options.length > 2 && (
                                                <button
                                                    type="button"
                                                    onClick={() => removeOption(i)}
                                                    className="flex items-center justify-center w-11 h-11 bg-rose-50 hover:bg-rose-100 text-rose-600 border border-rose-200 rounded-xl text-sm transition-colors cursor-pointer shrink-0"
                                                    aria-label={`Remove option ${i + 1}`}
                                                >
                                                    <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
                                                        <path strokeLinecap="round" strokeLinejoin="round" d="M6 18 18 6M6 6l12 12" />
                                                    </svg>
                                                </button>
                                            )}
                                        </div>
                                    ))}
                                </div>

                                <button
                                    type="button"
                                    onClick={addOption}
                                    className="self-start inline-flex items-center gap-1.5 px-4 py-2.5 bg-stone-100 hover:bg-stone-200 text-stone-700 border border-stone-200 rounded-xl text-sm font-semibold transition-colors cursor-pointer min-h-[44px]"
                                >
                                    <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
                                        <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                                    </svg>
                                    Add Option
                                </button>
                            </fieldset>

                            {/* Submit */}
                            <button
                                type="submit"
                                disabled={!isConnected || isPending || isConfirming}
                                className="w-full flex items-center justify-center gap-2 px-6 py-3.5 bg-teal-600 hover:bg-teal-700 active:bg-teal-800 text-white rounded-xl text-sm font-semibold transition-colors min-h-[44px] cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                            >
                                {!isConnected
                                    ? 'Connect Wallet to Create'
                                    : isPending
                                        ? 'Submitting...'
                                        : isConfirming
                                            ? 'Confirming...'
                                            : 'Create Poll'}
                            </button>
                        </form>
                    </div>
                )}
            </section>
        </div>
    )
}
