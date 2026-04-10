import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAccount } from 'wagmi'
import { encodeFunctionData } from 'viem'
import { SEMAPHORE_ADDRESS } from '../config'
import { useCreatePoll } from '../hooks/useRegistry'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'
import ZkBlindVotingABI from '../abi/ZkBlindVoting.json'
import {
    ArrowLeft,
    ShieldCheck,
    EyeOff,
    Plus,
    X,
    Check,
    AlertTriangle,
    Loader2,
    Vote,
    FileText,
} from 'lucide-react'

type PollType = 'anon-vote' | 'blind-vote'

/* -- Feedback message component ----------------------------------------- */
function FeedbackMessage({ type, children }: { type: 'success' | 'error' | 'pending'; children: React.ReactNode }) {
    const styles = {
        success: 'bg-emerald-50 border-emerald-200 text-emerald-800 dark:bg-emerald-900/30 dark:border-emerald-700 dark:text-emerald-300',
        error: 'bg-rose-50 border-rose-200 text-rose-800 dark:bg-rose-900/30 dark:border-rose-700 dark:text-rose-300',
        pending: 'bg-amber-50 border-amber-200 text-amber-800 dark:bg-amber-900/30 dark:border-amber-700 dark:text-amber-300',
    }
    const icons = {
        success: <Check className="w-5 h-5 text-emerald-500 shrink-0" />,
        error: <X className="w-5 h-5 text-rose-500 shrink-0" />,
        pending: <Loader2 className="w-5 h-5 text-amber-500 shrink-0 animate-spin" />,
    }
    return (
        <div className={`flex items-center gap-3 px-4 py-3 border rounded-xl text-sm font-semibold ${styles[type]}`} role="alert">
            {icons[type]}
            {children}
        </div>
    )
}

export default function CreatePoll() {
    const { address, isConnected } = useAccount()
    const navigate = useNavigate()
    const [title, setTitle] = useState('')
    const [description, setDescription] = useState('')
    const [options, setOptions] = useState<string[]>(['', ''])
    const [errorMsg, setErrorMsg] = useState('')
    const [pollType, setPollType] = useState<PollType>('anon-vote')
    const [revealDuration, setRevealDuration] = useState(3600)

    const { createPoll, isPending, isConfirming, isSuccess } = useCreatePoll()

    /* -- Form handlers --------------------------------------------------- */
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
            // Navigate home after short delay to show success
            setTimeout(() => navigate('/'), 1500)
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

    const validOptions = options.filter(o => o.trim() !== '')

    return (
        <div className="space-y-8">
            {/* -- Breadcrumb -------------------------------------------------- */}
            <div className="animate-fade-in-up flex items-center gap-3">
                <Link
                    to="/"
                    className="text-teal-600 hover:text-teal-800 dark:text-teal-400 dark:hover:text-teal-300 text-sm font-medium flex items-center gap-1.5 rounded-lg px-2 py-1 hover:bg-teal-50 dark:hover:bg-teal-900/30 transition-colors"
                >
                    <ArrowLeft className="w-4 h-4" />
                    Dashboard
                </Link>
                <span className="text-stone-300 dark:text-stone-600">/</span>
                <span className="text-sm font-semibold text-stone-700 dark:text-stone-300">Create Poll</span>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
                {/* -- Main Form Column ---------------------------------------- */}
                <div className="lg:col-span-2 space-y-6">
                    <div className="animate-fade-in-up">
                        <h1 className="text-2xl font-extrabold tracking-tight text-stone-900 dark:text-stone-100">
                            Create a New Poll
                        </h1>
                        <p className="mt-1 text-sm text-stone-500 dark:text-stone-400">
                            Configure your poll settings, add options, and publish it on-chain.
                        </p>
                    </div>

                    <div className="animate-fade-in-up animate-fade-in-up-1 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6 md:p-8">
                        {/* Feedback messages */}
                        <div className="space-y-3 mb-6">
                            {isPending && <FeedbackMessage type="pending">Submitting transaction...</FeedbackMessage>}
                            {isConfirming && <FeedbackMessage type="pending">Waiting for confirmation...</FeedbackMessage>}
                            {isSuccess && <FeedbackMessage type="success">Poll created successfully! Redirecting...</FeedbackMessage>}
                            {errorMsg && <FeedbackMessage type="error">{errorMsg}</FeedbackMessage>}
                        </div>

                        <form onSubmit={handleCreatePoll} className="space-y-6">
                            {/* Title */}
                            <div className="flex flex-col gap-2">
                                <label htmlFor="poll-title" className="text-sm font-semibold text-stone-700 dark:text-stone-300">
                                    Poll Title <span className="text-rose-500">*</span>
                                </label>
                                <input
                                    id="poll-title"
                                    type="text"
                                    placeholder="e.g., Q3 Board Election"
                                    value={title}
                                    onChange={e => setTitle(e.target.value)}
                                    className="bg-stone-50 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl px-4 py-3 text-sm text-stone-900 dark:text-stone-100 placeholder:text-stone-400 dark:placeholder:text-stone-500 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-teal-500 min-h-[44px] transition-all"
                                    required
                                />
                            </div>

                            {/* Description */}
                            <div className="flex flex-col gap-2">
                                <label htmlFor="poll-description" className="text-sm font-semibold text-stone-700 dark:text-stone-300">
                                    Description <span className="text-stone-400 dark:text-stone-500 font-normal">(optional)</span>
                                </label>
                                <textarea
                                    id="poll-description"
                                    placeholder="What is this poll about?"
                                    value={description}
                                    onChange={e => setDescription(e.target.value)}
                                    rows={3}
                                    className="bg-stone-50 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl px-4 py-3 text-sm text-stone-900 dark:text-stone-100 placeholder:text-stone-400 dark:placeholder:text-stone-500 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-teal-500 resize-y transition-all"
                                />
                            </div>

                            {/* Poll Type Selector */}
                            <div className="flex flex-col gap-2">
                                <span className="text-sm font-semibold text-stone-700 dark:text-stone-300">Poll Type</span>
                                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                    <button
                                        type="button"
                                        onClick={() => setPollType('anon-vote')}
                                        className={`flex items-start gap-4 px-5 py-4 rounded-xl border-2 transition-all text-left cursor-pointer ${
                                            pollType === 'anon-vote'
                                                ? 'border-teal-500 bg-teal-50 dark:bg-teal-900/30 dark:border-teal-600'
                                                : 'border-stone-200 dark:border-stone-700 hover:border-stone-300 dark:hover:border-stone-600 bg-white dark:bg-stone-800'
                                        }`}
                                    >
                                        <div className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 ${
                                            pollType === 'anon-vote'
                                                ? 'bg-teal-600'
                                                : 'bg-stone-100 dark:bg-stone-700'
                                        }`}>
                                            <ShieldCheck className={`w-5 h-5 ${pollType === 'anon-vote' ? 'text-white' : 'text-stone-400 dark:text-stone-500'}`} />
                                        </div>
                                        <div>
                                            <span className={`text-sm font-semibold ${pollType === 'anon-vote' ? 'text-teal-800 dark:text-teal-300' : 'text-stone-600 dark:text-stone-400'}`}>
                                                Anonymous (ZK)
                                            </span>
                                            <span className={`block text-xs font-normal mt-0.5 ${pollType === 'anon-vote' ? 'text-teal-600/70 dark:text-teal-400/70' : 'text-stone-400 dark:text-stone-500'}`}>
                                                Zero-knowledge proofs. No one can link your identity to your vote.
                                            </span>
                                        </div>
                                    </button>
                                    <button
                                        type="button"
                                        onClick={() => setPollType('blind-vote')}
                                        className={`flex items-start gap-4 px-5 py-4 rounded-xl border-2 transition-all text-left cursor-pointer ${
                                            pollType === 'blind-vote'
                                                ? 'border-amber-500 bg-amber-50 dark:bg-amber-900/30 dark:border-amber-600'
                                                : 'border-stone-200 dark:border-stone-700 hover:border-stone-300 dark:hover:border-stone-600 bg-white dark:bg-stone-800'
                                        }`}
                                    >
                                        <div className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 ${
                                            pollType === 'blind-vote'
                                                ? 'bg-amber-500'
                                                : 'bg-stone-100 dark:bg-stone-700'
                                        }`}>
                                            <EyeOff className={`w-5 h-5 ${pollType === 'blind-vote' ? 'text-white' : 'text-stone-400 dark:text-stone-500'}`} />
                                        </div>
                                        <div>
                                            <span className={`text-sm font-semibold ${pollType === 'blind-vote' ? 'text-amber-800 dark:text-amber-300' : 'text-stone-600 dark:text-stone-400'}`}>
                                                Blind (Commit-Reveal)
                                            </span>
                                            <span className={`block text-xs font-normal mt-0.5 ${pollType === 'blind-vote' ? 'text-amber-600/70 dark:text-amber-400/70' : 'text-stone-400 dark:text-stone-500'}`}>
                                                Votes are hidden until the reveal phase. Address-based registration.
                                            </span>
                                        </div>
                                    </button>
                                </div>
                            </div>

                            {/* Reveal Duration (blind-vote only) */}
                            {pollType === 'blind-vote' && (
                                <div className="flex flex-col gap-2 animate-fade-in-up">
                                    <label htmlFor="reveal-duration" className="text-sm font-semibold text-stone-700 dark:text-stone-300">
                                        Reveal Window (seconds)
                                    </label>
                                    <p className="text-xs text-stone-400 dark:text-stone-500">
                                        How long voters have to reveal their vote after voting ends. Default: 3600 (1 hour).
                                    </p>
                                    <input
                                        id="reveal-duration"
                                        type="number"
                                        min={60}
                                        value={revealDuration}
                                        onChange={e => setRevealDuration(Number(e.target.value))}
                                        className="w-40 bg-stone-50 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl px-4 py-3 text-sm text-stone-900 dark:text-stone-100 placeholder:text-stone-400 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-teal-500 min-h-[44px] transition-all"
                                    />
                                </div>
                            )}

                            {/* Options */}
                            <fieldset className="flex flex-col gap-3">
                                <legend className="text-sm font-semibold text-stone-700 dark:text-stone-300 mb-1">
                                    Voting Options <span className="text-stone-400 dark:text-stone-500 font-normal">(min 2)</span>
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
                                                className="flex-1 bg-stone-50 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl px-4 py-2.5 text-sm text-stone-900 dark:text-stone-100 placeholder:text-stone-400 dark:placeholder:text-stone-500 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-teal-500 min-h-[44px] transition-all"
                                                required
                                            />
                                            {options.length > 2 && (
                                                <button
                                                    type="button"
                                                    onClick={() => removeOption(i)}
                                                    className="flex items-center justify-center w-11 h-11 bg-rose-50 dark:bg-rose-900/30 hover:bg-rose-100 dark:hover:bg-rose-900/50 text-rose-600 dark:text-rose-400 border border-rose-200 dark:border-rose-700 rounded-xl text-sm transition-colors cursor-pointer shrink-0"
                                                    aria-label={`Remove option ${i + 1}`}
                                                >
                                                    <X className="w-4 h-4" />
                                                </button>
                                            )}
                                        </div>
                                    ))}
                                </div>

                                <button
                                    type="button"
                                    onClick={addOption}
                                    className="self-start inline-flex items-center gap-1.5 px-4 py-2.5 bg-stone-100 dark:bg-stone-800 hover:bg-stone-200 dark:hover:bg-stone-700 text-stone-700 dark:text-stone-300 border border-stone-200 dark:border-stone-700 rounded-xl text-sm font-semibold transition-colors cursor-pointer min-h-[44px]"
                                >
                                    <Plus className="w-4 h-4" />
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
                </div>

                {/* -- Sidebar: Preview & Info --------------------------------- */}
                <div className="space-y-6">
                    {/* Live Preview */}
                    <div className="animate-fade-in-up animate-fade-in-up-2 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                        <h3 className="text-xs font-bold text-stone-500 dark:text-stone-400 uppercase tracking-widest mb-4 flex items-center gap-2">
                            <FileText className="w-4 h-4" />
                            Preview
                        </h3>
                        <div className="space-y-3">
                            <div>
                                <p className="text-xs text-stone-400 dark:text-stone-500 mb-1">Title</p>
                                <p className="text-sm font-semibold text-stone-900 dark:text-stone-100">
                                    {title || <span className="text-stone-300 dark:text-stone-600 italic">Untitled Poll</span>}
                                </p>
                            </div>
                            {description && (
                                <div>
                                    <p className="text-xs text-stone-400 dark:text-stone-500 mb-1">Description</p>
                                    <p className="text-sm text-stone-600 dark:text-stone-400">{description}</p>
                                </div>
                            )}
                            <div>
                                <p className="text-xs text-stone-400 dark:text-stone-500 mb-1">Type</p>
                                <span className={`text-xs font-semibold px-2.5 py-1 rounded-full uppercase tracking-wide ${
                                    pollType === 'blind-vote'
                                        ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                                        : 'bg-teal-100 text-teal-700 dark:bg-teal-900/30 dark:text-teal-400'
                                }`}>
                                    {pollType === 'blind-vote' ? 'Blind Commit-Reveal' : 'ZK Anonymous'}
                                </span>
                            </div>
                            {validOptions.length > 0 && (
                                <div>
                                    <p className="text-xs text-stone-400 dark:text-stone-500 mb-2">Options ({validOptions.length})</p>
                                    <div className="space-y-1">
                                        {validOptions.map((opt, i) => (
                                            <div key={i} className="flex items-center gap-2 px-3 py-2 bg-stone-50 dark:bg-stone-800 rounded-lg text-sm text-stone-700 dark:text-stone-300 border border-stone-100 dark:border-stone-700">
                                                <span className="w-5 h-5 rounded-full bg-teal-500 text-white text-xs flex items-center justify-center font-bold">{i + 1}</span>
                                                {opt}
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            )}
                        </div>
                    </div>

                    {/* How it works */}
                    <div className="animate-fade-in-up animate-fade-in-up-3 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                        <h3 className="text-xs font-bold text-stone-500 dark:text-stone-400 uppercase tracking-widest mb-4 flex items-center gap-2">
                            <Vote className="w-4 h-4" />
                            How It Works
                        </h3>
                        <div className="space-y-4">
                            {pollType === 'anon-vote' ? (
                                <>
                                    <div className="flex gap-3">
                                        <div className="w-6 h-6 rounded-full bg-teal-100 dark:bg-teal-900/50 flex items-center justify-center flex-shrink-0 text-xs font-bold text-teal-700 dark:text-teal-400">1</div>
                                        <p className="text-xs text-stone-600 dark:text-stone-400">Admin generates invite tokens and distributes them privately to voters.</p>
                                    </div>
                                    <div className="flex gap-3">
                                        <div className="w-6 h-6 rounded-full bg-teal-100 dark:bg-teal-900/50 flex items-center justify-center flex-shrink-0 text-xs font-bold text-teal-700 dark:text-teal-400">2</div>
                                        <p className="text-xs text-stone-600 dark:text-stone-400">Voters load their token and cast a vote using a ZK proof -- no identity revealed.</p>
                                    </div>
                                    <div className="flex gap-3">
                                        <div className="w-6 h-6 rounded-full bg-teal-100 dark:bg-teal-900/50 flex items-center justify-center flex-shrink-0 text-xs font-bold text-teal-700 dark:text-teal-400">3</div>
                                        <p className="text-xs text-stone-600 dark:text-stone-400">Results are tallied on-chain. The smart contract guarantees each token votes once.</p>
                                    </div>
                                </>
                            ) : (
                                <>
                                    <div className="flex gap-3">
                                        <div className="w-6 h-6 rounded-full bg-amber-100 dark:bg-amber-900/50 flex items-center justify-center flex-shrink-0 text-xs font-bold text-amber-700 dark:text-amber-400">1</div>
                                        <p className="text-xs text-stone-600 dark:text-stone-400">Voters register their wallet address during the registration phase.</p>
                                    </div>
                                    <div className="flex gap-3">
                                        <div className="w-6 h-6 rounded-full bg-amber-100 dark:bg-amber-900/50 flex items-center justify-center flex-shrink-0 text-xs font-bold text-amber-700 dark:text-amber-400">2</div>
                                        <p className="text-xs text-stone-600 dark:text-stone-400">During voting, each voter commits a hash of their choice -- nobody can see votes.</p>
                                    </div>
                                    <div className="flex gap-3">
                                        <div className="w-6 h-6 rounded-full bg-amber-100 dark:bg-amber-900/50 flex items-center justify-center flex-shrink-0 text-xs font-bold text-amber-700 dark:text-amber-400">3</div>
                                        <p className="text-xs text-stone-600 dark:text-stone-400">After voting ends, voters reveal their choices. Unrevealed votes are excluded.</p>
                                    </div>
                                </>
                            )}
                        </div>
                    </div>

                    {/* Warning */}
                    {!isConnected && (
                        <div className="animate-fade-in-up animate-fade-in-up-4 bg-amber-50 dark:bg-amber-900/30 border border-amber-200 dark:border-amber-700 rounded-xl px-5 py-4 flex items-start gap-3">
                            <AlertTriangle className="w-5 h-5 text-amber-500 shrink-0 mt-0.5" />
                            <div>
                                <p className="text-sm font-semibold text-amber-800 dark:text-amber-300">Wallet not connected</p>
                                <p className="text-xs text-amber-700/70 dark:text-amber-400/70 mt-0.5">Connect your wallet using the button in the header to create a poll.</p>
                            </div>
                        </div>
                    )}
                </div>
            </div>
        </div>
    )
}
