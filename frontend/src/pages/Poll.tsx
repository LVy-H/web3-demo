import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt, useChainId } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { Identity } from '@semaphore-protocol/identity'
import { Group } from '@semaphore-protocol/group'
import { generateProof } from '@semaphore-protocol/proof'
import ZKVotingABI from '../ZkVoting.json'

const group = new Group()

function loadSavedIdentity(): Identity | null {
    try {
        const saved = localStorage.getItem('semaphore-identity')
        if (!saved) return null
        const id = new Identity(saved)
        try {
            group.addMember(id.commitment)
        } catch (e: unknown) {
            const msg = e instanceof Error ? e.message : String(e)
            if (!msg.includes('already')) console.warn('Group.addMember:', msg)
        }
        return id
    } catch {
        return null
    }
}

export default function Poll() {
    const { address: pollAddress } = useParams()
    const { isConnected } = useAccount()
    const chainId = useChainId()

    const isWrongNetwork = isConnected && chainId !== hardhat.id && chainId !== localhost.id

    const [localIdentity, setLocalIdentity] = useState<Identity | null>(loadSavedIdentity)
    const [candidate, setCandidate] = useState<number>(1)
    const [statusMsg, setStatusMsg] = useState<string>("")
    const [inviteToken, setInviteToken] = useState<string>("")
    const [adminTokens, setAdminTokens] = useState<string>("")

    // --- Contract Reads ---
    const { data: pollOwner } = useReadContract({
        address: pollAddress as `0x${string}`,
        abi: ZKVotingABI.abi,
        functionName: 'owner',
    })

    const { data: pollState } = useReadContract({
        address: pollAddress as `0x${string}`,
        abi: ZKVotingABI.abi,
        functionName: 'state',
        query: { refetchInterval: 2000 },
    })

    const { data: voteCountA } = useReadContract({
        address: pollAddress as `0x${string}`,
        abi: ZKVotingABI.abi,
        functionName: 'voteCounts',
        args: [1],
        query: { refetchInterval: 2000 },
    })

    const { data: voteCountB } = useReadContract({
        address: pollAddress as `0x${string}`,
        abi: ZKVotingABI.abi,
        functionName: 'voteCounts',
        args: [2],
        query: { refetchInterval: 2000 },
    })

    const currentPollState = pollState !== undefined ? Number(pollState) : -1;
    const { address } = useAccount();
    const isAdmin = pollOwner === address;

    // --- Contract Writes ---
    const { data: hash, mutateAsync: writeContractAsync } = useWriteContract()
    const { isLoading: isTxConfirming, isSuccess: isTxSuccess } = useWaitForTransactionReceipt({ hash })

    const loadIdentityFromToken = () => {
        if (!inviteToken) return;
        try {
            const newId = new Identity(inviteToken);
            localStorage.setItem('semaphore-identity', newId.privateKey.toString());
            setLocalIdentity(newId);
            setStatusMsg("Identity loaded successfully from Invite Token.");
        } catch {
            setStatusMsg("Invalid Invite Token.");
        }
    }

    const handleRegister = async () => {
        if (!localIdentity || !pollAddress) return
        try {
            setStatusMsg("Confirming registration transaction...")
            await writeContractAsync({
                address: pollAddress as `0x${string}`,
                abi: ZKVotingABI.abi,
                functionName: 'registerVoter',
                args: [localIdentity.commitment],
            })
            group.addMember(localIdentity.commitment)
        } catch (e: unknown) {
            console.error(e)
            const err = e as { shortMessage?: string; message?: string }
            setStatusMsg(`Registration Error: ${err.shortMessage ?? err.message ?? String(e)}`)
        }
    }

    const handleVote = async () => {
        if (!localIdentity || !pollAddress) return
        try {
            setStatusMsg("Generating Zero-Knowledge Proof... (Heavy computation)")

            const scope = pollAddress as `0x${string}`
            const fullProof = await generateProof(localIdentity, group, candidate, scope)

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
                address: pollAddress as `0x${string}`,
                abi: ZKVotingABI.abi,
                functionName: 'castVote',
                args: [candidate, proofStruct],
            })

            localStorage.setItem('my-nullifier', fullProof.nullifier.toString())
            setStatusMsg("Voted Successfully! Your anonymity is guaranteed.")
        } catch (e: unknown) {
            console.error(e)
            const err = e as { shortMessage?: string; message?: string }
            setStatusMsg(`Voting Error: ${err.shortMessage ?? err.message ?? String(e)}`)
        }
    }

    const handleBatchRegister = async () => {
        if (!pollAddress) return;
        try {
            setStatusMsg("Confirming batch registration transaction...")
            const commitments = JSON.parse(adminTokens)
            await writeContractAsync({
                address: pollAddress as `0x${string}`,
                abi: ZKVotingABI.abi,
                functionName: 'registerVoters',
                args: [commitments],
            })
            commitments.forEach((c: string) => group.addMember(c))
            setStatusMsg("Batch registration submitted successfully.")
        } catch (e: unknown) {
            console.error(e)
            const err = e as { shortMessage?: string; message?: string }
            setStatusMsg(`Batch Register Error: ${err.shortMessage ?? err.message ?? String(e)}`)
        }
    }

    // Admin actions
    const handleStartVoting = async () => {
        if (!pollAddress) return;
        try {
            await writeContractAsync({ address: pollAddress as `0x${string}`, abi: ZKVotingABI.abi, functionName: 'startVoting' })
        } catch (e) { console.error(e) }
    }

    const handleEndVoting = async () => {
        if (!pollAddress) return;
        try {
            await writeContractAsync({ address: pollAddress as `0x${string}`, abi: ZKVotingABI.abi, functionName: 'endVoting' })
        } catch (e) { console.error(e) }
    }

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
                                <div className="inline-flex items-center gap-2 px-4 py-2 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-xl text-sm font-medium">
                                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" /></svg>
                                    Identity Ready
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

                        {localIdentity && currentPollState === 0 && (
                            <div className="pt-6 border-t border-slate-100">
                                <h3 className="text-sm font-medium text-slate-900 mb-3">2. Register to Vote</h3>
                                <button onClick={handleRegister} disabled={!isConnected || isWrongNetwork} className="w-full py-3 bg-slate-900 hover:bg-slate-800 text-white transition-colors rounded-xl text-sm font-medium shadow-sm disabled:opacity-50 disabled:cursor-not-allowed">
                                    {isWrongNetwork ? 'Switch Network First' : !isConnected ? 'Connect Wallet First' : 'Submit Commitment On-chain'}
                                </button>
                            </div>
                        )}

                        {localIdentity && currentPollState === 1 && (
                            <div className="pt-6 border-t border-slate-100">
                                <h3 className="text-sm font-medium text-slate-900 mb-3">3. Cast Vote Anonymously</h3>
                                <div className="flex gap-3 mb-5">
                                    <button onClick={() => setCandidate(1)} className={`flex-1 py-3 rounded-xl border-2 transition-all ${candidate === 1 ? 'border-blue-600 bg-blue-50 text-blue-700 font-semibold' : 'border-slate-200 hover:border-slate-300 text-slate-600'}`}>Candidate A</button>
                                    <button onClick={() => setCandidate(2)} className={`flex-1 py-3 rounded-xl border-2 transition-all ${candidate === 2 ? 'border-blue-600 bg-blue-50 text-blue-700 font-semibold' : 'border-slate-200 hover:border-slate-300 text-slate-600'}`}>Candidate B</button>
                                </div>
                                <button onClick={handleVote} disabled={!isConnected || isWrongNetwork} className="w-full py-3 bg-blue-600 hover:bg-blue-700 text-white transition-colors rounded-xl text-sm font-medium shadow-sm disabled:opacity-50 disabled:cursor-not-allowed">
                                    {isWrongNetwork ? 'Switch Network First' : !isConnected ? 'Connect Wallet First' : 'Generate ZK Proof & Vote'}
                                </button>
                            </div>
                        )}

                        {currentPollState === 2 && (
                            <div className="pt-6 border-t border-slate-100">
                                <div className="inline-flex items-center gap-2 px-4 py-2 bg-slate-100 border border-slate-200 text-slate-700 rounded-xl text-sm font-medium">
                                    🎉 Poll Closed
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

                        <div className="space-y-6">
                            <div>
                                <div className="flex justify-between items-end mb-2">
                                    <span className="text-slate-700 font-medium text-sm">Candidate A</span>
                                    <span className="text-2xl font-bold text-slate-900">{voteCountA !== undefined ? Number(voteCountA) : '-'}</span>
                                </div>
                                <div className="w-full bg-slate-100 rounded-full h-2 overflow-hidden">
                                    <div className="bg-blue-500 h-2 rounded-full transition-all duration-500" style={{ width: `${voteCountA ? Math.min((Number(voteCountA) / (Number(voteCountA) + Number(voteCountB) + 0.01)) * 100, 100) : 0}%` }}></div>
                                </div>
                            </div>

                            <div>
                                <div className="flex justify-between items-end mb-2">
                                    <span className="text-slate-700 font-medium text-sm">Candidate B</span>
                                    <span className="text-2xl font-bold text-slate-900">{voteCountB !== undefined ? Number(voteCountB) : '-'}</span>
                                </div>
                                <div className="w-full bg-slate-100 rounded-full h-2 overflow-hidden">
                                    <div className="bg-indigo-400 h-2 rounded-full transition-all duration-500" style={{ width: `${voteCountB ? Math.min((Number(voteCountB) / (Number(voteCountA) + Number(voteCountB) + 0.01)) * 100, 100) : 0}%` }}></div>
                                </div>
                            </div>
                        </div>
                    </div>

                    {/* ADMIN CONTROLS (CONDITIONAL) */}
                    {isAdmin && (
                        <div className="bg-white border border-rose-200 rounded-3xl p-8 shadow-sm relative overflow-hidden">
                            <h2 className="text-xs font-bold mb-5 text-rose-500 uppercase tracking-widest flex items-center gap-2">
                                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" /><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" /></svg>
                                Admin Organizer
                            </h2>
                            <div className="flex flex-col sm:flex-row gap-3 mb-5">
                                <button onClick={handleStartVoting} disabled={currentPollState !== 0 || !isConnected || isWrongNetwork} className="flex-1 py-2 bg-rose-50 hover:bg-rose-100 text-rose-700 transition border border-rose-200 rounded-xl text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed">
                                    Start Voting
                                </button>
                                <button onClick={handleEndVoting} disabled={currentPollState !== 1 || !isConnected || isWrongNetwork} className="flex-1 py-2 bg-rose-50 hover:bg-rose-100 text-rose-700 transition border border-rose-200 rounded-xl text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed">
                                    Close Poll
                                </button>
                            </div>
                            <textarea placeholder="Paste JSON array of commitments to batch register" value={adminTokens} onChange={e => setAdminTokens(e.target.value)} className="w-full h-24 bg-slate-50 border border-rose-200 rounded-xl p-3 text-xs text-slate-600 mb-3 focus:outline-none focus:ring-2 focus:ring-rose-500 font-mono resize-none transition-shadow" />
                            <button onClick={handleBatchRegister} disabled={currentPollState !== 0 || !isConnected || isWrongNetwork} className="w-full py-2.5 bg-rose-600 hover:bg-rose-700 text-white transition rounded-xl text-sm font-medium shadow-sm disabled:opacity-50 disabled:cursor-not-allowed">
                                Batch Register Commitments
                            </button>
                        </div>
                    )}
                </section>
            </main>
        </div>
    )
}
