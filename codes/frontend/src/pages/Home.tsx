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
        <div className={`flex items-center gap-3 px-4 py-3 border rounded-2xl text-sm font-semibold ${styles[type]}`} role="alert">
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


    return (
        <div className="space-y-12">

            {/* ── Hero ────────────────────────────────────────── */}
            <section className="text-center py-12 md:py-16">
                <h1 className="text-4xl md:text-5xl font-extrabold tracking-tight text-slate-900 leading-tight">
                    Anonymous Voting
                </h1>
                <p className="mt-4 text-lg text-slate-500 max-w-xl mx-auto font-normal leading-relaxed">
                    Create and participate in provably fair polls. Your identity stays private.
                </p>
                <button
                    onClick={scrollToForm}
                    className="mt-8 inline-flex items-center gap-2 px-6 py-3 bg-slate-900 hover:bg-slate-800 active:bg-slate-950 text-white rounded-xl text-sm font-semibold shadow-sm transition-colors min-h-[44px] cursor-pointer"
                >
                    {/* Plus icon */}
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                    </svg>
                    Create Poll
                </button>
            </section>


            {/* ── Poll grid ───────────────────────────────────── */}
            <section>
                <h2 className="text-xl font-extrabold text-slate-900 mb-6">Active Polls</h2>

                {pollsArray.length === 0 ? (
                    /* Empty state */
                    <div className="flex flex-col items-center justify-center py-16 px-8 bg-white border border-slate-200 rounded-2xl shadow-sm">
                        {/* Ballot box icon */}
                        <svg className="w-16 h-16 text-slate-300 mb-6" fill="none" stroke="currentColor" strokeWidth={1} viewBox="0 0 24 24" aria-hidden="true">
                            <path strokeLinecap="round" strokeLinejoin="round" d="M9 12h3.75M9 15h3.75M9 18h3.75m3 .75H18a2.25 2.25 0 0 0 2.25-2.25V6.108c0-1.135-.845-2.098-1.976-2.192a48.424 48.424 0 0 0-1.123-.08m-5.801 0c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 0 0 .75-.75 2.25 2.25 0 0 0-.1-.664m-5.8 0A2.251 2.251 0 0 1 13.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m0 0H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V9.375c0-.621-.504-1.125-1.125-1.125H8.25Z" />
                        </svg>
                        <h3 className="text-lg font-extrabold text-slate-900 mb-2">No polls yet</h3>
                        <p className="text-sm text-slate-500 mb-6 text-center max-w-sm">
                            Be the first to create a poll. It only takes a few seconds and your voters stay completely anonymous.
                        </p>
                        <button
                            onClick={scrollToForm}
                            className="inline-flex items-center gap-2 px-6 py-3 bg-slate-900 hover:bg-slate-800 active:bg-slate-950 text-white rounded-xl text-sm font-semibold shadow-sm transition-colors min-h-[44px] cursor-pointer"
                        >
                            Create Your First Poll
                        </button>
                    </div>
                ) : (
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                        {[...pollsArray].reverse().map((poll: PollInfo) => (
                            <Link
                                key={poll.pollAddress}
                                to={`/poll/${poll.pollAddress}`}
                                className="group flex flex-col bg-white border border-slate-200 rounded-2xl shadow-sm hover:shadow-md hover:border-blue-300 transition-all p-6 no-underline"
                            >
                                {/* Top: badges */}
                                <div className="flex items-center gap-2 mb-3">
                                    <span className="text-xs font-semibold px-2.5 py-1 bg-slate-100 text-slate-600 rounded-full uppercase tracking-wide">
                                        {poll.moduleType}
                                    </span>
                                </div>

                                {/* Title + description */}
                                <h3 className="text-base font-extrabold text-slate-900 group-hover:text-blue-600 transition-colors leading-snug">
                                    {poll.title}
                                </h3>
                                {poll.description && (
                                    <p className="text-sm text-slate-500 mt-1 line-clamp-2 font-normal">
                                        {poll.description}
                                    </p>
                                )}

                                {/* Footer */}
                                <div className="mt-auto pt-4 border-t border-slate-100 flex justify-between items-center">
                                    <span className="text-xs font-mono text-slate-400 bg-slate-50 px-2 py-1 rounded-md border border-slate-100">
                                        {poll.pollAddress.slice(0, 6)}...{poll.pollAddress.slice(-4)}
                                    </span>
                                    <span className="text-blue-600 text-sm font-semibold group-hover:translate-x-1 transition-transform inline-flex items-center gap-1">
                                        View Poll
                                        <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true">
                                            <path strokeLinecap="round" strokeLinejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
                                        </svg>
                                    </span>
                                </div>
                            </Link>
                        ))}
                    </div>
                )}
            </section>


            {/* ── Create Poll form (collapsible) ──────────────── */}
            <section ref={formRef}>
                <button
                    onClick={() => setFormOpen(prev => !prev)}
                    className="flex items-center gap-2 text-lg font-extrabold text-slate-900 mb-4 cursor-pointer bg-transparent border-none p-0"
                    aria-expanded={formOpen}
                    aria-controls="create-poll-form"
                >
                    {/* Chevron */}
                    <svg
                        className={`w-5 h-5 text-slate-400 transition-transform ${formOpen ? 'rotate-90' : ''}`}
                        fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden="true"
                    >
                        <path strokeLinecap="round" strokeLinejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
                    </svg>
                    Create a New Poll
                </button>

                {formOpen && (
                    <div
                        id="create-poll-form"
                        className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6 md:p-8"
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
                                <label htmlFor="poll-title" className="text-sm font-semibold text-slate-700">
                                    Poll Title <span className="text-rose-500">*</span>
                                </label>
                                <input
                                    id="poll-title"
                                    type="text"
                                    placeholder="e.g., Q3 Board Election"
                                    value={title}
                                    onChange={e => setTitle(e.target.value)}
                                    className="bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 min-h-[44px]"
                                    required
                                />
                            </div>

                            {/* Description */}
                            <div className="flex flex-col gap-2">
                                <label htmlFor="poll-description" className="text-sm font-semibold text-slate-700">
                                    Description <span className="text-slate-400 font-normal">(optional)</span>
                                </label>
                                <textarea
                                    id="poll-description"
                                    placeholder="What is this poll about?"
                                    value={description}
                                    onChange={e => setDescription(e.target.value)}
                                    rows={3}
                                    className="bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 resize-y"
                                />
                            </div>

                            {/* Poll Type Selector */}
                            <div className="flex flex-col gap-2">
                                <span className="text-sm font-semibold text-slate-700">Poll Type</span>
                                <div className="grid grid-cols-2 gap-3">
                                    <button
                                        type="button"
                                        onClick={() => setPollType('anon-vote')}
                                        className={`flex flex-col items-start gap-1 px-4 py-3 rounded-xl border-2 transition-all text-left cursor-pointer ${
                                            pollType === 'anon-vote'
                                                ? 'border-blue-600 bg-blue-50 text-blue-800'
                                                : 'border-slate-200 hover:border-slate-300 text-slate-600'
                                        }`}
                                    >
                                        <span className="text-sm font-semibold">Anonymous (ZK)</span>
                                        <span className="text-xs font-normal opacity-75">
                                            Zero-knowledge proofs. No one can link your identity to your vote.
                                        </span>
                                    </button>
                                    <button
                                        type="button"
                                        onClick={() => setPollType('blind-vote')}
                                        className={`flex flex-col items-start gap-1 px-4 py-3 rounded-xl border-2 transition-all text-left cursor-pointer ${
                                            pollType === 'blind-vote'
                                                ? 'border-blue-600 bg-blue-50 text-blue-800'
                                                : 'border-slate-200 hover:border-slate-300 text-slate-600'
                                        }`}
                                    >
                                        <span className="text-sm font-semibold">Blind (Commit-Reveal)</span>
                                        <span className="text-xs font-normal opacity-75">
                                            Votes are hidden until the reveal phase. Address-based registration.
                                        </span>
                                    </button>
                                </div>
                            </div>

                            {/* Reveal Duration (blind-vote only) */}
                            {pollType === 'blind-vote' && (
                                <div className="flex flex-col gap-2">
                                    <label htmlFor="reveal-duration" className="text-sm font-semibold text-slate-700">
                                        Reveal Window (seconds)
                                    </label>
                                    <p className="text-xs text-slate-400">
                                        How long voters have to reveal their vote after voting ends. Default: 3600 (1 hour).
                                    </p>
                                    <input
                                        id="reveal-duration"
                                        type="number"
                                        min={60}
                                        value={revealDuration}
                                        onChange={e => setRevealDuration(Number(e.target.value))}
                                        className="w-40 bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 min-h-[44px]"
                                    />
                                </div>
                            )}

                            {/* Options */}
                            <fieldset className="flex flex-col gap-3">
                                <legend className="text-sm font-semibold text-slate-700 mb-1">
                                    Voting Options <span className="text-slate-400 font-normal">(min 2)</span>
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
                                                className="flex-1 bg-slate-50 border border-slate-200 rounded-xl px-4 py-2.5 text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 min-h-[44px]"
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
                                    className="self-start inline-flex items-center gap-1.5 px-4 py-2.5 bg-slate-100 hover:bg-slate-200 text-slate-700 border border-slate-200 rounded-xl text-sm font-semibold transition-colors cursor-pointer min-h-[44px]"
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
                                className="w-full flex items-center justify-center gap-2 px-6 py-3 bg-slate-900 hover:bg-slate-800 active:bg-slate-950 text-white rounded-xl text-sm font-semibold shadow-sm transition-colors min-h-[44px] cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
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
