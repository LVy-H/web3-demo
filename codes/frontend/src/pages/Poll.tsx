import { useState, useEffect, useTransition, Fragment } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useAccount, useChainId, usePublicClient } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { Identity } from '@semaphore-protocol/identity'
import { Group } from '@semaphore-protocol/group'
import { generateProof } from '@semaphore-protocol/proof'
import { parseAbiItem } from 'viem'
import { usePollState, usePollOptions, usePollResults, usePollOwner, usePollWrite } from '../hooks/usePoll'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'

/* ─── Error Map ─────────────────────────────────────────────────────────── */

const ERROR_MAP: Record<string, string> = {
    'Not in voting phase': "Voting hasn't started yet. Wait for the poll admin to open voting.",
    'You have already voted': "You've already voted in this poll. Each identity can only vote once.",
    'Invalid option index': 'Invalid vote selection. Please try again.',
    'Not owner': 'Only the poll creator can perform this action.',
    'Not in registration phase': 'Registration is closed. Voting has already begun.',
    'Need at least 2 options': 'A poll needs at least 2 options before voting can start.',
    'Already registered': 'This identity is already registered for this poll.',
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

/* ─── State Progression Bar ─────────────────────────────────────────────── */

function StateProgress({ current }: { current: number }) {
    const steps = ['Registration', 'Voting', 'Ended']
    return (
        <div className="flex items-center gap-1">
            {steps.map((step, i) => (
                <Fragment key={i}>
                    {i > 0 && (
                        <div className={`flex-1 h-0.5 ${i <= current ? 'bg-blue-500' : 'bg-slate-200'}`} />
                    )}
                    <div className="flex flex-col items-center gap-1">
                        <div
                            className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-semibold
                                ${i < current
                                    ? 'bg-emerald-500 text-white'
                                    : i === current
                                        ? 'bg-blue-600 text-white'
                                        : 'bg-slate-200 text-slate-400'
                                }`}
                        >
                            {i < current ? '\u2713' : i + 1}
                        </div>
                        <span className={`text-xs ${i === current ? 'text-blue-700 font-semibold' : 'text-slate-400'}`}>
                            {step}
                        </span>
                    </div>
                </Fragment>
            ))}
        </div>
    )
}

/* ─── Privacy Receipt ───────────────────────────────────────────────────── */

function PrivacyReceipt() {
    return (
        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
            <h3 className="text-sm font-semibold text-slate-900 mb-4 flex items-center gap-2">
                <svg className="w-4 h-4 text-emerald-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                </svg>
                Privacy Receipt
            </h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                    <p className="text-xs font-semibold text-emerald-600 uppercase tracking-wide mb-2">Recorded on-chain</p>
                    <ul className="space-y-1.5 text-sm text-slate-600">
                        <li className="flex items-start gap-2">
                            <span className="text-emerald-500 mt-0.5">&#10003;</span>
                            Your vote choice (encrypted)
                        </li>
                        <li className="flex items-start gap-2">
                            <span className="text-emerald-500 mt-0.5">&#10003;</span>
                            A nullifier (prevents double-voting)
                        </li>
                        <li className="flex items-start gap-2">
                            <span className="text-emerald-500 mt-0.5">&#10003;</span>
                            ZK proof of group membership
                        </li>
                    </ul>
                </div>
                <div>
                    <p className="text-xs font-semibold text-rose-500 uppercase tracking-wide mb-2">Never recorded</p>
                    <ul className="space-y-1.5 text-sm text-slate-600">
                        <li className="flex items-start gap-2">
                            <span className="text-rose-400 mt-0.5">&#10007;</span>
                            Your wallet address
                        </li>
                        <li className="flex items-start gap-2">
                            <span className="text-rose-400 mt-0.5">&#10007;</span>
                            Your identity or private key
                        </li>
                        <li className="flex items-start gap-2">
                            <span className="text-rose-400 mt-0.5">&#10007;</span>
                            Any link between you and your vote
                        </li>
                    </ul>
                </div>
            </div>
        </div>
    )
}

/* ─── Module-level state (preserved) ────────────────────────────────────── */

let group: Group | null = null;
let isGroupSynced = false;

function loadSavedIdentity(pollAddr: string | undefined): Identity | null {
    if (!pollAddr) return null
    try {
        const saved = localStorage.getItem(`semaphore-identity-${pollAddr}`)
        if (!saved) return null
        return new Identity(saved)
    } catch {
        return null
    }
}

/* ─── Option Colors ─────────────────────────────────────────────────────── */

const OPTION_COLORS = [
    'bg-blue-500', 'bg-indigo-400', 'bg-emerald-500', 'bg-amber-500',
    'bg-rose-500', 'bg-purple-500', 'bg-teal-500', 'bg-orange-500',
    'bg-cyan-500', 'bg-pink-500',
]

/* ─── Main Component ────────────────────────────────────────────────────── */

export default function Poll() {
    const { address: pollAddress } = useParams()
    const { address, isConnected } = useAccount()
    const chainId = useChainId()

    const isWrongNetwork = isConnected && chainId !== hardhat.id && chainId !== localhost.id

    const typedPollAddr = pollAddress as `0x${string}`

    const [localIdentity, setLocalIdentity] = useState<Identity | null>(null)
    const [hasVoted, setHasVoted] = useState(false)

    // Load identity scoped to this poll
    useEffect(() => {
        setLocalIdentity(loadSavedIdentity(pollAddress))
        isGroupSynced = false
        // Restore voted state from localStorage
        const nullifier = localStorage.getItem('my-nullifier')
        if (nullifier) setHasVoted(true)
    }, [pollAddress])

    const [selectedOption, setSelectedOption] = useState<number>(0)
    const [statusMsg, setStatusMsg] = useState<string>("")
    const [statusType, setStatusType] = useState<'info' | 'success' | 'error'>('info')
    const [inviteToken, setInviteToken] = useState<string>("")
    const [isSyncing, setIsSyncing] = useState(false)
    const [isPending, startTransition] = useTransition()

    // Admin: token generation
    const [tokenCount, setTokenCount] = useState<number>(5)
    const [generatedTokens, setGeneratedTokens] = useState<string[]>([])
    const [newOptionLabel, setNewOptionLabel] = useState<string>("")

    // Use hooks from usePoll
    const { data: pollOwner } = usePollOwner(typedPollAddr)
    const { data: pollState } = usePollState(typedPollAddr)
    const { data: optionsData, refetch: refetchOptions } = usePollOptions(typedPollAddr)
    const { data: resultsData } = usePollResults(typedPollAddr)

    // Write hook for all contract mutations
    const { mutateAsync: writeContractAsync, isConfirming: isTxConfirming, isSuccess: isTxSuccess } = usePollWrite()

    const publicClient = usePublicClient()

    // Read groupId from ZkAnonVoting (not in IZkPoll interface)
    const [contractGroupId, setContractGroupId] = useState<bigint | null>(null)
    useEffect(() => {
        if (!publicClient || !pollAddress) return
        publicClient.readContract({
            address: typedPollAddr,
            abi: ZkAnonVotingABI.abi,
            functionName: 'groupId',
            args: [],
        }).then(result => {
            setContractGroupId(result as bigint)
        }).catch(() => {
            // groupId might not be available yet
        })
    }, [publicClient, pollAddress, typedPollAddr])

    const pollOptions = (optionsData as string[]) || []
    const voteCounts = (resultsData as bigint[])?.map(Number) || []
    const totalVotes = voteCounts.reduce((s, c) => s + c, 0)

    const currentPollState = pollState !== undefined ? Number(pollState) : -1;
    const isAdmin = pollOwner === address;

    /* ─── Status helper ──────────────────────────────────────────────── */
    function setStatus(msg: string, type: 'info' | 'success' | 'error' = 'info') {
        setStatusMsg(msg)
        setStatusType(type)
    }

    /* ─── Core logic (unchanged) ─────────────────────────────────────── */

    const syncGroupState = async () => {
        if (!pollAddress || !publicClient || isGroupSynced || contractGroupId === undefined || contractGroupId === null) return;
        setIsSyncing(true);
        setStatus("Syncing voting group from blockchain...");
        try {
            group = new Group();
            const logs = await publicClient.getLogs({
                address: typedPollAddr,
                event: parseAbiItem('event VoterRegistered(uint256 identityCommitment)'),
                fromBlock: 0n,
            });
            logs.forEach(log => {
                try {
                    if (log.args.identityCommitment && group) {
                        group.addMember(BigInt(log.args.identityCommitment.toString()));
                    }
                } catch (e: unknown) {
                    const err = e as { message?: string }
                    if (!err.message?.includes('already')) console.warn(err.message);
                }
            });
            isGroupSynced = true;
            setStatus("Voting group synced. You can now vote.", 'success');
        } catch (e) {
            console.error("Failed to sync group", e);
            setStatus("Failed to sync voting group. Proof might fail.", 'error');
        } finally {
            setIsSyncing(false);
        }
    }

    const loadIdentityFromToken = () => {
        if (!inviteToken) return;
        try {
            const newId = new Identity(inviteToken);
            localStorage.setItem(`semaphore-identity-${pollAddress}`, newId.privateKey.toString());
            setLocalIdentity(newId);
            setStatus("Identity loaded successfully from invite token.", 'success');
        } catch {
            setStatus("Invalid invite token. Please double-check and try again.", 'error');
        }
    }

    // --- Admin: Generate Tokens & Auto-Register ---
    const handleGenerateTokens = async () => {
        if (!pollAddress) return;
        try {
            setStatus(`Generating ${tokenCount} vote tokens...`)
            const tokens: string[] = []
            const commitments: bigint[] = []

            for (let i = 0; i < tokenCount; i++) {
                const privateKeyBytes = new Uint8Array(32)
                crypto.getRandomValues(privateKeyBytes)
                const privateKeyHex = Array.from(privateKeyBytes).map(b => b.toString(16).padStart(2, '0')).join('')
                const identity = new Identity(privateKeyHex)
                tokens.push(privateKeyHex)
                commitments.push(identity.commitment)
            }

            setStatus(`Registering ${tokenCount} commitments on-chain...`)
            await writeContractAsync({
                address: typedPollAddr,
                abi: ZkAnonVotingABI.abi,
                functionName: 'registerVoters',
                args: [commitments],
                gas: 15000000n,
            })

            setGeneratedTokens(tokens)
            isGroupSynced = false; // force re-sync
            setStatus(`${tokenCount} tokens generated and registered on-chain! Distribute them to voters.`, 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    // --- Admin: Add Option ---
    const handleAddOption = async () => {
        if (!pollAddress || !newOptionLabel.trim()) return;
        try {
            setStatus("Adding option on-chain...")
            await writeContractAsync({
                address: typedPollAddr,
                abi: ZkAnonVotingABI.abi,
                functionName: 'addOption',
                args: [newOptionLabel.trim()],
            })
            setNewOptionLabel("")
            refetchOptions()
            setStatus("Option added successfully!", 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    // --- Voter: Cast Vote ---
    const handleVote = async () => {
        if (!localIdentity || !pollAddress || contractGroupId === undefined) return
        try {
            await syncGroupState();
            if (!group) throw new Error("Group not initialized");

            setStatus("Generating zero-knowledge proof... This may take a moment.")

            const scope = typedPollAddr

            if (group.indexOf(BigInt(localIdentity.commitment.toString())) === -1) {
                throw new Error("Your identity is not registered in this poll's on-chain group. Did you receive a valid invite token?");
            }

            const fullProof = await generateProof(localIdentity, group, selectedOption, scope)

            const proofStruct = {
                merkleTreeDepth: fullProof.merkleTreeDepth,
                merkleTreeRoot: fullProof.merkleTreeRoot,
                nullifier: fullProof.nullifier,
                message: fullProof.message,
                scope: fullProof.scope,
                points: fullProof.points
            }

            setStatus("Submitting ZK proof to the blockchain...")
            await writeContractAsync({
                address: typedPollAddr,
                abi: ZkAnonVotingABI.abi,
                functionName: 'castVote',
                args: [selectedOption, proofStruct],
                gas: 5000000n,
            })

            localStorage.setItem('my-nullifier', fullProof.nullifier.toString())
            setHasVoted(true)
            setStatus("Vote cast successfully! Your anonymity is guaranteed by zero-knowledge cryptography.", 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    // Admin actions
    const handleStartVoting = async () => {
        if (!pollAddress) return;
        try {
            setStatus("Starting voting phase...")
            await writeContractAsync({ address: typedPollAddr, abi: ZkAnonVotingABI.abi, functionName: 'startVoting' })
            setStatus("Voting phase started!", 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    const handleEndVoting = async () => {
        if (!pollAddress) return;
        try {
            setStatus("Ending voting phase...")
            await writeContractAsync({ address: typedPollAddr, abi: ZkAnonVotingABI.abi, functionName: 'endVoting' })
            setStatus("Voting has ended. Final results are now locked.", 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    /* ─── Vote button label ──────────────────────────────────────────── */
    function voteButtonLabel(): string {
        if (isWrongNetwork) return 'Switch Network First'
        if (!isConnected) return 'Connect Wallet First'
        if (isSyncing) return 'Syncing Group...'
        if (isPending || isTxConfirming) return 'Processing...'
        return 'Cast Anonymous Vote'
    }

    const voteDisabled = !isConnected || isWrongNetwork || isSyncing || isTxConfirming || isPending

    /* ─── Render ─────────────────────────────────────────────────────── */

    return (
        <div className="space-y-6">
            {/* ── Header ─────────────────────────────────────────────── */}
            <div className="flex items-center justify-between">
                <Link
                    to="/"
                    className="text-blue-600 hover:text-blue-800 text-sm font-medium flex items-center gap-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2 rounded-lg px-1 py-0.5"
                >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" />
                    </svg>
                    Back to Polls
                </Link>
                <span className="text-xs font-mono text-slate-400 bg-slate-100 px-2 py-1 rounded-lg border border-slate-200">
                    {pollAddress?.slice(0, 6)}...{pollAddress?.slice(-4)}
                </span>
            </div>

            {/* ── State Progression ──────────────────────────────────── */}
            {currentPollState >= 0 && (
                <div className="bg-white border border-slate-200 rounded-2xl shadow-sm px-6 py-4">
                    <StateProgress current={currentPollState} />
                </div>
            )}

            {/* ── Trust Signal: Encryption ───────────────────────────── */}
            <div className="bg-blue-50 border border-blue-200 rounded-2xl px-4 py-3 flex items-center gap-3">
                <svg className="w-5 h-5 text-blue-600 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
                <p className="text-sm text-blue-800 font-medium">
                    Your vote is encrypted end-to-end. Zero-knowledge proofs ensure no one can link your identity to your vote.
                </p>
            </div>

            {/* ── Status Banner ───────────────────────────────────────── */}
            {statusMsg && (
                <div
                    className={`px-4 py-3 rounded-2xl flex items-start gap-3 text-sm font-medium shadow-sm border ${
                        statusType === 'success'
                            ? 'bg-emerald-50 border-emerald-200 text-emerald-800'
                            : statusType === 'error'
                                ? 'bg-rose-50 border-rose-200 text-rose-800'
                                : 'bg-blue-50 border-blue-100 text-blue-800'
                    }`}
                    role="status"
                    aria-live="polite"
                >
                    <div className={`mt-0.5 h-2 w-2 rounded-full flex-shrink-0 ${
                        statusType === 'success'
                            ? 'bg-emerald-500'
                            : statusType === 'error'
                                ? 'bg-rose-500'
                                : 'bg-blue-500 animate-pulse'
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

            {/* ── Main Grid ──────────────────────────────────────────── */}
            <main className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* ════════ LEFT COLUMN: Voter Panel ════════ */}
                <section className="space-y-6">
                    {/* ── Identity Card ───────────────────────────────── */}
                    <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
                        <h2 className="text-base font-semibold text-slate-900 mb-1">Identity</h2>
                        <p className="text-xs text-slate-500 mb-4">
                            Your private key stays in your browser. It is mathematically impossible to link your identity to your vote.
                        </p>

                        {localIdentity ? (
                            <div className="flex items-center justify-between">
                                <div className="inline-flex items-center gap-2 px-4 py-2 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-xl text-sm font-medium">
                                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                                    </svg>
                                    Identity Ready
                                </div>
                                <button
                                    onClick={() => {
                                        localStorage.removeItem(`semaphore-identity-${pollAddress}`)
                                        setLocalIdentity(null)
                                        setHasVoted(false)
                                        setStatus("Identity cleared.", 'info')
                                    }}
                                    className="text-xs text-slate-400 hover:text-rose-500 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-400 rounded px-2 py-1"
                                >
                                    Clear
                                </button>
                            </div>
                        ) : (
                            <div className="flex flex-col sm:flex-row gap-2">
                                <input
                                    type="text"
                                    placeholder="Paste your invite token"
                                    value={inviteToken}
                                    onChange={e => setInviteToken(e.target.value)}
                                    className="flex-1 bg-slate-50 border border-slate-200 rounded-xl px-4 py-2.5 text-sm text-slate-900 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                                    aria-label="Invite token"
                                />
                                <button
                                    onClick={loadIdentityFromToken}
                                    className="px-5 py-2.5 bg-blue-600 hover:bg-blue-700 text-white transition-colors rounded-xl text-sm font-medium shadow-sm whitespace-nowrap focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
                                >
                                    Load Identity
                                </button>
                            </div>
                        )}
                    </div>

                    {/* ── Cast Vote Card ──────────────────────────────── */}
                    {localIdentity && currentPollState === 1 && !hasVoted && (
                        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
                            <h2 className="text-base font-semibold text-slate-900 mb-4">Cast Your Vote</h2>

                            {pollOptions.length === 0 ? (
                                <p className="text-sm text-slate-400">No options available.</p>
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
                                                className={`w-full min-h-[48px] py-3 px-4 rounded-xl border-2 transition-all text-left flex items-center gap-3 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2 ${
                                                    selectedOption === i
                                                        ? 'border-l-[3px] border-blue-600 bg-blue-50 text-blue-800 font-semibold'
                                                        : 'border-slate-200 hover:border-slate-300 text-slate-700'
                                                }`}
                                            >
                                                {/* Radio indicator */}
                                                <span className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 ${
                                                    selectedOption === i
                                                        ? 'border-blue-600 bg-blue-600'
                                                        : 'border-slate-300'
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

                                    {/* VOTE BUTTON -- largest element, full-width */}
                                    <button
                                        onClick={() => startTransition(async () => await handleVote())}
                                        disabled={voteDisabled}
                                        className="w-full py-4 bg-blue-600 hover:bg-blue-700 active:bg-blue-800 text-white transition-colors rounded-2xl text-base font-bold shadow-md disabled:opacity-50 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
                                    >
                                        {voteButtonLabel()}
                                    </button>
                                </fieldset>
                            )}
                        </div>
                    )}

                    {/* ── Voted: Privacy Receipt ─────────────────────── */}
                    {hasVoted && currentPollState === 1 && <PrivacyReceipt />}

                    {/* ── Phase-specific empty states ─────────────────── */}
                    {currentPollState === 0 && localIdentity && (
                        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-full bg-amber-100 flex items-center justify-center flex-shrink-0">
                                    <svg className="w-5 h-5 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                                    </svg>
                                </div>
                                <div>
                                    <p className="text-sm font-semibold text-amber-800">Registration Phase</p>
                                    <p className="text-xs text-slate-500 mt-0.5">
                                        Voting has not started yet. The poll admin is still registering voters and configuring options.
                                    </p>
                                </div>
                            </div>
                        </div>
                    )}

                    {currentPollState === 0 && !localIdentity && (
                        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-full bg-slate-100 flex items-center justify-center flex-shrink-0">
                                    <svg className="w-5 h-5 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z" />
                                    </svg>
                                </div>
                                <div>
                                    <p className="text-sm font-semibold text-slate-700">No Identity Loaded</p>
                                    <p className="text-xs text-slate-500 mt-0.5">
                                        Enter your invite token above to load your anonymous identity.
                                    </p>
                                </div>
                            </div>
                        </div>
                    )}

                    {currentPollState === 1 && !localIdentity && (
                        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-full bg-blue-100 flex items-center justify-center flex-shrink-0">
                                    <svg className="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z" />
                                    </svg>
                                </div>
                                <div>
                                    <p className="text-sm font-semibold text-blue-700">Voting is Open</p>
                                    <p className="text-xs text-slate-500 mt-0.5">
                                        Load your invite token above to cast your anonymous vote.
                                    </p>
                                </div>
                            </div>
                        </div>
                    )}

                    {currentPollState === 2 && (
                        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-full bg-slate-100 flex items-center justify-center flex-shrink-0">
                                    <svg className="w-5 h-5 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                                    </svg>
                                </div>
                                <div>
                                    <p className="text-sm font-semibold text-slate-700">Poll Closed</p>
                                    <p className="text-xs text-slate-500 mt-0.5">
                                        This poll has concluded. The final tally is shown in the results panel.
                                    </p>
                                </div>
                            </div>
                        </div>
                    )}
                </section>

                {/* ════════ RIGHT COLUMN: Info Panel ════════ */}
                <section className="space-y-6">
                    {/* ── Live Results Card ───────────────────────────── */}
                    <div className="bg-white border border-slate-200 rounded-2xl shadow-sm p-6">
                        <div className="flex items-center justify-between mb-4">
                            <h2 className="text-base font-semibold text-slate-900">Live Results</h2>
                            {totalVotes > 0 && (
                                <span className="text-xs text-slate-400 bg-slate-100 px-2 py-1 rounded-lg">
                                    {totalVotes} vote{totalVotes !== 1 ? 's' : ''}
                                </span>
                            )}
                        </div>

                        {pollOptions.length > 0 ? (
                            <div className="space-y-4">
                                {pollOptions.map((opt, i) => {
                                    const count = voteCounts[i] || 0
                                    const pct = totalVotes > 0 ? (count / totalVotes) * 100 : 0
                                    const color = OPTION_COLORS[i % OPTION_COLORS.length]
                                    return (
                                        <div key={i}>
                                            <div className="flex justify-between items-baseline mb-1.5">
                                                <span className="text-sm font-medium text-slate-700">{opt}</span>
                                                <div className="flex items-baseline gap-1.5">
                                                    <span className="text-xs text-slate-400">
                                                        {totalVotes > 0 ? `${pct.toFixed(0)}%` : '--'}
                                                    </span>
                                                    <span className="text-lg font-bold text-slate-900 tabular-nums">{count}</span>
                                                </div>
                                            </div>
                                            <div className="w-full bg-slate-100 rounded-full h-2.5 overflow-hidden">
                                                <div
                                                    className={`${color} h-2.5 rounded-full transition-all duration-700 ease-out`}
                                                    style={{ width: `${pct}%` }}
                                                />
                                            </div>
                                        </div>
                                    )
                                })}
                            </div>
                        ) : (
                            <div className="text-center py-8">
                                <svg className="w-8 h-8 text-slate-300 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                                </svg>
                                <p className="text-sm text-slate-400">No options configured yet.</p>
                            </div>
                        )}
                    </div>

                    {/* ── Privacy Receipt (after poll ends) ───────────── */}
                    {currentPollState === 2 && <PrivacyReceipt />}

                    {/* ── Admin Panel ─────────────────────────────────── */}
                    {isAdmin && (
                        <div className="bg-white border-2 border-rose-200 rounded-2xl shadow-sm p-6 relative">
                            {/* Rose tint overlay for distinction */}
                            <div className="absolute inset-0 bg-rose-50/30 rounded-2xl pointer-events-none" />

                            <div className="relative">
                                <h2 className="text-xs font-bold text-rose-500 uppercase tracking-widest mb-4 flex items-center gap-2">
                                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                                    </svg>
                                    Admin Panel
                                </h2>

                                {/* Poll Lifecycle Buttons */}
                                <div className="flex flex-col sm:flex-row gap-2 mb-6">
                                    <button
                                        onClick={handleStartVoting}
                                        disabled={currentPollState !== 0 || !isConnected || isWrongNetwork}
                                        className="flex-1 py-2.5 bg-rose-50 hover:bg-rose-100 text-rose-700 transition border border-rose-200 rounded-xl text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-400"
                                    >
                                        Start Voting
                                    </button>
                                    <button
                                        onClick={handleEndVoting}
                                        disabled={currentPollState !== 1 || !isConnected || isWrongNetwork}
                                        className="flex-1 py-2.5 bg-rose-50 hover:bg-rose-100 text-rose-700 transition border border-rose-200 rounded-xl text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-400"
                                    >
                                        Close Poll
                                    </button>
                                </div>

                                {/* Manage Options (Registration only) */}
                                {currentPollState === 0 && (
                                    <div className="mb-6 border-t border-rose-100 pt-4">
                                        <h3 className="text-sm font-semibold text-rose-700 mb-3">Manage Options</h3>
                                        {pollOptions.length > 0 && (
                                            <div className="mb-3 space-y-1">
                                                {pollOptions.map((opt, i) => (
                                                    <div key={i} className="flex items-center gap-2 px-3 py-2 bg-rose-50 rounded-lg text-sm text-rose-800 border border-rose-100">
                                                        <span className="w-5 h-5 rounded-full bg-rose-200 text-rose-700 text-xs flex items-center justify-center font-bold">{i + 1}</span>
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
                                                className="flex-1 bg-white border border-rose-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-rose-400"
                                                aria-label="New option label"
                                            />
                                            <button
                                                onClick={() => startTransition(async () => await handleAddOption())}
                                                disabled={!newOptionLabel.trim() || !isConnected || isWrongNetwork || isPending}
                                                className="px-4 py-2 bg-rose-600 hover:bg-rose-700 text-white rounded-xl text-sm font-medium transition-colors disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-400"
                                            >
                                                {isPending ? '...' : '+ Add'}
                                            </button>
                                        </div>
                                    </div>
                                )}

                                {/* Generate Tokens (Registration only) */}
                                {currentPollState === 0 && (
                                    <div className="border-t border-rose-100 pt-4">
                                        <h3 className="text-sm font-semibold text-rose-700 mb-2">Generate Vote Tokens</h3>
                                        <p className="text-xs text-slate-500 mb-3">
                                            Create anonymous invite tokens and register them on-chain. Distribute token strings privately to voters.
                                        </p>
                                        <div className="flex gap-2 mb-4">
                                            <input
                                                type="number"
                                                min={1}
                                                max={50}
                                                value={tokenCount}
                                                onChange={e => setTokenCount(Number(e.target.value))}
                                                className="w-20 bg-white border border-rose-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-rose-400 text-center"
                                                aria-label="Number of tokens to generate"
                                            />
                                            <button
                                                onClick={() => startTransition(async () => await handleGenerateTokens())}
                                                disabled={!isConnected || isWrongNetwork || isPending}
                                                className="flex-1 py-2 bg-rose-600 hover:bg-rose-700 text-white rounded-xl text-sm font-medium transition-colors disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-400"
                                            >
                                                {isPending ? 'Generating...' : `Generate ${tokenCount} Tokens`}
                                            </button>
                                        </div>

                                        {generatedTokens.length > 0 && (
                                            <div className="bg-slate-900 rounded-xl p-4 max-h-60 overflow-y-auto">
                                                <div className="flex justify-between items-center mb-3">
                                                    <span className="text-xs text-slate-400 font-bold uppercase tracking-wider">
                                                        Invite Tokens (distribute privately)
                                                    </span>
                                                    <button
                                                        onClick={() => {
                                                            navigator.clipboard.writeText(generatedTokens.join('\n'))
                                                            setStatus("All tokens copied to clipboard!", 'success')
                                                        }}
                                                        className="text-xs bg-slate-700 hover:bg-slate-600 text-slate-200 px-3 py-1 rounded-lg transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-slate-400"
                                                    >
                                                        Copy All
                                                    </button>
                                                </div>
                                                {generatedTokens.map((t, i) => (
                                                    <div key={i} className="flex items-center gap-2 mb-1">
                                                        <span className="text-xs text-slate-500 w-6">{i + 1}.</span>
                                                        <code className="text-xs text-emerald-400 font-mono break-all">{t}</code>
                                                    </div>
                                                ))}
                                            </div>
                                        )}
                                    </div>
                                )}
                            </div>
                        </div>
                    )}
                </section>
            </main>
        </div>
    )
}
