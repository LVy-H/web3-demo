import { useState, useEffect, useTransition } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useAccount, useChainId, usePublicClient } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { Identity } from '@semaphore-protocol/identity'
import { Group } from '@semaphore-protocol/group'
import { generateProof } from '@semaphore-protocol/proof'
import { parseAbiItem } from 'viem'
import { usePollState, usePollOptions, usePollResults, usePollOwner, usePollWrite } from '../hooks/usePoll'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'

let group: Group | null = null;

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

let isGroupSynced = false;

export default function Poll() {
    const { address: pollAddress } = useParams()
    const { address, isConnected } = useAccount()
    const chainId = useChainId()

    const isWrongNetwork = isConnected && chainId !== hardhat.id && chainId !== localhost.id

    const typedPollAddr = pollAddress as `0x${string}`

    const [localIdentity, setLocalIdentity] = useState<Identity | null>(null)

    // Load identity scoped to this poll
    useEffect(() => {
        setLocalIdentity(loadSavedIdentity(pollAddress))
        isGroupSynced = false
    }, [pollAddress])

    const [selectedOption, setSelectedOption] = useState<number>(0)
    const [statusMsg, setStatusMsg] = useState<string>("")
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

    const syncGroupState = async () => {
        if (!pollAddress || !publicClient || isGroupSynced || contractGroupId === undefined || contractGroupId === null) return;
        setIsSyncing(true);
        setStatusMsg("Syncing voting group from blockchain...");
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
            setStatusMsg("Voting group synced. You can now vote.");
        } catch (e) {
            console.error("Failed to sync group", e);
            setStatusMsg("Failed to sync voting group. Proof might fail.");
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
            setStatusMsg("Identity loaded successfully from Invite Token.");
        } catch {
            setStatusMsg("Invalid Invite Token.");
        }
    }

    // --- Admin: Generate Tokens & Auto-Register ---
    const handleGenerateTokens = async () => {
        if (!pollAddress) return;
        try {
            setStatusMsg(`Generating ${tokenCount} vote tokens...`)
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

            setStatusMsg(`Registering ${tokenCount} commitments on-chain...`)
            await writeContractAsync({
                address: typedPollAddr,
                abi: ZkAnonVotingABI.abi,
                functionName: 'registerVoters',
                args: [commitments],
                gas: 15000000n,
            })

            setGeneratedTokens(tokens)
            isGroupSynced = false; // force re-sync
            setStatusMsg(`${tokenCount} tokens generated and registered on-chain! Distribute them to voters.`)
        } catch (e: unknown) {
            console.error(e)
            const err = e as { shortMessage?: string; message?: string }
            setStatusMsg(`Token Gen Error: ${err.shortMessage ?? err.message ?? String(e)}`)
        }
    }

    // --- Admin: Add Option ---
    const handleAddOption = async () => {
        if (!pollAddress || !newOptionLabel.trim()) return;
        try {
            setStatusMsg("Adding option on-chain...")
            await writeContractAsync({
                address: typedPollAddr,
                abi: ZkAnonVotingABI.abi,
                functionName: 'addOption',
                args: [newOptionLabel.trim()],
            })
            setNewOptionLabel("")
            refetchOptions()
            setStatusMsg("Option added successfully!")
        } catch (e: unknown) {
            console.error(e)
            const err = e as { shortMessage?: string; message?: string }
            setStatusMsg(`Add Option Error: ${err.shortMessage ?? err.message ?? String(e)}`)
        }
    }

    // --- Voter: Cast Vote ---
    const handleVote = async () => {
        if (!localIdentity || !pollAddress || contractGroupId === undefined) return
        try {
            await syncGroupState();
            if (!group) throw new Error("Group not initialized");

            setStatusMsg("Generating Zero-Knowledge Proof... (Heavy computation)")

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

            setStatusMsg("Submitting ZKP to the blockchain...")
            await writeContractAsync({
                address: typedPollAddr,
                abi: ZkAnonVotingABI.abi,
                functionName: 'castVote',
                args: [selectedOption, proofStruct],
                gas: 5000000n,
            })

            localStorage.setItem('my-nullifier', fullProof.nullifier.toString())
            setStatusMsg("Voted Successfully! Your anonymity is guaranteed.")
        } catch (e: unknown) {
            console.error(e)
            const err = e as { shortMessage?: string; message?: string }
            setStatusMsg(`Voting Error: ${err.shortMessage ?? err.message ?? String(e)}`)
        }
    }

    // Admin actions
    const handleStartVoting = async () => {
        if (!pollAddress) return;
        try {
            await writeContractAsync({ address: typedPollAddr, abi: ZkAnonVotingABI.abi, functionName: 'startVoting' })
        } catch (e) { console.error(e) }
    }

    const handleEndVoting = async () => {
        if (!pollAddress) return;
        try {
            await writeContractAsync({ address: typedPollAddr, abi: ZkAnonVotingABI.abi, functionName: 'endVoting' })
        } catch (e) { console.error(e) }
    }

    const optionColors = [
        'bg-blue-500', 'bg-indigo-400', 'bg-emerald-500', 'bg-amber-500',
        'bg-rose-500', 'bg-purple-500', 'bg-teal-500', 'bg-orange-500',
        'bg-cyan-500', 'bg-pink-500',
    ]

    return (
        <div className="space-y-8">
            <Link to="/" className="text-blue-600 hover:text-blue-800 text-sm font-medium flex items-center gap-1">
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" /></svg>
                Back to Polls
            </Link>

            {statusMsg && (
                <div className="p-4 bg-blue-50 border border-blue-100 rounded-2xl flex items-center gap-3 text-blue-800 shadow-sm">
                    <div className="h-2 w-2 bg-blue-500 rounded-full animate-pulse"></div>
                    <p className="text-sm font-medium">{statusMsg}</p>
                </div>
            )}

            {isTxConfirming && <p className="text-amber-600 text-sm font-medium animate-pulse">Transaction pending...</p>}
            {isTxSuccess && <p className="text-emerald-600 text-sm font-medium">Transaction confirmed!</p>}

            <main className="grid grid-cols-1 lg:grid-cols-2 gap-8 lg:gap-12">
                {/* USER PANEL */}
                <section className="bg-white border border-slate-200 rounded-3xl p-8 shadow-sm">
                    <h2 className="text-xl font-semibold mb-6 text-slate-900 border-b border-slate-100 pb-4 flex justify-between items-center">
                        Voter Action
                        {!isAdmin && <span className="text-xs font-bold px-2 py-1 bg-blue-100 text-blue-700 rounded-md">VOTER MODE</span>}
                    </h2>

                    <div className="space-y-8">
                        <div>
                            <h3 className="text-sm font-medium text-slate-900 mb-2">1. Identity (Zero-Knowledge)</h3>
                            <p className="text-xs text-slate-500 mb-4">Your private key stays strictly in your browser. It is mathematically impossible to link your identity to your vote.</p>
                            {localIdentity ? (
                                <div className="flex items-center gap-3">
                                    <div className="inline-flex items-center gap-2 px-4 py-2 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-xl text-sm font-medium">
                                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" /></svg>
                                        Identity Ready
                                    </div>
                                    <button onClick={() => { localStorage.removeItem(`semaphore-identity-${pollAddress}`); setLocalIdentity(null); setStatusMsg("Identity cleared.") }} className="text-xs text-slate-400 hover:text-rose-500 transition-colors">
                                        Clear
                                    </button>
                                </div>
                            ) : (
                                <div className="flex flex-col sm:flex-row gap-3">
                                    <input type="text" placeholder="Enter Invite Token" value={inviteToken} onChange={e => setInviteToken(e.target.value)} className="flex-1 bg-slate-50 border border-slate-200 rounded-xl px-4 py-2.5 text-sm text-slate-900 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all" />
                                    <button onClick={loadIdentityFromToken} className="px-5 py-2.5 bg-blue-600 hover:bg-blue-700 text-white transition-colors rounded-xl text-sm font-medium shadow-sm whitespace-nowrap">
                                        Load Identity
                                    </button>
                                </div>
                            )}
                        </div>

                        {localIdentity && currentPollState === 1 && (
                            <div className="pt-6 border-t border-slate-100">
                                <h3 className="text-sm font-medium text-slate-900 mb-3">2. Cast Vote Anonymously</h3>
                                <div className="flex flex-col gap-2 mb-5">
                                    {pollOptions.map((opt, i) => (
                                        <button key={i} onClick={() => setSelectedOption(i)} className={`w-full py-3 px-4 rounded-xl border-2 transition-all text-left ${selectedOption === i ? 'border-blue-600 bg-blue-50 text-blue-700 font-semibold' : 'border-slate-200 hover:border-slate-300 text-slate-600'}`}>
                                            {opt}
                                        </button>
                                    ))}
                                </div>
                                <button onClick={() => startTransition(async () => await handleVote())} disabled={!isConnected || isWrongNetwork || isSyncing || isTxConfirming || isPending} className="w-full py-3 bg-blue-600 hover:bg-blue-700 text-white transition-colors rounded-xl text-sm font-medium shadow-sm disabled:opacity-50 disabled:cursor-not-allowed">
                                    {isWrongNetwork ? 'Switch Network First' : !isConnected ? 'Connect Wallet First' : isSyncing ? 'Syncing...' : isPending ? 'Processing...' : 'Generate ZK Proof & Vote'}
                                </button>
                            </div>
                        )}

                        {currentPollState === 0 && localIdentity && (
                            <div className="pt-6 border-t border-slate-100">
                                <div className="inline-flex items-center gap-2 px-4 py-2 bg-amber-50 border border-amber-200 text-amber-700 rounded-xl text-sm font-medium">
                                    Registration Phase -- Voting has not started yet
                                </div>
                            </div>
                        )}

                        {currentPollState === 2 && (
                            <div className="pt-6 border-t border-slate-100">
                                <div className="inline-flex items-center gap-2 px-4 py-2 bg-slate-100 border border-slate-200 text-slate-700 rounded-xl text-sm font-medium">
                                    Poll Closed
                                </div>
                                <p className="text-sm text-slate-500 mt-3">The poll has concluded. The final tally is shown on the right.</p>
                            </div>
                        )}
                    </div>
                </section>

                {/* RIGHT COLUMN */}
                <section className="flex flex-col gap-8">
                    {/* LIVE POLL STATUS */}
                    <div className="bg-white border border-slate-200 rounded-3xl p-8 shadow-sm">
                        <h2 className="text-xl font-semibold mb-6 text-slate-900 border-b border-slate-100 pb-4">Live Overview</h2>

                        <div className="flex gap-2 mb-8 bg-slate-50 p-1.5 rounded-xl border border-slate-200">
                            <div className={`flex-1 py-2 text-center rounded-lg text-xs font-medium transition-colors ${currentPollState === 0 ? 'bg-white shadow-sm text-blue-600 border border-slate-200' : 'text-slate-500'}`}>Registration</div>
                            <div className={`flex-1 py-2 text-center rounded-lg text-xs font-medium transition-colors ${currentPollState === 1 ? 'bg-white shadow-sm text-blue-600 border border-slate-200' : 'text-slate-500'}`}>Voting</div>
                            <div className={`flex-1 py-2 text-center rounded-lg text-xs font-medium transition-colors ${currentPollState === 2 ? 'bg-white shadow-sm text-blue-600 border border-slate-200' : 'text-slate-500'}`}>Closed</div>
                        </div>

                        {/* Dynamic Options + Counts */}
                        {pollOptions.length > 0 && (
                            <div className="space-y-5">
                                {pollOptions.map((opt, i) => {
                                    const count = voteCounts[i] || 0
                                    const pct = totalVotes > 0 ? (count / totalVotes) * 100 : 0
                                    const color = optionColors[i % optionColors.length]
                                    return (
                                        <div key={i}>
                                            <div className="flex justify-between items-end mb-2">
                                                <span className="text-slate-700 font-medium text-sm">{opt}</span>
                                                <span className="text-2xl font-bold text-slate-900">{count}</span>
                                            </div>
                                            <div className="w-full bg-slate-100 rounded-full h-2 overflow-hidden">
                                                <div className={`${color} h-2 rounded-full transition-all duration-500`} style={{ width: `${pct}%` }}></div>
                                            </div>
                                        </div>
                                    )
                                })}
                                {totalVotes > 0 && (
                                    <p className="text-xs text-slate-400 mt-2">Total votes: {totalVotes}</p>
                                )}
                            </div>
                        )}

                        {pollOptions.length === 0 && (
                            <p className="text-sm text-slate-400">No options configured yet.</p>
                        )}
                    </div>

                    {/* ADMIN CONTROLS (CONDITIONAL) */}
                    {isAdmin && (
                        <div className="bg-white border border-rose-200 rounded-3xl p-8 shadow-sm relative overflow-hidden">
                            <h2 className="text-xs font-bold mb-5 text-rose-500 uppercase tracking-widest flex items-center gap-2">
                                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" /><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" /></svg>
                                Admin Organizer
                            </h2>

                            {/* Poll Lifecycle */}
                            <div className="flex flex-col sm:flex-row gap-3 mb-6">
                                <button onClick={handleStartVoting} disabled={currentPollState !== 0 || !isConnected || isWrongNetwork} className="flex-1 py-2 bg-rose-50 hover:bg-rose-100 text-rose-700 transition border border-rose-200 rounded-xl text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed">
                                    Start Voting
                                </button>
                                <button onClick={handleEndVoting} disabled={currentPollState !== 1 || !isConnected || isWrongNetwork} className="flex-1 py-2 bg-rose-50 hover:bg-rose-100 text-rose-700 transition border border-rose-200 rounded-xl text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed">
                                    Close Poll
                                </button>
                            </div>

                            {/* Manage Options (Registration only) */}
                            {currentPollState === 0 && (
                                <div className="mb-6 border-t border-rose-100 pt-5">
                                    <h3 className="text-sm font-semibold text-rose-700 mb-3">Manage Options</h3>
                                    <div className="mb-3 space-y-1">
                                        {pollOptions.map((opt, i) => (
                                            <div key={i} className="flex items-center gap-2 px-3 py-2 bg-rose-50 rounded-lg text-sm text-rose-800 border border-rose-100">
                                                <span className="w-5 h-5 rounded-full bg-rose-200 text-rose-700 text-xs flex items-center justify-center font-bold">{i + 1}</span>
                                                {opt}
                                            </div>
                                        ))}
                                    </div>
                                    <div className="flex gap-2">
                                        <input type="text" placeholder="New option label" value={newOptionLabel} onChange={e => setNewOptionLabel(e.target.value)} className="flex-1 bg-white border border-rose-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-rose-400" />
                                        <button onClick={() => startTransition(async () => await handleAddOption())} disabled={!newOptionLabel.trim() || !isConnected || isWrongNetwork || isPending} className="px-4 py-2 bg-rose-600 hover:bg-rose-700 text-white rounded-xl text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed">
                                            {isPending ? '...' : '+ Add'}
                                        </button>
                                    </div>
                                </div>
                            )}

                            {/* Generate Tokens (Registration only) */}
                            {currentPollState === 0 && (
                                <div className="border-t border-rose-100 pt-5">
                                    <h3 className="text-sm font-semibold text-rose-700 mb-3">Generate Vote Tokens</h3>
                                    <p className="text-xs text-rose-400 mb-3">Create anonymous invite tokens and auto-register them on-chain. Distribute token strings privately to voters.</p>
                                    <div className="flex gap-2 mb-4">
                                        <input type="number" min={1} max={50} value={tokenCount} onChange={e => setTokenCount(Number(e.target.value))} className="w-20 bg-white border border-rose-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-rose-400 text-center" />
                                        <button onClick={() => startTransition(async () => await handleGenerateTokens())} disabled={!isConnected || isWrongNetwork || isPending} className="flex-1 py-2 bg-rose-600 hover:bg-rose-700 text-white rounded-xl text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed">
                                            {isPending ? 'Generating...' : `Generate ${tokenCount} Tokens`}
                                        </button>
                                    </div>

                                    {generatedTokens.length > 0 && (
                                        <div className="bg-slate-900 rounded-xl p-4 max-h-60 overflow-y-auto">
                                            <div className="flex justify-between items-center mb-3">
                                                <span className="text-xs text-slate-400 font-bold uppercase tracking-wider">Invite Tokens (distribute privately)</span>
                                                <button
                                                    onClick={() => { navigator.clipboard.writeText(generatedTokens.join('\n')); setStatusMsg("All tokens copied to clipboard!") }}
                                                    className="text-xs bg-slate-700 hover:bg-slate-600 text-slate-200 px-3 py-1 rounded-lg transition-colors"
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
                    )}
                </section>
            </main>
        </div>
    )
}
