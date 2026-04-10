import { useState, useEffect, useTransition, Fragment } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useAccount, useChainId } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { keccak256, encodePacked } from 'viem'
import { usePollState, usePollOptions, usePollResults, usePollOwner, useParticipantCount } from '../hooks/usePoll'
import {
    useBlindPollRevealDeadline,
    useBlindPollFinalized,
    useHasVoted,
    useHasRevealed,
    useBlindPollWrite,
} from '../hooks/useBlindPoll'
import ZkBlindVotingABI from '../abi/ZkBlindVoting.json'

/* ---- Error Map -------------------------------------------------------- */

const ERROR_MAP: Record<string, string> = {
    'Not in voting phase': "Voting hasn't started yet. Wait for the poll admin to open voting.",
    'Already committed': "You've already committed a vote in this poll.",
    'Not registered': 'You are not registered for this poll. Register first.',
    'Invalid option index': 'Invalid vote selection. Please try again.',
    'Not owner': 'Only the poll creator can perform this action.',
    'Not in registration phase': 'Registration is closed. Voting has already begun.',
    'Need at least 2 options': 'A poll needs at least 2 options before voting can start.',
    'Already registered': 'You are already registered for this poll.',
    'Not in ended phase': 'The poll has not ended yet.',
    'Reveal deadline passed': 'The reveal window has closed.',
    'No commit found': 'You did not commit a vote.',
    'Already revealed': 'You have already revealed your vote.',
    'Hash mismatch': 'Your reveal data does not match your commitment. Did you use the correct browser?',
    'Reveal deadline not passed': 'The reveal window has not closed yet.',
    'Already finalized': 'Results have already been finalized.',
    'Need at least 1 voter': 'At least one voter must be registered before starting.',
}

function friendlyError(err: unknown): string {
    const msg = (err as { shortMessage?: string; message?: string })?.shortMessage
        ?? (err as { message?: string })?.message
        ?? String(err)
    for (const [key, friendly] of Object.entries(ERROR_MAP)) {
        if (msg.includes(key)) return friendly
    }
    return 'Something went wrong. Please check your wallet and try again.'
}

/* ---- State Progression Bar -------------------------------------------- */

function StateProgress({ current }: { current: number }) {
    const steps = ['Registration', 'Voting', 'Reveal / Ended']
    return (
        <div className="flex items-center gap-1">
            {steps.map((step, i) => (
                <Fragment key={i}>
                    {i > 0 && (
                        <div className={`flex-1 h-0.5 rounded-full transition-all duration-500 ${
                            i <= current ? 'bg-teal-500' : 'bg-stone-200'
                        }`} />
                    )}
                    <div className="flex flex-col items-center gap-1.5">
                        <div className="relative">
                            <div
                                className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold transition-all duration-300
                                    ${i < current
                                        ? 'bg-teal-600 text-white'
                                        : i === current
                                            ? 'bg-white border-2 border-teal-500 text-teal-600'
                                            : 'bg-stone-200 text-stone-400'
                                    }`}
                            >
                                {i < current ? '\u2713' : i + 1}
                            </div>
                            {i === current && (
                                <span className="absolute inset-0 rounded-full animate-ping bg-teal-400 opacity-15" />
                            )}
                        </div>
                        <span className={`text-xs font-medium ${i === current ? 'text-teal-700 font-semibold' : i < current ? 'text-teal-600' : 'text-stone-400'}`}>
                            {step}
                        </span>
                    </div>
                </Fragment>
            ))}
        </div>
    )
}

/* ---- Countdown component ---------------------------------------------- */

function Countdown({ deadline }: { deadline: number }) {
    const [now, setNow] = useState(Math.floor(Date.now() / 1000))

    useEffect(() => {
        const interval = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000)
        return () => clearInterval(interval)
    }, [])

    const remaining = deadline - now
    if (remaining <= 0) return <span className="text-rose-600 font-bold">Deadline passed</span>

    const hrs = Math.floor(remaining / 3600)
    const mins = Math.floor((remaining % 3600) / 60)
    const secs = remaining % 60

    return (
        <span className="font-mono font-bold text-2xl tabular-nums text-white">
            {hrs.toString().padStart(2, '0')}:{mins.toString().padStart(2, '0')}:{secs.toString().padStart(2, '0')}
        </span>
    )
}

/* ---- Option Colors (solid, no gradients) ------------------------------ */

const OPTION_BAR_COLORS = [
    'bg-teal-500',
    'bg-indigo-500',
    'bg-amber-500',
    'bg-rose-500',
    'bg-violet-500',
    'bg-cyan-500',
    'bg-orange-500',
    'bg-emerald-500',
    'bg-pink-500',
    'bg-sky-500',
]

/* ---- Main Component --------------------------------------------------- */

export default function BlindPoll() {
    const { address: pollAddress } = useParams()
    const { address, isConnected } = useAccount()
    const chainId = useChainId()

    const isWrongNetwork = isConnected && chainId !== hardhat.id && chainId !== localhost.id
    const typedPollAddr = pollAddress as `0x${string}`
    const typedAddress = address as `0x${string}` | undefined

    const [selectedOption, setSelectedOption] = useState<number>(0)
    const [statusMsg, setStatusMsg] = useState('')
    const [statusType, setStatusType] = useState<'info' | 'success' | 'error'>('info')
    const [newOptionLabel, setNewOptionLabel] = useState('')
    const [isPending, startTransition] = useTransition()

    // IZkPoll reads
    const { data: pollOwner } = usePollOwner(typedPollAddr)
    const { data: pollState } = usePollState(typedPollAddr)
    const { data: optionsData, refetch: refetchOptions } = usePollOptions(typedPollAddr)
    const { data: resultsData } = usePollResults(typedPollAddr)
    const { data: participantCountData } = useParticipantCount(typedPollAddr)

    // Blind-specific reads
    const { data: revealDeadlineData } = useBlindPollRevealDeadline(typedPollAddr)
    const { data: isFinalized } = useBlindPollFinalized(typedPollAddr)
    const { data: hasVotedData } = useHasVoted(typedPollAddr, typedAddress)
    const { data: hasRevealedData } = useHasRevealed(typedPollAddr, typedAddress)

    // Write hook
    const { mutateAsync: writeContractAsync, isConfirming: isTxConfirming, isSuccess: isTxSuccess } = useBlindPollWrite()

    const pollOptions = (optionsData as string[]) || []
    const voteCounts = (resultsData as bigint[])?.map(Number) || []
    const totalVotes = voteCounts.reduce((s, c) => s + c, 0)

    const currentPollState = pollState !== undefined ? Number(pollState) : -1
    const isAdmin = pollOwner === address
    const revealDeadline = revealDeadlineData !== undefined ? Number(revealDeadlineData) : 0
    const participantCount = participantCountData !== undefined ? Number(participantCountData) : 0

    const hasCommitted = hasVotedData === true
    const hasRevealed = hasRevealedData === true
    const finalized = isFinalized === true

    // Check localStorage for saved commit data
    const [hasSavedCommit, setHasSavedCommit] = useState(false)
    useEffect(() => {
        const saved = localStorage.getItem(`blind-vote-${pollAddress}`)
        setHasSavedCommit(saved !== null)
    }, [pollAddress, hasCommitted])

    /* ---- Status helper ------------------------------------------------ */
    function setStatus(msg: string, type: 'info' | 'success' | 'error' = 'info') {
        setStatusMsg(msg)
        setStatusType(type)
    }

    /* ---- Voter: Register ---------------------------------------------- */
    const handleRegister = async () => {
        if (!pollAddress) return
        try {
            setStatus('Registering as voter...')
            await writeContractAsync({
                address: typedPollAddr,
                abi: ZkBlindVotingABI.abi,
                functionName: 'register',
            })
            setStatus('Registered successfully! You can vote once voting starts.', 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    /* ---- Voter: Commit Vote ------------------------------------------- */
    const handleCommitVote = async () => {
        if (!pollAddress) return
        try {
            setStatus('Generating commitment...')

            // Generate random salt (32 bytes)
            const saltBytes = new Uint8Array(32)
            crypto.getRandomValues(saltBytes)
            const salt = '0x' + Array.from(saltBytes).map(b => b.toString(16).padStart(2, '0')).join('') as `0x${string}`

            // Compute commit hash: keccak256(abi.encodePacked(optionIndex, salt))
            const commitHash = keccak256(
                encodePacked(['uint256', 'bytes32'], [BigInt(selectedOption), salt])
            )

            // Save to localStorage BEFORE submitting (so we don't lose it)
            localStorage.setItem(`blind-vote-${pollAddress}`, JSON.stringify({
                optionIndex: selectedOption,
                salt: salt,
            }))

            setStatus('Submitting vote commitment...')
            await writeContractAsync({
                address: typedPollAddr,
                abi: ZkBlindVotingABI.abi,
                functionName: 'commitVote',
                args: [commitHash],
            })

            setHasSavedCommit(true)
            setStatus('Vote committed! Your choice is sealed until the reveal phase.', 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    /* ---- Voter: Reveal Vote ------------------------------------------- */
    const handleRevealVote = async () => {
        if (!pollAddress) return
        try {
            const saved = localStorage.getItem(`blind-vote-${pollAddress}`)
            if (!saved) {
                setStatus('No saved commitment found in this browser. Did you commit from a different device?', 'error')
                return
            }
            const { optionIndex, salt } = JSON.parse(saved) as { optionIndex: number; salt: string }

            setStatus('Revealing your vote...')
            await writeContractAsync({
                address: typedPollAddr,
                abi: ZkBlindVotingABI.abi,
                functionName: 'revealVote',
                args: [BigInt(optionIndex), salt as `0x${string}`],
            })

            setStatus('Vote revealed successfully! Your choice is now counted.', 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    /* ---- Admin actions ------------------------------------------------ */
    const handleStartVoting = async () => {
        if (!pollAddress) return
        try {
            setStatus('Starting voting phase...')
            await writeContractAsync({ address: typedPollAddr, abi: ZkBlindVotingABI.abi, functionName: 'startVoting' })
            setStatus('Voting phase started!', 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    const handleEndVoting = async () => {
        if (!pollAddress) return
        try {
            setStatus('Ending voting phase...')
            await writeContractAsync({ address: typedPollAddr, abi: ZkBlindVotingABI.abi, functionName: 'endVoting' })
            setStatus('Voting ended. Reveal window is now open.', 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    const handleFinalizeResults = async () => {
        if (!pollAddress) return
        try {
            setStatus('Finalizing results...')
            await writeContractAsync({ address: typedPollAddr, abi: ZkBlindVotingABI.abi, functionName: 'finalizeResults' })
            setStatus('Results finalized!', 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    const handleAddOption = async () => {
        if (!pollAddress || !newOptionLabel.trim()) return
        try {
            setStatus('Adding option on-chain...')
            await writeContractAsync({
                address: typedPollAddr,
                abi: ZkBlindVotingABI.abi,
                functionName: 'addOption',
                args: [newOptionLabel.trim()],
            })
            setNewOptionLabel('')
            refetchOptions()
            setStatus('Option added successfully!', 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    /* ---- Button helpers ----------------------------------------------- */
    const voteDisabled = !isConnected || isWrongNetwork || isTxConfirming || isPending

    /* ---- Render ------------------------------------------------------- */
    return (
        <div className="space-y-6">
            {/* ---- Header ------------------------------------------------ */}
            <div className="flex items-center justify-between animate-fade-in-up">
                <Link
                    to="/"
                    className="text-teal-600 hover:text-teal-800 text-sm font-medium flex items-center gap-1.5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2 rounded-lg px-2 py-1 hover:bg-teal-50 transition-colors"
                >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" />
                    </svg>
                    Back to Polls
                </Link>
                <div className="flex items-center gap-2">
                    <span className="text-xs font-semibold px-2.5 py-1 bg-amber-100 text-amber-700 rounded-full uppercase tracking-wide">
                        Blind Vote
                    </span>
                    <span className="text-xs font-mono text-stone-400 bg-stone-50 px-2 py-1 rounded-lg border border-stone-200">
                        {pollAddress?.slice(0, 6)}...{pollAddress?.slice(-4)}
                    </span>
                </div>
            </div>

            {/* ---- State Progression ------------------------------------- */}
            {currentPollState >= 0 && (
                <div className="animate-fade-in-up animate-fade-in-up-1 bg-white border border-stone-200 rounded-xl shadow-sm px-6 py-5">
                    <StateProgress current={currentPollState} />
                </div>
            )}

            {/* ---- Trust Signal ------------------------------------------ */}
            <div className="animate-fade-in-up animate-fade-in-up-2 bg-teal-50 border border-teal-200 rounded-xl px-5 py-4 flex items-center gap-3">
                <svg viewBox="0 0 32 32" fill="none" stroke="currentColor" strokeWidth="1.5" className="w-6 h-6 text-teal-600 flex-shrink-0">
                    <rect x="8" y="14" width="16" height="12" rx="2" />
                    <path d="M12 14V10a4 4 0 0 1 8 0v4" />
                    <circle cx="16" cy="21" r="1.5" fill="currentColor" />
                </svg>
                <p className="text-sm text-teal-800 font-medium">
                    Your vote is sealed with a cryptographic commitment. No one can see your choice until the reveal phase.
                </p>
            </div>

            {/* ---- Status Banner ----------------------------------------- */}
            {statusMsg && (
                <div
                    className={`px-5 py-4 rounded-xl flex items-start gap-3 text-sm font-medium border ${
                        statusType === 'success'
                            ? 'bg-emerald-50 border-emerald-200 text-emerald-800'
                            : statusType === 'error'
                                ? 'bg-rose-50 border-rose-200 text-rose-800'
                                : 'bg-stone-50 border-stone-200 text-stone-800'
                    }`}
                    role="status"
                    aria-live="polite"
                >
                    <div className={`mt-0.5 h-2.5 w-2.5 rounded-full flex-shrink-0 ${
                        statusType === 'success'
                            ? 'bg-emerald-500'
                            : statusType === 'error'
                                ? 'bg-rose-500'
                                : 'bg-stone-400 animate-pulse'
                    }`} />
                    <p>{statusMsg}</p>
                </div>
            )}

            {isTxConfirming && !statusMsg && (
                <p className="text-amber-600 text-sm font-medium animate-pulse px-1">Transaction pending...</p>
            )}
            {isTxSuccess && !statusMsg && (
                <p className="text-emerald-600 text-sm font-medium px-1">Transaction confirmed!</p>
            )}

            {/* ---- Main Grid --------------------------------------------- */}
            <main className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* ======== LEFT COLUMN: Voter Panel ======== */}
                <section className="space-y-6">
                    {/* ---- Registration Phase ----------------------------- */}
                    {currentPollState === 0 && (
                        <div className="animate-fade-in-up animate-fade-in-up-3 bg-white border border-stone-200 rounded-xl shadow-sm p-6">
                            <h2 className="text-base font-semibold text-stone-900 mb-1">Register to Vote</h2>
                            <p className="text-xs text-stone-500 mb-4">
                                Connect your wallet and register. Your address will be added to the voter list.
                            </p>
                            <div className="flex items-center gap-3">
                                <span className="text-sm text-stone-600 font-mono tabular-nums">
                                    <span className="text-lg font-bold text-teal-600">{participantCount}</span>{' '}
                                    voter{participantCount !== 1 ? 's' : ''} registered
                                </span>
                            </div>
                            <button
                                onClick={() => startTransition(async () => await handleRegister())}
                                disabled={voteDisabled}
                                className="mt-4 w-full py-3 bg-teal-600 hover:bg-teal-700 active:bg-teal-800 text-white transition-colors rounded-xl text-sm font-bold disabled:opacity-50 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
                            >
                                {!isConnected ? 'Connect Wallet First' : isPending || isTxConfirming ? 'Processing...' : 'Register to Vote'}
                            </button>
                        </div>
                    )}

                    {/* ---- Voting Phase: Commit ------------------------------ */}
                    {currentPollState === 1 && !hasCommitted && (
                        <div className="animate-fade-in-up bg-white border border-stone-200 rounded-xl shadow-sm p-6">
                            <h2 className="text-base font-semibold text-stone-900 mb-4">Cast Your Vote</h2>

                            {pollOptions.length === 0 ? (
                                <p className="text-sm text-stone-400">No options available.</p>
                            ) : (
                                <fieldset>
                                    <legend className="sr-only">Select a voting option</legend>
                                    <div className="flex flex-col gap-2 mb-6">
                                        {pollOptions.map((opt, i) => (
                                            <button
                                                key={i}
                                                onClick={() => setSelectedOption(i)}
                                                role="radio"
                                                aria-checked={selectedOption === i}
                                                className={`w-full min-h-[48px] py-3 px-4 rounded-xl border transition-all duration-200 text-left flex items-center gap-3 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2 ${
                                                    selectedOption === i
                                                        ? 'border-teal-500 bg-teal-50 text-teal-800 font-semibold'
                                                        : 'border-stone-200 hover:border-teal-300 text-stone-700'
                                                }`}
                                            >
                                                <span className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-all ${
                                                    selectedOption === i
                                                        ? 'border-teal-600 bg-teal-600'
                                                        : 'border-stone-300'
                                                }`}>
                                                    {selectedOption === i && (
                                                        <svg className="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
                                                        </svg>
                                                    )}
                                                </span>
                                                <span>{opt}</span>
                                            </button>
                                        ))}
                                    </div>

                                    <button
                                        onClick={() => startTransition(async () => await handleCommitVote())}
                                        disabled={voteDisabled}
                                        className="w-full py-4 bg-teal-600 hover:bg-teal-700 active:bg-teal-800 text-white transition-colors rounded-xl text-base font-bold disabled:opacity-50 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
                                    >
                                        {!isConnected ? 'Connect Wallet First' : isPending || isTxConfirming ? 'Processing...' : 'Commit Vote'}
                                    </button>
                                </fieldset>
                            )}
                        </div>
                    )}

                    {/* ---- Voting Phase: Already Committed ------------------- */}
                    {currentPollState === 1 && hasCommitted && (
                        <div className="animate-fade-in-up bg-white border border-emerald-200 rounded-xl shadow-sm p-6">
                            <div className="flex items-center gap-3 mb-3">
                                <div className="w-10 h-10 rounded-xl bg-emerald-100 flex items-center justify-center flex-shrink-0">
                                    <svg className="w-5 h-5 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                                    </svg>
                                </div>
                                <div>
                                    <p className="text-sm font-semibold text-emerald-800">Vote Committed</p>
                                    <p className="text-xs text-stone-500 mt-0.5">
                                        Your vote is sealed. You will need to reveal it after voting ends.
                                    </p>
                                </div>
                            </div>
                            {hasSavedCommit && (
                                <div className="bg-emerald-50 border border-emerald-100 rounded-xl px-3 py-2 mt-2">
                                    <p className="text-xs text-emerald-700 font-medium">
                                        Reveal data is saved in this browser. Do not clear your browser data before revealing.
                                    </p>
                                </div>
                            )}
                        </div>
                    )}

                    {/* ---- Ended Phase: Reveal Window ----------------------- */}
                    {currentPollState === 2 && !finalized && (
                        <div className="animate-fade-in-up bg-white border border-stone-200 rounded-xl shadow-sm p-6">
                            <h2 className="text-base font-semibold text-stone-900 mb-1">Reveal Phase</h2>
                            <p className="text-xs text-stone-500 mb-4">
                                Voting has ended. Reveal your vote before the deadline to have it counted.
                            </p>

                            {revealDeadline > 0 && (
                                <div className="flex flex-col items-center gap-2 mb-5 px-4 py-4 bg-stone-900 rounded-xl">
                                    <div className="flex items-center gap-2">
                                        <svg className="w-5 h-5 text-stone-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                                        </svg>
                                        <span className="text-xs font-semibold text-stone-400 uppercase tracking-wider">Reveal Deadline</span>
                                    </div>
                                    <Countdown deadline={revealDeadline} />
                                </div>
                            )}

                            {hasCommitted && !hasRevealed ? (
                                <button
                                    onClick={() => startTransition(async () => await handleRevealVote())}
                                    disabled={voteDisabled}
                                    className="w-full py-4 bg-amber-500 hover:bg-amber-600 active:bg-amber-700 text-white transition-colors rounded-xl text-base font-bold disabled:opacity-50 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-500 focus-visible:ring-offset-2"
                                >
                                    {isPending || isTxConfirming ? 'Processing...' : 'Reveal Vote'}
                                </button>
                            ) : hasRevealed ? (
                                <div className="flex items-center gap-2 px-4 py-3 bg-teal-50 border border-teal-200 text-teal-700 rounded-xl text-sm font-medium">
                                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                                    </svg>
                                    Your vote has been revealed and counted.
                                </div>
                            ) : (
                                <p className="text-sm text-stone-500">You did not commit a vote in this poll.</p>
                            )}
                        </div>
                    )}

                    {/* ---- Finalized State ---------------------------------- */}
                    {currentPollState === 2 && finalized && (
                        <div className="animate-fade-in-up bg-white border border-stone-200 rounded-xl shadow-sm p-6">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-xl bg-stone-100 flex items-center justify-center flex-shrink-0">
                                    <svg className="w-5 h-5 text-stone-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                                    </svg>
                                </div>
                                <div>
                                    <p className="text-sm font-semibold text-stone-700">Results Finalized</p>
                                    <p className="text-xs text-stone-500 mt-0.5">
                                        The reveal window has closed and results are final. Unrevealed votes were excluded.
                                    </p>
                                </div>
                            </div>
                        </div>
                    )}

                    {/* ---- Not connected info -------------------------------- */}
                    {!isConnected && currentPollState >= 0 && (
                        <div className="animate-fade-in-up bg-white border border-stone-200 rounded-xl shadow-sm p-6">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-xl bg-stone-100 flex items-center justify-center flex-shrink-0">
                                    <svg className="w-5 h-5 text-stone-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z" />
                                    </svg>
                                </div>
                                <div>
                                    <p className="text-sm font-semibold text-stone-700">Wallet Not Connected</p>
                                    <p className="text-xs text-stone-500 mt-0.5">
                                        Connect your wallet to register, vote, or reveal.
                                    </p>
                                </div>
                            </div>
                        </div>
                    )}
                </section>

                {/* ======== RIGHT COLUMN: Info Panel ======== */}
                <section className="space-y-6">
                    {/* ---- Live Results Card ------------------------------ */}
                    <div className="animate-fade-in-up animate-fade-in-up-4 bg-white border border-stone-200 rounded-xl shadow-sm p-6">
                        <div className="flex items-center justify-between mb-5">
                            <h2 className="text-base font-semibold text-stone-900">
                                {finalized ? 'Final Results' : currentPollState === 2 ? 'Results (updating as reveals come in)' : 'Options'}
                            </h2>
                            {totalVotes > 0 && (
                                <span className="text-xs font-semibold text-stone-500 bg-stone-100 px-3 py-1 rounded-full font-mono tabular-nums">
                                    {totalVotes} revealed
                                </span>
                            )}
                        </div>

                        {pollOptions.length > 0 ? (
                            <div className="space-y-5">
                                {pollOptions.map((opt, i) => {
                                    const count = voteCounts[i] || 0
                                    const pct = totalVotes > 0 ? (count / totalVotes) * 100 : 0
                                    const barColor = OPTION_BAR_COLORS[i % OPTION_BAR_COLORS.length]
                                    return (
                                        <div key={i}>
                                            <div className="flex justify-between items-baseline mb-2">
                                                <span className="text-sm font-medium text-stone-700">{opt}</span>
                                                <div className="flex items-baseline gap-2">
                                                    <span className="text-xs text-stone-400 font-mono tabular-nums">
                                                        {totalVotes > 0 ? `${pct.toFixed(1)}%` : '--'}
                                                    </span>
                                                    <span className="text-xl font-bold text-stone-900 font-mono tabular-nums">{count}</span>
                                                </div>
                                            </div>
                                            <div className="w-full bg-stone-100 rounded-full h-2.5 overflow-hidden">
                                                <div
                                                    className={`${barColor} h-2.5 rounded-full transition-all duration-700 ease-out`}
                                                    style={{ width: `${pct}%` }}
                                                />
                                            </div>
                                        </div>
                                    )
                                })}
                            </div>
                        ) : (
                            <div className="text-center py-8">
                                <svg className="w-8 h-8 text-stone-300 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                                </svg>
                                <p className="text-sm text-stone-400">No options configured yet.</p>
                            </div>
                        )}

                        {/* Participant info */}
                        <div className="mt-4 pt-4 border-t border-stone-100 flex items-center gap-2 text-xs text-stone-400">
                            <span className="font-mono tabular-nums text-sm font-bold text-teal-600">{participantCount}</span>
                            registered voter{participantCount !== 1 ? 's' : ''}
                        </div>
                    </div>

                    {/* ---- Admin Panel ------------------------------------ */}
                    {isAdmin && (
                        <div className="animate-fade-in-up animate-fade-in-up-5 bg-white border-2 border-amber-200 rounded-xl shadow-sm p-6">
                            <h2 className="text-xs font-bold text-amber-600 uppercase tracking-widest mb-4 flex items-center gap-2">
                                <div className="w-6 h-6 rounded-lg bg-amber-100 flex items-center justify-center">
                                    <svg className="w-3.5 h-3.5 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                                    </svg>
                                </div>
                                Admin Panel
                            </h2>

                            {/* Poll Lifecycle Buttons */}
                            <div className="flex flex-col sm:flex-row gap-2 mb-6">
                                <button
                                    onClick={handleStartVoting}
                                    disabled={currentPollState !== 0 || !isConnected || isWrongNetwork}
                                    className="flex-1 py-2.5 bg-amber-50 hover:bg-amber-100 text-amber-700 transition-all border border-amber-200 rounded-xl text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
                                >
                                    Start Voting
                                </button>
                                <button
                                    onClick={handleEndVoting}
                                    disabled={currentPollState !== 1 || !isConnected || isWrongNetwork}
                                    className="flex-1 py-2.5 bg-amber-50 hover:bg-amber-100 text-amber-700 transition-all border border-amber-200 rounded-xl text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
                                >
                                    End Voting
                                </button>
                                <button
                                    onClick={handleFinalizeResults}
                                    disabled={currentPollState !== 2 || finalized || !isConnected || isWrongNetwork}
                                    className="flex-1 py-2.5 bg-amber-50 hover:bg-amber-100 text-amber-700 transition-all border border-amber-200 rounded-xl text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
                                >
                                    Finalize Results
                                </button>
                            </div>

                            {/* Manage Options (Registration only) */}
                            {currentPollState === 0 && (
                                <div className="border-t border-amber-100 pt-4">
                                    <h3 className="text-sm font-semibold text-amber-700 mb-3">Manage Options</h3>
                                    {pollOptions.length > 0 && (
                                        <div className="mb-3 space-y-1">
                                            {pollOptions.map((opt, i) => (
                                                <div key={i} className="flex items-center gap-2 px-3 py-2 bg-amber-50 rounded-lg text-sm text-amber-800 border border-amber-100">
                                                    <span className="w-5 h-5 rounded-full bg-amber-500 text-white text-xs flex items-center justify-center font-bold">{i + 1}</span>
                                                    {opt}
                                                </div>
                                            ))}
                                        </div>
                                    )}
                                    <div className="flex gap-2">
                                        <input
                                            type="text"
                                            placeholder="New option label"
                                            value={newOptionLabel}
                                            onChange={e => setNewOptionLabel(e.target.value)}
                                            className="flex-1 bg-white border border-amber-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-400 transition-all"
                                            aria-label="New option label"
                                        />
                                        <button
                                            onClick={() => startTransition(async () => await handleAddOption())}
                                            disabled={!newOptionLabel.trim() || !isConnected || isWrongNetwork || isPending}
                                            className="px-4 py-2 bg-amber-500 hover:bg-amber-600 text-white rounded-xl text-sm font-medium transition-colors disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
                                        >
                                            {isPending ? '...' : '+ Add'}
                                        </button>
                                    </div>
                                </div>
                            )}
                        </div>
                    )}
                </section>
            </main>
        </div>
    )
}
