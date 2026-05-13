import { useState, useEffect, useTransition, Fragment } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useAccount, useChainId, usePublicClient } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { Identity } from '@semaphore-protocol/identity'
import { generateProof } from '@semaphore-protocol/proof'
import { usePollState, usePollOptions, usePollResults, usePollOwner, usePollWrite } from '../hooks/usePoll'
import { useGroupSync } from '../hooks/useGroupSync'
import { useRelayVote } from '../hooks/useRelay'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'
import {
    ArrowLeft,
    Lock,
    Check,
    X,
    Copy,
    Clock,
    Key,
    Settings,
    BarChart3,
    Users,
    Radio,
    Zap,
} from 'lucide-react'

/* -- Error Map ------------------------------------------------------------ */

const ERROR_MAP: Record<string, string> = {
    'Not in voting phase': "Voting hasn't started yet. Wait for the poll admin to open voting.",
    'You have already voted': "You've already voted in this poll. Each identity can only vote once.",
    'Invalid option index': 'Invalid vote selection. Please try again.',
    'Not owner': 'Only the poll creator can perform this action.',
    'Not in registration phase': 'Registration is closed. Voting has already begun.',
    'Need at least 2 options': 'A poll needs at least 2 options before voting can start.',
    'Already registered': 'This identity is already registered for this poll.',
    'nullifier consumed': 'This vote token has already been used.',
    'Relay failed': 'Relayer service could not process the vote. Please try again.',
    'Failed to fetch': 'Cannot reach relayer service. Make sure it is running on port 3001.',
    'NetworkError': 'Network error connecting to relayer. Check your connection.',
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

/* -- State Progression ---------------------------------------------------- */

function StateProgress({ current }: { current: number }) {
    const steps = ['Registration', 'Voting', 'Ended']
    return (
        <div className="flex items-center gap-1">
            {steps.map((step, i) => (
                <Fragment key={i}>
                    {i > 0 && (
                        <div className={`flex-1 h-0.5 rounded-full transition-all duration-500 ${
                            i <= current ? 'bg-teal-500' : 'bg-stone-200 dark:bg-stone-700'
                        }`} />
                    )}
                    <div className="flex flex-col items-center gap-1.5">
                        <div className="relative">
                            <div
                                className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold transition-all duration-300
                                    ${i < current
                                        ? 'bg-teal-600 text-white'
                                        : i === current
                                            ? 'bg-white dark:bg-stone-800 border-2 border-teal-500 text-teal-600 dark:text-teal-400'
                                            : 'bg-stone-200 dark:bg-stone-700 text-stone-400 dark:text-stone-500'
                                    }`}
                            >
                                {i < current ? <Check className="w-3.5 h-3.5" /> : i + 1}
                            </div>
                            {i === current && (
                                <span className="absolute inset-0 rounded-full animate-ping bg-teal-400 opacity-15" />
                            )}
                        </div>
                        <span className={`text-xs font-medium ${i === current ? 'text-teal-700 dark:text-teal-400 font-semibold' : i < current ? 'text-teal-600 dark:text-teal-500' : 'text-stone-400 dark:text-stone-500'}`}>
                            {step}
                        </span>
                    </div>
                </Fragment>
            ))}
        </div>
    )
}

/* -- Privacy Receipt ------------------------------------------------------ */

function PrivacyReceipt() {
    return (
        <div className="bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
            <h3 className="text-sm font-semibold text-stone-900 dark:text-stone-100 mb-4 flex items-center gap-2">
                <Lock className="w-5 h-5 text-teal-600 dark:text-teal-400" />
                Privacy Receipt
            </h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="bg-teal-50 dark:bg-teal-900/30 rounded-xl p-4 border border-teal-100 dark:border-teal-800">
                    <p className="text-xs font-semibold text-teal-700 dark:text-teal-400 uppercase tracking-wide mb-2">Recorded on-chain</p>
                    <ul className="space-y-1.5 text-sm text-stone-600 dark:text-stone-400">
                        <li className="flex items-start gap-2">
                            <Check className="w-4 h-4 text-teal-500 mt-0.5 shrink-0" />
                            Your vote choice (encrypted)
                        </li>
                        <li className="flex items-start gap-2">
                            <Check className="w-4 h-4 text-teal-500 mt-0.5 shrink-0" />
                            A nullifier (prevents double-voting)
                        </li>
                        <li className="flex items-start gap-2">
                            <Check className="w-4 h-4 text-teal-500 mt-0.5 shrink-0" />
                            ZK proof of group membership
                        </li>
                    </ul>
                </div>
                <div className="bg-rose-50 dark:bg-rose-900/30 rounded-xl p-4 border border-rose-100 dark:border-rose-800">
                    <p className="text-xs font-semibold text-rose-500 dark:text-rose-400 uppercase tracking-wide mb-2">Never recorded</p>
                    <ul className="space-y-1.5 text-sm text-stone-600 dark:text-stone-400">
                        <li className="flex items-start gap-2">
                            <X className="w-4 h-4 text-rose-400 mt-0.5 shrink-0" />
                            Your wallet address
                        </li>
                        <li className="flex items-start gap-2">
                            <X className="w-4 h-4 text-rose-400 mt-0.5 shrink-0" />
                            Your identity or private key
                        </li>
                        <li className="flex items-start gap-2">
                            <X className="w-4 h-4 text-rose-400 mt-0.5 shrink-0" />
                            Any link between you and your vote
                        </li>
                    </ul>
                </div>
            </div>
        </div>
    )
}

/* -- Helpers -------------------------------------------------------------- */

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

/* -- Option Colors (solid, no gradients) ---------------------------------- */

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

/* -- Main Component ------------------------------------------------------- */

export default function Poll() {
    const { address: pollAddress } = useParams()
    const { address, isConnected } = useAccount()
    const chainId = useChainId()

    const isWrongNetwork = isConnected && chainId !== hardhat.id && chainId !== localhost.id

    const typedPollAddr = pollAddress as `0x${string}`

    const [localIdentity, setLocalIdentity] = useState<Identity | null>(null)
    const [hasVoted, setHasVoted] = useState(false)

    // Load identity scoped to this poll. The voted-state must be scoped to
    // both poll AND identity commitment so a shared-kiosk scenario (user A
    // voted, user B loads their own token on the same browser) doesn't
    // suppress the vote UI for user B.
    useEffect(() => {
        const id = loadSavedIdentity(pollAddress)
        setLocalIdentity(id)
        if (!id) {
            // No identity yet — no scoped key to read; default to not-voted.
            setHasVoted(false)
            return
        }
        const nullifier = localStorage.getItem(`my-nullifier-${pollAddress}-${id.commitment.toString()}`)
        setHasVoted(Boolean(nullifier))
    }, [pollAddress])

    const [selectedOption, setSelectedOption] = useState<number>(0)
    const [statusMsg, setStatusMsg] = useState<string>("")
    const [statusType, setStatusType] = useState<'info' | 'success' | 'error'>('info')
    const [inviteToken, setInviteToken] = useState<string>("")
    const [isPending, startTransition] = useTransition()

    // Vote submission mode: false = direct on-chain via wallet, true = gasless relayer.
    const [useRelay, setUseRelay] = useState(false)
    const { relayVote, isRelaying } = useRelayVote()

    // Admin: token generation
    const [tokenCount, setTokenCount] = useState<number>(5)
    const [generatedTokens, setGeneratedTokens] = useState<string[]>([])
    const [newOptionLabel, setNewOptionLabel] = useState<string>("")
    const [copiedIndex, setCopiedIndex] = useState<number | null>(null)

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

    // Group sync state — owned by the hook, scoped per pollAddress.
    const groupSync = useGroupSync(pollAddress, contractGroupId, publicClient, typedPollAddr)
    const isSyncing = groupSync.isSyncing

    const pollOptions = (optionsData as string[]) || []
    const voteCounts = (resultsData as bigint[])?.map(Number) || []
    const totalVotes = voteCounts.reduce((s, c) => s + c, 0)

    const currentPollState = pollState !== undefined ? Number(pollState) : -1;
    const isAdmin = pollOwner === address;

    /* -- Status helper ---------------------------------------------------- */
    function setStatus(msg: string, type: 'info' | 'success' | 'error' = 'info') {
        setStatusMsg(msg)
        setStatusType(type)
    }

    /* -- Core logic ------------------------------------------------------- */

    const loadIdentityFromToken = () => {
        if (!inviteToken) return;
        try {
            const newId = new Identity(inviteToken);
            localStorage.setItem(`semaphore-identity-${pollAddress}`, newId.privateKey.toString());
            // Loading a different identity: the voted-flag is now scoped per
            // (poll, identity) so the new identity's flag is naturally isolated.
            // Still clear the legacy unscoped key for migration cleanup, and
            // re-check the per-identity flag for the loaded identity.
            localStorage.removeItem(`my-nullifier-${pollAddress}`)
            const scopedFlag = localStorage.getItem(`my-nullifier-${pollAddress}-${newId.commitment.toString()}`)
            setHasVoted(Boolean(scopedFlag))
            groupSync.reset()
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
            groupSync.reset(); // force re-sync after new commitments registered
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
            let group = groupSync.group
            if (!group) {
                setStatus("Syncing voting group from blockchain...")
                try {
                    group = await groupSync.sync()
                    if (group) setStatus("Voting group synced. You can now vote.", 'success')
                } catch {
                    setStatus("Failed to sync voting group. Proof might fail.", 'error')
                }
            }
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
            const txHash = await writeContractAsync({
                address: typedPollAddr,
                abi: ZkAnonVotingABI.abi,
                functionName: 'castVote',
                args: [selectedOption, proofStruct],
                gas: 5000000n,
            })

            // Wait for inclusion + success before marking the local nullifier consumed.
            // writeContractAsync resolves on tx SEND, not CONFIRMATION; a revert here
            // would otherwise leave the UI showing "voted" while the on-chain
            // nullifier was never spent.
            if (!publicClient) throw new Error("No public client available to confirm transaction.")
            setStatus("Confirming on-chain... please wait for block inclusion.")
            const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash })
            if (receipt.status !== 'success') {
                throw new Error("Transaction reverted on-chain. Your vote was not recorded.")
            }

            localStorage.setItem(`my-nullifier-${pollAddress}-${localIdentity.commitment.toString()}`, fullProof.nullifier.toString())
            setHasVoted(true)
            setStatus("Vote cast successfully! Your anonymity is guaranteed by zero-knowledge cryptography.", 'success')
        } catch (e: unknown) {
            console.error(e)
            setStatus(friendlyError(e), 'error')
        }
    }

    // --- Voter: Cast Vote via Relayer (no wallet required) ---
    const handleRelayVote = async () => {
        if (!localIdentity || !pollAddress || contractGroupId === null || contractGroupId === undefined) return
        try {
            let group = groupSync.group
            if (!group) {
                setStatus("Syncing voting group from blockchain...")
                try {
                    group = await groupSync.sync()
                } catch {
                    setStatus("Failed to sync voting group. Proof might fail.", 'error')
                    return
                }
            }
            if (!group) throw new Error("Could not sync the voting group.")

            const scope = typedPollAddr
            if (group.indexOf(BigInt(localIdentity.commitment.toString())) === -1) {
                throw new Error("Your identity is not registered in this poll's on-chain group. Did you receive a valid invite token?")
            }

            setStatus("Generating zero-knowledge proof... This may take 10-30 seconds.")
            const fullProof = await generateProof(localIdentity, group, selectedOption, scope)

            setStatus("Sending vote to relayer service...")
            const result = await relayVote(pollAddress, selectedOption, fullProof)
            if (!result.success) throw new Error(result.error || 'Relay failed')
            if (!result.txHash) throw new Error("Relayer did not return a transaction hash.")

            // Wait for inclusion + success before marking the local nullifier consumed.
            // The relayer returns once the tx is broadcast; a revert (out of gas,
            // contract revert, reorg) would otherwise leave the UI showing "voted"
            // while the on-chain nullifier was never spent.
            if (!publicClient) throw new Error("No public client available to confirm transaction.")
            setStatus("Confirming on-chain... please wait for block inclusion.")
            const receipt = await publicClient.waitForTransactionReceipt({ hash: result.txHash })
            if (receipt.status !== 'success') {
                throw new Error("Relayed transaction reverted on-chain. Your vote was not recorded.")
            }

            localStorage.setItem(`my-nullifier-${pollAddress}-${localIdentity.commitment.toString()}`, fullProof.nullifier.toString())
            setHasVoted(true)
            const txTail = ` Tx: ${result.txHash.slice(0, 10)}...`
            setStatus(`Vote relayed successfully!${txTail} Your anonymity is preserved.`, 'success')
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

    /* -- Copy token helper ------------------------------------------------ */
    const copyToken = (token: string, index: number) => {
        navigator.clipboard.writeText(token)
        setCopiedIndex(index)
        setTimeout(() => setCopiedIndex(null), 1500)
    }

    /* -- Vote button label ------------------------------------------------ */
    function voteButtonLabel(): string {
        if (useRelay) {
            if (isRelaying) return 'Relaying Vote...'
            if (isSyncing) return 'Syncing Group...'
            if (isPending) return 'Processing...'
            return 'Vote via Relayer (No Wallet)'
        }
        if (isWrongNetwork) return 'Switch Network First'
        if (!isConnected) return 'Connect Wallet First'
        if (isSyncing) return 'Syncing Group...'
        if (isPending || isTxConfirming) return 'Processing...'
        return 'Cast Anonymous Vote'
    }

    const voteDisabled = useRelay
        ? isSyncing || isRelaying || isPending
        : !isConnected || isWrongNetwork || isSyncing || isTxConfirming || isPending

    /* -- Render ----------------------------------------------------------- */

    return (
        <div className="space-y-6">
            {/* -- Header ------------------------------------------------------ */}
            <div className="flex items-center justify-between animate-fade-in-up">
                <Link
                    to="/"
                    className="text-teal-600 dark:text-teal-400 hover:text-teal-800 dark:hover:text-teal-300 text-sm font-medium flex items-center gap-1.5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2 rounded-lg px-2 py-1 hover:bg-teal-50 dark:hover:bg-teal-900/30 transition-colors"
                >
                    <ArrowLeft className="w-4 h-4" />
                    Back to Polls
                </Link>
                <div className="flex items-center gap-2">
                    <span className="text-xs font-semibold px-2.5 py-1 bg-teal-100 dark:bg-teal-900/30 text-teal-700 dark:text-teal-400 rounded-full uppercase tracking-wide">
                        ZK Anonymous
                    </span>
                    <span className="text-xs font-mono text-stone-400 dark:text-stone-500 bg-stone-50 dark:bg-stone-800 px-2 py-1 rounded-lg border border-stone-200 dark:border-stone-700">
                        {pollAddress?.slice(0, 6)}...{pollAddress?.slice(-4)}
                    </span>
                </div>
            </div>

            {/* -- State Progression ------------------------------------------- */}
            {currentPollState >= 0 && (
                <div className="animate-fade-in-up animate-fade-in-up-1 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm px-6 py-5">
                    <StateProgress current={currentPollState} />
                </div>
            )}

            {/* -- Trust Signal: Encryption ------------------------------------ */}
            <div className="animate-fade-in-up animate-fade-in-up-2 bg-teal-50 dark:bg-teal-900/30 border border-teal-200 dark:border-teal-800 rounded-xl px-5 py-4 flex items-center gap-3">
                <Lock className="w-5 h-5 text-teal-600 dark:text-teal-400 flex-shrink-0" />
                <p className="text-sm text-teal-800 dark:text-teal-300 font-medium">
                    Your vote is encrypted end-to-end. Zero-knowledge proofs ensure no one can link your identity to your vote.
                </p>
            </div>

            {/* -- Status Banner ----------------------------------------------- */}
            {statusMsg && (
                <div
                    className={`px-5 py-4 rounded-xl flex items-start gap-3 text-sm font-medium border ${
                        statusType === 'success'
                            ? 'bg-emerald-50 dark:bg-emerald-900/30 border-emerald-200 dark:border-emerald-700 text-emerald-800 dark:text-emerald-300'
                            : statusType === 'error'
                                ? 'bg-rose-50 dark:bg-rose-900/30 border-rose-200 dark:border-rose-700 text-rose-800 dark:text-rose-300'
                                : 'bg-stone-50 dark:bg-stone-800 border-stone-200 dark:border-stone-700 text-stone-800 dark:text-stone-300'
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
                <p className="text-amber-600 dark:text-amber-400 text-sm font-medium animate-pulse px-1">Transaction pending...</p>
            )}
            {isTxSuccess && !statusMsg && (
                <p className="text-emerald-600 dark:text-emerald-400 text-sm font-medium px-1">Transaction confirmed!</p>
            )}

            {/* -- Main Grid --------------------------------------------------- */}
            <main className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* ======== LEFT COLUMN: Voter Panel ======== */}
                <section className="space-y-6">
                    {/* -- Identity Card ---------------------------------------- */}
                    <div className="animate-fade-in-up animate-fade-in-up-3 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                        <h2 className="text-base font-semibold text-stone-900 dark:text-stone-100 mb-1">Identity</h2>
                        <p className="text-xs text-stone-500 dark:text-stone-400 mb-4">
                            Your private key stays in your browser. It is mathematically impossible to link your identity to your vote.
                        </p>

                        {localIdentity ? (
                            <div className="flex items-center justify-between">
                                <div className="inline-flex items-center gap-2 px-4 py-2 bg-teal-50 dark:bg-teal-900/30 border border-teal-200 dark:border-teal-700 text-teal-700 dark:text-teal-400 rounded-xl text-sm font-medium">
                                    <Check className="w-4 h-4" />
                                    Identity Ready
                                </div>
                                <button
                                    onClick={() => {
                                        localStorage.removeItem(`semaphore-identity-${pollAddress}`)
                                        // Clear both the legacy unscoped key and the
                                        // identity-scoped key for the currently-loaded
                                        // identity. Other identities' scoped flags on
                                        // this device remain intact under their own keys.
                                        localStorage.removeItem(`my-nullifier-${pollAddress}`)
                                        if (localIdentity) {
                                            localStorage.removeItem(`my-nullifier-${pollAddress}-${localIdentity.commitment.toString()}`)
                                        }
                                        setLocalIdentity(null)
                                        setHasVoted(false)
                                        setInviteToken("")
                                        groupSync.reset()
                                        setStatus("Identity cleared.", 'info')
                                    }}
                                    className="text-xs text-stone-400 dark:text-stone-500 hover:text-rose-500 dark:hover:text-rose-400 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-400 rounded px-2 py-1"
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
                                    className="flex-1 bg-stone-50 dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl px-4 py-2.5 text-sm text-stone-900 dark:text-stone-100 placeholder:text-stone-400 dark:placeholder:text-stone-500 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent transition-all"
                                    aria-label="Invite token"
                                />
                                <button
                                    onClick={loadIdentityFromToken}
                                    className="px-5 py-2.5 bg-teal-600 hover:bg-teal-700 text-white transition-colors rounded-xl text-sm font-medium whitespace-nowrap focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 focus-visible:ring-offset-2"
                                >
                                    Load Identity
                                </button>
                            </div>
                        )}
                    </div>

                    {/* -- Cast Vote Card --------------------------------------- */}
                    {localIdentity && currentPollState === 1 && !hasVoted && (
                        <div className="animate-fade-in-up bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                            <h2 className="text-base font-semibold text-stone-900 dark:text-stone-100 mb-4">Cast Your Vote</h2>

                            {/* Relay Mode Toggle */}
                            <div className="flex items-center gap-3 mb-5 p-3 rounded-xl bg-stone-50 dark:bg-stone-800 border border-stone-200 dark:border-stone-700">
                                <button
                                    onClick={() => setUseRelay(false)}
                                    aria-pressed={!useRelay}
                                    className={`flex-1 flex items-center justify-center gap-2 py-2 px-3 rounded-lg text-xs font-semibold transition-all ${
                                        !useRelay
                                            ? 'bg-white dark:bg-stone-700 text-teal-700 dark:text-teal-400 shadow-sm border border-stone-200 dark:border-stone-600'
                                            : 'text-stone-500 dark:text-stone-400 hover:text-stone-700 dark:hover:text-stone-300'
                                    }`}
                                >
                                    <Radio className="w-3.5 h-3.5" />
                                    Direct (Wallet)
                                </button>
                                <button
                                    onClick={() => setUseRelay(true)}
                                    aria-pressed={useRelay}
                                    className={`flex-1 flex items-center justify-center gap-2 py-2 px-3 rounded-lg text-xs font-semibold transition-all ${
                                        useRelay
                                            ? 'bg-white dark:bg-stone-700 text-violet-700 dark:text-violet-400 shadow-sm border border-stone-200 dark:border-stone-600'
                                            : 'text-stone-500 dark:text-stone-400 hover:text-stone-700 dark:hover:text-stone-300'
                                    }`}
                                >
                                    <Zap className="w-3.5 h-3.5" />
                                    Relayer (No Wallet)
                                </button>
                            </div>

                            {useRelay && (
                                <div className="mb-4 px-3 py-2.5 bg-violet-50 dark:bg-violet-900/20 border border-violet-200 dark:border-violet-800 rounded-lg text-xs text-violet-700 dark:text-violet-400">
                                    Your vote will be submitted anonymously via the relayer service. No wallet or ETH required.
                                </div>
                            )}

                            {pollOptions.length === 0 ? (
                                <p className="text-sm text-stone-400 dark:text-stone-500">No options available.</p>
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
                                                        ? 'border-teal-500 bg-teal-50 dark:bg-teal-900/30 text-teal-800 dark:text-teal-300 font-semibold'
                                                        : 'border-stone-200 dark:border-stone-700 hover:border-teal-300 dark:hover:border-teal-600 text-stone-700 dark:text-stone-300'
                                                }`}
                                            >
                                                {/* Radio indicator */}
                                                <span className={`w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-all ${
                                                    selectedOption === i
                                                        ? 'border-teal-600 bg-teal-600'
                                                        : 'border-stone-300 dark:border-stone-600'
                                                }`}>
                                                    {selectedOption === i && (
                                                        <Check className="w-3 h-3 text-white" />
                                                    )}
                                                </span>
                                                <span>{opt}</span>
                                            </button>
                                        ))}
                                    </div>

                                    {/* VOTE BUTTON */}
                                    <button
                                        onClick={() => startTransition(async () => {
                                            if (useRelay) await handleRelayVote()
                                            else await handleVote()
                                        })}
                                        disabled={voteDisabled}
                                        className={`w-full py-4 text-white transition-colors rounded-xl text-base font-bold disabled:opacity-50 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 ${
                                            useRelay
                                                ? 'bg-violet-600 hover:bg-violet-700 active:bg-violet-800 focus-visible:ring-violet-500'
                                                : 'bg-teal-600 hover:bg-teal-700 active:bg-teal-800 focus-visible:ring-teal-500'
                                        }`}
                                    >
                                        {voteButtonLabel()}
                                    </button>
                                </fieldset>
                            )}
                        </div>
                    )}

                    {/* -- Voted: Privacy Receipt ------------------------------ */}
                    {hasVoted && currentPollState === 1 && <PrivacyReceipt />}

                    {/* -- Phase-specific empty states ------------------------- */}
                    {currentPollState === 0 && localIdentity && (
                        <div className="animate-fade-in-up bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-xl bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center flex-shrink-0">
                                    <Clock className="w-5 h-5 text-amber-600 dark:text-amber-400" />
                                </div>
                                <div>
                                    <p className="text-sm font-semibold text-amber-800 dark:text-amber-300">Registration Phase</p>
                                    <p className="text-xs text-stone-500 dark:text-stone-400 mt-0.5">
                                        Voting has not started yet. The poll admin is still registering voters and configuring options.
                                    </p>
                                </div>
                            </div>
                        </div>
                    )}

                    {currentPollState === 0 && !localIdentity && (
                        <div className="animate-fade-in-up bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-xl bg-stone-100 dark:bg-stone-800 flex items-center justify-center flex-shrink-0">
                                    <Key className="w-5 h-5 text-stone-400 dark:text-stone-500" />
                                </div>
                                <div>
                                    <p className="text-sm font-semibold text-stone-700 dark:text-stone-300">No Identity Loaded</p>
                                    <p className="text-xs text-stone-500 dark:text-stone-400 mt-0.5">
                                        Enter your invite token above to load your anonymous identity.
                                    </p>
                                </div>
                            </div>
                        </div>
                    )}

                    {currentPollState === 1 && !localIdentity && (
                        <div className="animate-fade-in-up bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-xl bg-teal-100 dark:bg-teal-900/30 flex items-center justify-center flex-shrink-0">
                                    <Key className="w-5 h-5 text-teal-600 dark:text-teal-400" />
                                </div>
                                <div>
                                    <p className="text-sm font-semibold text-teal-700 dark:text-teal-300">Voting is Open</p>
                                    <p className="text-xs text-stone-500 dark:text-stone-400 mt-0.5">
                                        Load your invite token above to cast your anonymous vote.
                                    </p>
                                </div>
                            </div>
                        </div>
                    )}

                    {currentPollState === 2 && (
                        <div className="animate-fade-in-up bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-xl bg-stone-100 dark:bg-stone-800 flex items-center justify-center flex-shrink-0">
                                    <Check className="w-5 h-5 text-stone-500 dark:text-stone-400" />
                                </div>
                                <div>
                                    <p className="text-sm font-semibold text-stone-700 dark:text-stone-300">Poll Closed</p>
                                    <p className="text-xs text-stone-500 dark:text-stone-400 mt-0.5">
                                        This poll has concluded. The final tally is shown in the results panel.
                                    </p>
                                </div>
                            </div>
                        </div>
                    )}
                </section>

                {/* ======== RIGHT COLUMN: Info Panel ======== */}
                <section className="space-y-6">
                    {/* -- Live Results Card ------------------------------------ */}
                    <div className="animate-fade-in-up animate-fade-in-up-4 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6">
                        <div className="flex items-center justify-between mb-5">
                            <h2 className="text-base font-semibold text-stone-900 dark:text-stone-100 flex items-center gap-2">
                                <BarChart3 className="w-4 h-4 text-stone-400 dark:text-stone-500" />
                                Live Results
                            </h2>
                            {totalVotes > 0 && (
                                <span className="text-xs font-semibold text-stone-500 dark:text-stone-400 bg-stone-100 dark:bg-stone-800 px-3 py-1 rounded-full font-mono tabular-nums">
                                    {totalVotes} vote{totalVotes !== 1 ? 's' : ''}
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
                                                <span className="text-sm font-medium text-stone-700 dark:text-stone-300">{opt}</span>
                                                <div className="flex items-baseline gap-2">
                                                    <span className="text-xs text-stone-400 dark:text-stone-500 font-mono tabular-nums">
                                                        {totalVotes > 0 ? `${pct.toFixed(1)}%` : '--'}
                                                    </span>
                                                    <span className="text-xl font-bold text-stone-900 dark:text-stone-100 font-mono tabular-nums">{count}</span>
                                                </div>
                                            </div>
                                            <div className="w-full bg-stone-100 dark:bg-stone-800 rounded-full h-2.5 overflow-hidden">
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
                                <BarChart3 className="w-8 h-8 text-stone-300 dark:text-stone-600 mx-auto mb-2" />
                                <p className="text-sm text-stone-400 dark:text-stone-500">No options configured yet.</p>
                            </div>
                        )}
                    </div>

                    {/* -- Privacy Receipt (after poll ends) -------------------- */}
                    {currentPollState === 2 && <PrivacyReceipt />}

                    {/* -- Admin Panel ----------------------------------------- */}
                    {isAdmin && (
                        <div className="animate-fade-in-up animate-fade-in-up-5 bg-white dark:bg-stone-900 border-2 border-amber-200 dark:border-amber-700 rounded-xl shadow-sm p-6">
                            <h2 className="text-xs font-bold text-amber-600 dark:text-amber-400 uppercase tracking-widest mb-4 flex items-center gap-2">
                                <div className="w-6 h-6 rounded-lg bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center">
                                    <Settings className="w-3.5 h-3.5 text-amber-600 dark:text-amber-400" />
                                </div>
                                Admin Panel
                            </h2>

                            {/* Poll Lifecycle Buttons */}
                            <div className="flex flex-col sm:flex-row gap-2 mb-6">
                                <button
                                    onClick={handleStartVoting}
                                    disabled={currentPollState !== 0 || !isConnected || isWrongNetwork}
                                    className="flex-1 py-2.5 bg-amber-50 dark:bg-amber-900/30 hover:bg-amber-100 dark:hover:bg-amber-900/50 text-amber-700 dark:text-amber-400 transition-all border border-amber-200 dark:border-amber-700 rounded-xl text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
                                >
                                    Start Voting
                                </button>
                                <button
                                    onClick={handleEndVoting}
                                    disabled={currentPollState !== 1 || !isConnected || isWrongNetwork}
                                    className="flex-1 py-2.5 bg-amber-50 dark:bg-amber-900/30 hover:bg-amber-100 dark:hover:bg-amber-900/50 text-amber-700 dark:text-amber-400 transition-all border border-amber-200 dark:border-amber-700 rounded-xl text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
                                >
                                    Close Poll
                                </button>
                            </div>

                            {/* Manage Options (Registration only) */}
                            {currentPollState === 0 && (
                                <div className="mb-6 border-t border-amber-100 dark:border-amber-800 pt-4">
                                    <h3 className="text-sm font-semibold text-amber-700 dark:text-amber-400 mb-3">Manage Options</h3>
                                    {pollOptions.length > 0 && (
                                        <div className="mb-3 space-y-1">
                                            {pollOptions.map((opt, i) => (
                                                <div key={i} className="flex items-center gap-2 px-3 py-2 bg-amber-50 dark:bg-amber-900/30 rounded-lg text-sm text-amber-800 dark:text-amber-300 border border-amber-100 dark:border-amber-800">
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
                                            className="flex-1 bg-white dark:bg-stone-800 border border-amber-200 dark:border-amber-700 rounded-xl px-3 py-2 text-sm text-stone-900 dark:text-stone-100 focus:outline-none focus:ring-2 focus:ring-amber-400 transition-all"
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

                            {/* Generate Tokens (Registration only) */}
                            {currentPollState === 0 && (
                                <div className="border-t border-amber-100 dark:border-amber-800 pt-4">
                                    <h3 className="text-sm font-semibold text-amber-700 dark:text-amber-400 mb-2 flex items-center gap-2">
                                        <Users className="w-4 h-4" />
                                        Generate Vote Tokens
                                    </h3>
                                    <p className="text-xs text-stone-500 dark:text-stone-400 mb-3">
                                        Create anonymous invite tokens and register them on-chain. Distribute token strings privately to voters.
                                    </p>
                                    <div className="flex gap-2 mb-4">
                                        <input
                                            type="number"
                                            min={1}
                                            max={50}
                                            value={tokenCount}
                                            onChange={e => setTokenCount(Number(e.target.value))}
                                            className="w-20 bg-white dark:bg-stone-800 border border-amber-200 dark:border-amber-700 rounded-xl px-3 py-2 text-sm text-stone-900 dark:text-stone-100 focus:outline-none focus:ring-2 focus:ring-amber-400 text-center transition-all"
                                            aria-label="Number of tokens to generate"
                                        />
                                        <button
                                            onClick={() => startTransition(async () => await handleGenerateTokens())}
                                            disabled={!isConnected || isWrongNetwork || isPending}
                                            className="flex-1 py-2 bg-amber-500 hover:bg-amber-600 text-white rounded-xl text-sm font-medium transition-colors disabled:opacity-40 disabled:cursor-not-allowed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
                                        >
                                            {isPending ? 'Generating...' : `Generate ${tokenCount} Tokens`}
                                        </button>
                                    </div>

                                    {generatedTokens.length > 0 && (
                                        <div className="bg-stone-900 dark:bg-stone-950 rounded-xl p-4 max-h-60 overflow-y-auto">
                                            <div className="flex justify-between items-center mb-3">
                                                <span className="text-xs text-stone-400 font-bold uppercase tracking-wider">
                                                    Invite Tokens (distribute privately)
                                                </span>
                                                <button
                                                    onClick={() => {
                                                        navigator.clipboard.writeText(generatedTokens.join('\n'))
                                                        setStatus("All tokens copied to clipboard!", 'success')
                                                    }}
                                                    className="text-xs bg-stone-700 hover:bg-stone-600 text-stone-200 px-3 py-1 rounded-lg transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-stone-400"
                                                >
                                                    Copy All
                                                </button>
                                            </div>
                                            {generatedTokens.map((t, i) => (
                                                <div
                                                    key={i}
                                                    onClick={() => copyToken(t, i)}
                                                    className={`flex items-center gap-2 mb-1 px-2 py-1.5 rounded-lg cursor-pointer hover:bg-stone-700/50 transition-all ${
                                                        copiedIndex === i ? 'bg-teal-900/30' : ''
                                                    }`}
                                                >
                                                    <span className="text-xs text-stone-500 w-6 font-mono">{i + 1}.</span>
                                                    <code className="text-xs text-teal-400 font-mono break-all flex-1">{t}</code>
                                                    {copiedIndex === i ? (
                                                        <span className="text-xs text-teal-400 font-medium shrink-0">Copied!</span>
                                                    ) : (
                                                        <Copy className="w-3.5 h-3.5 text-stone-500 shrink-0" />
                                                    )}
                                                </div>
                                            ))}
                                        </div>
                                    )}
                                </div>
                            )}
                        </div>
                    )}
                </section>
            </main>
        </div>
    )
}
