import { useState, useEffect } from 'react'
import { useAccount, useConnect, useDisconnect, useReadContract, useWriteContract, useWaitForTransactionReceipt, useChainId, useSwitchChain } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { Identity } from '@semaphore-protocol/identity'
import { Group } from '@semaphore-protocol/group'
import { generateProof } from '@semaphore-protocol/proof'
import ZKVotingABI from './ZkVotingLottery.json'
import { CONTRACT_ADDRESS } from './config'
import { keccak256, toBytes } from 'viem'

// Hardcoded Group details simulating an offchain tracker 
// In a production app, the frontend would query events to build this tree precisely
const group = new Group()

export default function App() {
  const { address, isConnected } = useAccount()
  const { connectors, connect } = useConnect()
  const { disconnect } = useDisconnect()
  const chainId = useChainId()
  const { switchChain } = useSwitchChain()

  const isWrongNetwork = isConnected && chainId !== hardhat.id && chainId !== localhost.id

  const [localIdentity, setLocalIdentity] = useState<Identity | null>(null)
  const [candidate, setCandidate] = useState<number>(1)
  const [statusMsg, setStatusMsg] = useState<string>("")
  const [claimAddress, setClaimAddress] = useState<string>("")

  // --- Contract Reads ---
  const { data: pollState } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: ZKVotingABI.abi,
    functionName: 'state',
  })

  const { data: voteCountA } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: ZKVotingABI.abi,
    functionName: 'voteCounts',
    args: [1],
  })

  const { data: voteCountB } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: ZKVotingABI.abi,
    functionName: 'voteCounts',
    args: [2],
  })

  const { data: winningNullifier } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: ZKVotingABI.abi,
    functionName: 'winningNullifier',
  })

  const currentPollState = pollState !== undefined ? Number(pollState) : -1;

  // --- Contract Writes ---
  const { data: hash, writeContractAsync } = useWriteContract()
  const { isLoading: isTxConfirming, isSuccess: isTxSuccess } = useWaitForTransactionReceipt({ hash })

  useEffect(() => {
    // Load existing identity from local storage
    const saved = localStorage.getItem('semaphore-identity')
    if (saved) {
      const id = new Identity(saved)
      setLocalIdentity(id)

      // Attempt to add it to our off-chain group tracker if it exists
      // Wait, in a real app we'd fetch ALL past `VoterRegistered` events to populate the group
      try { group.addMember(id.commitment) } catch (e) { }
    }
  }, [])

  const generateIdentity = () => {
    const newId = new Identity()
    localStorage.setItem('semaphore-identity', newId.privateKey.toString())
    setLocalIdentity(newId)
    setStatusMsg("Identity generated and saved to browser storage secretly.")
  }

  const handleRegister = async () => {
    if (!localIdentity) return
    try {
      setStatusMsg("Confirming registration transaction...")
      await writeContractAsync({
        address: CONTRACT_ADDRESS,
        abi: ZKVotingABI.abi,
        functionName: 'registerVoter',
        args: [localIdentity.commitment],
      })
      group.addMember(localIdentity.commitment)
    } catch (e: any) {
      console.error(e)
      setStatusMsg(`Registration Error: ${e.shortMessage || e.message}`)
    }
  }

  const handleVote = async () => {
    if (!localIdentity) return
    try {
      setStatusMsg("Generating Zero-Knowledge Proof... (Heavy computation)")

      // Scope is the contract address
      const scope = CONTRACT_ADDRESS

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
        address: CONTRACT_ADDRESS,
        abi: ZKVotingABI.abi,
        functionName: 'castVote',
        args: [candidate, proofStruct],
      })

      localStorage.setItem('my-nullifier', fullProof.nullifier.toString())
      setStatusMsg("Voted Successfully! Your anonymity is guaranteed.")
    } catch (e: any) {
      console.error(e)
      setStatusMsg(`Voting Error: ${e.shortMessage || e.message}`)
    }
  }

  const handleClaim = async () => {
    if (!localIdentity || !claimAddress) return
    try {
      setStatusMsg("Generating Claim Zero-Knowledge Proof... (Heavy computation)")

      // Same scope as hardcoded in the contract
      const claimScope = BigInt(keccak256(toBytes("CLAIM_PRIZE_SCOPE")));
      const claimSignal = BigInt(claimAddress);

      const claimProof = await generateProof(localIdentity, group, claimSignal, claimScope)

      const proofStruct = {
        merkleTreeDepth: claimProof.merkleTreeDepth,
        merkleTreeRoot: claimProof.merkleTreeRoot,
        nullifier: claimProof.nullifier,
        message: claimProof.message,
        scope: claimProof.scope,
        points: claimProof.points
      }

      setStatusMsg("Submitting Claim ZKP...")
      await writeContractAsync({
        address: CONTRACT_ADDRESS,
        abi: ZKVotingABI.abi,
        functionName: 'claimPrize',
        args: [claimAddress, proofStruct],
      })

      setStatusMsg("Prize Claimed successfully to your new anonymous address!")
    } catch (e: any) {
      console.error(e)
      setStatusMsg(`Claim Error: ${e.shortMessage || e.message}`)
    }
  }

  // Admin actions
  const handleStartVoting = async () => {
    try {
      await writeContractAsync({ address: CONTRACT_ADDRESS, abi: ZKVotingABI.abi, functionName: 'startVoting' })
    } catch (e) { console.error(e) }
  }

  const handleEndVoting = async () => {
    try {
      await writeContractAsync({ address: CONTRACT_ADDRESS, abi: ZKVotingABI.abi, functionName: 'endVotingAndDrawLottery' })
    } catch (e) { console.error(e) }
  }


  return (
    <div className="min-h-screen bg-gray-950 text-white p-8 font-sans selection:bg-fuchsia-500 selection:text-white">
      <div className="max-w-4xl mx-auto">
        <header className="flex justify-between items-center mb-12">
          <div>
            <h1 className="text-4xl font-extrabold tracking-tight bg-gradient-to-r from-teal-400 to-indigo-500 bg-clip-text text-transparent">
              ZK Ballot & Lottery
            </h1>
            <p className="text-gray-400 mt-2 text-sm">Provably fair and permanently anonymous.</p>
          </div>

          <div>
            {!isConnected ? (
              <div className="flex gap-2">
                {connectors.map((connector) => (
                  <button
                    key={connector.uid}
                    onClick={() => connect({ connector })}
                    className="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 transition-colors rounded-lg font-medium shadow-lg shadow-indigo-500/20"
                  >
                    Connect {connector.name}
                  </button>
                ))}
              </div>
            ) : isWrongNetwork ? (
              <div className="flex items-center gap-4">
                <button
                  onClick={() => switchChain({ chainId: hardhat.id })}
                  className="px-4 py-2 bg-red-600 hover:bg-red-500 text-white transition-colors rounded-lg font-bold shadow-lg shadow-red-500/20 shadow-pulse flex items-center gap-2"
                >
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>
                  Switch to Hardhat Network
                </button>
                <button
                  onClick={() => disconnect()}
                  className="px-3 py-1 bg-gray-800 hover:bg-gray-700 transition-colors rounded-lg text-sm text-gray-400 font-medium"
                >
                  Disconnect
                </button>
              </div>
            ) : (
              <div className="flex items-center gap-4">
                <div className="text-sm px-3 py-1 bg-gray-800 rounded-full border border-gray-700 font-mono">
                  {address?.slice(0, 6)}...{address?.slice(-4)}
                </div>
                <button
                  onClick={() => disconnect()}
                  className="px-3 py-1 bg-red-500/10 hover:bg-red-500/20 text-red-500 transition-colors rounded-lg text-sm font-medium"
                >
                  Disconnect
                </button>
              </div>
            )}
          </div>
        </header>

        {statusMsg && (
          <div className="mb-8 p-4 bg-gray-900 border border-gray-800 rounded-xl flex items-center gap-3">
            <div className="h-2 w-2 bg-teal-400 rounded-full animate-pulse"></div>
            <p className="text-gray-300 text-sm font-medium">{statusMsg}</p>
          </div>
        )}

        {isTxConfirming && <p className="mb-4 text-yellow-400 text-sm animate-pulse">Transaction pending...</p>}
        {isTxSuccess && <p className="mb-4 text-emerald-400 text-sm">Transaction confirmed!</p>}

        <main className="grid grid-cols-1 md:grid-cols-2 gap-8">
          {/* USER PANEL */}
          <section className="bg-gray-900 border border-gray-800 rounded-2xl p-6 shadow-2xl">
            <h2 className="text-2xl font-bold mb-6 text-gray-100 flex items-center gap-2">
              <span className="bg-gray-800 p-2 rounded-lg">👤</span> Voter Dashboard
            </h2>

            <div className="space-y-6">
              <div className="p-4 bg-gray-950 rounded-xl border border-gray-800">
                <h3 className="font-semibold text-gray-300 mb-2">1. Identity (Zero-Knowledge)</h3>
                <p className="text-xs text-gray-500 mb-4 line-clamp-2">Your private key stays strictly in your browser. It is mathematically impossible to link your identity to your vote.</p>
                {localIdentity ? (
                  <div className="text-emerald-400 text-sm font-medium flex items-center gap-2">
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" /></svg>
                    Identity Ready
                  </div>
                ) : (
                  <button onClick={generateIdentity} className="w-full py-2 bg-gray-800 hover:bg-gray-700 transition rounded-lg text-sm">
                    Generate Local Identity
                  </button>
                )}
              </div>

              {localIdentity && currentPollState === 0 && (
                <div className="p-4 bg-indigo-500/10 border border-indigo-500/20 rounded-xl">
                  <h3 className="font-semibold text-indigo-300 mb-2">2. Register to Vote</h3>
                  <button onClick={handleRegister} disabled={!isConnected || isWrongNetwork} className="w-full py-2 bg-indigo-600 hover:bg-indigo-500 transition rounded-lg text-sm shadow-lg shadow-indigo-600/20 disabled:opacity-50 disabled:cursor-not-allowed">
                    {isWrongNetwork ? 'Switch Network First' : !isConnected ? 'Connect Wallet First' : 'Submit Commitment On-chain'}
                  </button>
                </div>
              )}

              {localIdentity && currentPollState === 1 && (
                <div className="p-4 bg-fuchsia-500/10 border border-fuchsia-500/20 rounded-xl">
                  <h3 className="font-semibold text-fuchsia-300 mb-2">3. Cast Vote Anonymously</h3>
                  <div className="flex gap-2 mb-4">
                    <button onClick={() => setCandidate(1)} className={`flex-1 py-2 rounded-lg text-sm transition ${candidate === 1 ? 'bg-fuchsia-600 shadow-lg shadow-fuchsia-600/20' : 'bg-gray-800 hover:bg-gray-700'}`}>Candidate A</button>
                    <button onClick={() => setCandidate(2)} className={`flex-1 py-2 rounded-lg text-sm transition ${candidate === 2 ? 'bg-fuchsia-600 shadow-lg shadow-fuchsia-600/20' : 'bg-gray-800 hover:bg-gray-700'}`}>Candidate B</button>
                  </div>
                  <button onClick={handleVote} disabled={!isConnected || isWrongNetwork} className="w-full py-3 bg-fuchsia-600 hover:bg-fuchsia-500 transition rounded-lg text-sm font-bold tracking-wide disabled:opacity-50 disabled:cursor-not-allowed">
                    {isWrongNetwork ? 'Switch Network First' : !isConnected ? 'Connect Wallet First' : 'Generate Proof & Vote'}
                  </button>
                </div>
              )}

              {currentPollState === 2 && typeof winningNullifier === 'bigint' && (
                <div className="p-4 bg-amber-500/10 border border-amber-500/20 rounded-xl">
                  <h3 className="font-semibold text-amber-300 mb-2">🎉 Lottery Results</h3>
                  <p className="text-xs text-gray-400 mb-2 break-all">Winning Nullifier Hash: <span className="font-mono text-amber-200">{winningNullifier.toString()}</span></p>

                  {localStorage.getItem('my-nullifier') === winningNullifier.toString() ? (
                    <div className="mt-4">
                      <p className="text-sm font-bold text-amber-400 mb-2">You won! Provide a fresh address:</p>
                      <input type="text" placeholder="0x..." value={claimAddress} onChange={e => setClaimAddress(e.target.value)} className="w-full bg-gray-950 border border-gray-800 rounded-lg px-3 py-2 text-sm mb-3 focus:outline-none focus:border-amber-500" />
                      <button onClick={handleClaim} disabled={!isConnected || isWrongNetwork} className="w-full py-2 bg-amber-600 hover:bg-amber-500 transition rounded-lg text-sm shadow-lg shadow-amber-600/20 text-white font-bold disabled:opacity-50 disabled:cursor-not-allowed">
                        {isWrongNetwork ? 'Switch Network First' : !isConnected ? 'Connect Wallet First' : 'Verify & Claim Prize'}
                      </button>
                    </div>
                  ) : (
                    <p className="text-sm text-gray-500">You did not win this time, but your privacy remains 100% intact.</p>
                  )}
                </div>
              )}
            </div>
          </section>

          {/* ADMIN & STATE PANEL */}
          <section className="flex flex-col gap-8">
            <div className="bg-gray-900 border border-gray-800 rounded-2xl p-6 shadow-2xl">
              <h2 className="text-xl font-bold mb-4 text-gray-100">Live Poll Status</h2>
              <div className="flex gap-4 mb-6">
                <div className={`flex-1 p-3 rounded-lg text-center text-sm border ${currentPollState === 0 ? 'border-teal-500 bg-teal-500/10 text-teal-400' : 'border-gray-800 text-gray-600'}`}>Registration</div>
                <div className={`flex-1 p-3 rounded-lg text-center text-sm border ${currentPollState === 1 ? 'border-fuchsia-500 bg-fuchsia-500/10 text-fuchsia-400' : 'border-gray-800 text-gray-600'}`}>Voting</div>
                <div className={`flex-1 p-3 rounded-lg text-center text-sm border ${currentPollState === 2 ? 'border-indigo-500 bg-indigo-500/10 text-indigo-400' : 'border-gray-800 text-gray-600'}`}>Closed</div>
              </div>

              <div className="bg-gray-950 rounded-xl p-4 border border-gray-800">
                <div className="flex justify-between items-center mb-3">
                  <span className="text-gray-400 text-sm">Candidate A</span>
                  <span className="text-2xl font-mono text-gray-100">{voteCountA !== undefined ? Number(voteCountA) : '-'}</span>
                </div>
                <div className="w-full bg-gray-900 rounded-full h-2">
                  <div className="bg-teal-400 h-2 rounded-full" style={{ width: `${voteCountA ? Math.min((Number(voteCountA) / (Number(voteCountA) + Number(voteCountB) + 0.01)) * 100, 100) : 0}%` }}></div>
                </div>

                <div className="flex justify-between items-center mt-6 mb-3">
                  <span className="text-gray-400 text-sm">Candidate B</span>
                  <span className="text-2xl font-mono text-gray-100">{voteCountB !== undefined ? Number(voteCountB) : '-'}</span>
                </div>
                <div className="w-full bg-gray-900 rounded-full h-2">
                  <div className="bg-fuchsia-400 h-2 rounded-full" style={{ width: `${voteCountB ? Math.min((Number(voteCountB) / (Number(voteCountA) + Number(voteCountB) + 0.01)) * 100, 100) : 0}%` }}></div>
                </div>
              </div>
            </div>

            <div className="bg-red-950/20 border border-red-900/30 rounded-2xl p-6 relative overflow-hidden">
              <div className="absolute top-0 right-0 p-2 opacity-10 text-4xl">⚙️</div>
              <h2 className="text-sm font-bold mb-4 text-red-400 uppercase tracking-widest">Admin Controls</h2>
              <div className="flex gap-3">
                <button onClick={handleStartVoting} disabled={currentPollState !== 0 || !isConnected || isWrongNetwork} className="flex-1 py-2 bg-red-900/50 hover:bg-red-800/80 text-red-200 transition rounded-lg text-xs font-medium border border-red-700/50 disabled:opacity-50 disabled:cursor-not-allowed">
                  Start Voting
                </button>
                <button onClick={handleEndVoting} disabled={currentPollState !== 1 || !isConnected || isWrongNetwork} className="flex-1 py-2 bg-red-900/50 hover:bg-red-800/80 text-red-200 transition rounded-lg text-xs font-medium border border-red-700/50 disabled:opacity-50 disabled:cursor-not-allowed">
                  Close & Draw Lottery
                </button>
              </div>
            </div>
          </section>

        </main>
      </div>
    </div>
  )
}
