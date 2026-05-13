import { useState, useEffect, useTransition } from 'react'
import { useParams } from 'react-router-dom'
import { useAccount, useChainId, usePublicClient } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { Identity } from '@semaphore-protocol/identity'
import { generateProof } from '@semaphore-protocol/proof'
import { Clock, Key, Check } from 'lucide-react'
import { usePollState, usePollOptions, usePollResults, usePollOwner, usePollWrite } from '../hooks/usePoll'
import { useGroupSync } from '../hooks/useGroupSync'
import { useRelayVote } from '../hooks/useRelay'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'
import { friendlyError } from '../lib/pollErrors'
import { PollHeader } from '../components/poll/PollHeader'
import { PhaseStrip } from '../components/poll/PhaseStrip'
import { PollStatusBanner } from '../components/poll/PollStatusBanner'
import { IdentityCard } from '../components/poll/IdentityCard'
import { VoteShowdownCard } from '../components/poll/VoteShowdownCard'
import { ResultsBarsDb } from '../components/poll/ResultsBarsDb'
import { PrivacyReceiptPanel } from '../components/poll/PrivacyReceiptPanel'
import { AdminPanel } from '../components/poll/AdminPanel'

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

/* -- Phase gate (small inline component) ---------------------------------- */

function PhaseGate({
    icon: Icon,
    iconTone,
    title,
    body,
}: {
    icon: typeof Clock
    iconTone: string
    title: string
    body: string
}) {
    return (
        <div className="bg-db-slate border-l-2 border-db-rule p-5 flex items-start gap-4">
            <div className="w-10 h-10 border border-db-rule flex items-center justify-center flex-shrink-0">
                <Icon className={`w-5 h-5 ${iconTone}`} />
            </div>
            <div className="min-w-0">
                <p className="font-sans font-extrabold text-[14px] tracking-[0.02em] text-db-chalk uppercase">
                    {title}
                </p>
                <p className="font-mono text-[11px] text-db-mute leading-relaxed mt-1">
                    {body}
                </p>
            </div>
        </div>
    )
}

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
        // Sweep legacy unscoped nullifier key for returning voters who re-loaded
        // their identity token (the new key is `my-nullifier-${pollAddress}-${commitment}`).
        localStorage.removeItem(`my-nullifier-${pollAddress}`)
        const nullifier = localStorage.getItem(`my-nullifier-${pollAddress}-${id.commitment.toString()}`)
        setHasVoted(Boolean(nullifier))
    }, [pollAddress])

    const [selectedOption, setSelectedOption] = useState<number | null>(null)
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
        if (selectedOption === null) return
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
        if (selectedOption === null) return
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

    const copyAllTokens = () => {
        navigator.clipboard.writeText(generatedTokens.join('\n'))
        setStatus("All tokens copied to clipboard!", 'success')
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

    const onCastVote = () => startTransition(async () => {
        if (useRelay) await handleRelayVote()
        else await handleVote()
    })

    const onClearIdentity = () => {
        localStorage.removeItem(`semaphore-identity-${pollAddress}`)
        // Clear both the legacy unscoped key and the identity-scoped key for
        // the currently-loaded identity. Other identities' scoped flags on
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
    }

    /* -- Render ----------------------------------------------------------- */

    return (
        <div className="space-y-6">
            <PollHeader pollAddress={pollAddress} />

            {currentPollState >= 0 && <PhaseStrip current={currentPollState} />}

            <PollStatusBanner
                msg={statusMsg}
                type={statusType}
                isTxConfirming={isTxConfirming}
                isTxSuccess={isTxSuccess}
            />

            <main className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* ======== LEFT COLUMN: Voter Panel ======== */}
                <section className="space-y-6">
                    <IdentityCard
                        localIdentity={localIdentity}
                        inviteToken={inviteToken}
                        onInviteTokenChange={setInviteToken}
                        onLoadIdentity={loadIdentityFromToken}
                        onClearIdentity={onClearIdentity}
                        pollAddress={pollAddress}
                    />

                    {localIdentity && currentPollState === 1 && !hasVoted && (
                        <VoteShowdownCard
                            pollOptions={pollOptions}
                            selectedOption={selectedOption}
                            onSelectOption={setSelectedOption}
                            voteCounts={voteCounts}
                            totalVotes={totalVotes}
                            useRelay={useRelay}
                            onSetUseRelay={setUseRelay}
                            onCast={onCastVote}
                            voteButtonLabel={voteButtonLabel()}
                            voteDisabled={voteDisabled}
                            voteHintText={voteButtonLabel()}
                            pollAddress={pollAddress}
                        />
                    )}

                    {hasVoted && currentPollState === 1 && (
                        <PrivacyReceiptPanel variant="post-vote" />
                    )}

                    {currentPollState === 0 && localIdentity && (
                        <PhaseGate
                            icon={Clock}
                            iconTone="text-db-oltremare"
                            title="Registration Phase"
                            body="Voting has not started yet. The poll admin is still registering voters and configuring options."
                        />
                    )}

                    {currentPollState === 0 && !localIdentity && (
                        <PhaseGate
                            icon={Key}
                            iconTone="text-db-mute"
                            title="No Identity Loaded"
                            body="Enter your invite token above to load your anonymous identity."
                        />
                    )}

                    {currentPollState === 1 && !localIdentity && (
                        <PhaseGate
                            icon={Key}
                            iconTone="text-db-segnale"
                            title="Voting is Open"
                            body="Load your invite token above to cast your anonymous vote."
                        />
                    )}

                    {currentPollState === 2 && (
                        <PhaseGate
                            icon={Check}
                            iconTone="text-db-mute"
                            title="Poll Closed"
                            body="This poll has concluded. The final tally is shown in the results panel."
                        />
                    )}
                </section>

                {/* ======== RIGHT COLUMN: Info Panel ======== */}
                <section className="space-y-6">
                    <ResultsBarsDb
                        pollOptions={pollOptions}
                        voteCounts={voteCounts}
                        totalVotes={totalVotes}
                    />

                    {currentPollState === 2 && (
                        <PrivacyReceiptPanel variant="post-close" />
                    )}

                    {isAdmin && (
                        <AdminPanel
                            currentPollState={currentPollState}
                            isConnected={isConnected}
                            isWrongNetwork={isWrongNetwork}
                            isPending={isPending}
                            pollOptions={pollOptions}
                            newOptionLabel={newOptionLabel}
                            onChangeNewOptionLabel={setNewOptionLabel}
                            tokenCount={tokenCount}
                            onChangeTokenCount={setTokenCount}
                            generatedTokens={generatedTokens}
                            copiedIndex={copiedIndex}
                            onCopyToken={copyToken}
                            onCopyAllTokens={copyAllTokens}
                            onStartVoting={() => startTransition(async () => await handleStartVoting())}
                            onEndVoting={() => startTransition(async () => await handleEndVoting())}
                            onAddOption={() => startTransition(async () => await handleAddOption())}
                            onGenerateTokens={() => startTransition(async () => await handleGenerateTokens())}
                        />
                    )}
                </section>
            </main>
        </div>
    )
}
