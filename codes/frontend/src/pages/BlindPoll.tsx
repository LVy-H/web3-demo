import { useState, useTransition } from 'react'
import { useParams } from 'react-router-dom'
import { useAccount, useChainId } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'

import { usePollState, usePollOptions, usePollResults, usePollOwner, useParticipantCount } from '../hooks/usePoll'
import {
    useBlindPollRevealDeadline,
    useBlindPollFinalized,
    useHasVoted,
    useHasRevealed,
} from '../hooks/useBlindPoll'
import { useBlindVote } from '../hooks/useBlindVote'

import { StateProgress } from '../components/blindpoll/StateProgress'
import { RegisterCard } from '../components/blindpoll/RegisterCard'
import { CommitCard } from '../components/blindpoll/CommitCard'
import { RevealCard } from '../components/blindpoll/RevealCard'
import { AdminPanel } from '../components/blindpoll/AdminPanel'
import { ResultsBars } from '../components/blindpoll/ResultsBars'
import { PageHeader } from '../components/blindpoll/PageHeader'
import { StatusBanner, type StatusType } from '../components/blindpoll/StatusBanner'
import { TrustBanner, FinalizedCard, NotConnectedCard } from '../components/blindpoll/InfoCards'

export default function BlindPoll() {
    const { address: pollAddress } = useParams()
    const { address, isConnected } = useAccount()
    const chainId = useChainId()

    const isWrongNetwork = isConnected && chainId !== hardhat.id && chainId !== localhost.id
    const typedPollAddr = pollAddress as `0x${string}`
    const typedAddress = address as `0x${string}` | undefined

    const [selectedOption, setSelectedOption] = useState<number>(0)
    const [statusMsg, setStatusMsg] = useState('')
    const [statusType, setStatusType] = useState<StatusType>('info')
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

    const {
        commit, reveal, adminWrite,
        isTxConfirming, isTxSuccess,
        hasSavedCommit,
        friendlyError,
    } = useBlindVote({ pollAddress: typedPollAddr, hasCommitted })

    const setStatus = (msg: string, type: StatusType = 'info') => {
        setStatusMsg(msg); setStatusType(type)
    }

    // Wrap an async action with consistent status + error handling.
    const run = (pending: string, ok: string, fn: () => Promise<void>) => async () => {
        if (!pollAddress) return
        try { setStatus(pending); await fn(); setStatus(ok, 'success') }
        catch (e: unknown) {
            console.error(e)
            if (e instanceof Error && e.message === 'NO_SAVED_COMMIT') {
                setStatus('No saved commitment found in this browser. Did you commit from a different device?', 'error')
                return
            }
            setStatus(friendlyError(e), 'error')
        }
    }

    const handleRegister = run('Registering as voter...', 'Registered successfully! You can vote once voting starts.', () => adminWrite('register'))
    const handleCommitVote = run('Generating commitment...', 'Vote committed! Your choice is sealed until the reveal phase.', () => commit(selectedOption))
    const handleRevealVote = run('Revealing your vote...', 'Vote revealed successfully! Your choice is now counted.', () => reveal())
    const handleStartVoting = run('Starting voting phase...', 'Voting phase started!', () => adminWrite('startVoting'))
    const handleEndVoting = run('Ending voting phase...', 'Voting ended. Reveal window is now open.', () => adminWrite('endVoting'))
    const handleFinalizeResults = run('Finalizing results...', 'Results finalized!', () => adminWrite('finalizeResults'))
    const doAddOption = run('Adding option on-chain...', 'Option added successfully!', async () => {
        await adminWrite('addOption', [newOptionLabel.trim()])
        setNewOptionLabel(''); refetchOptions()
    })
    const handleAddOption = async () => { if (newOptionLabel.trim()) await doAddOption() }

    const voteDisabled = !isConnected || isWrongNetwork || isTxConfirming || isPending
    const isProcessing = isPending || isTxConfirming

    return (
        <div className="space-y-6">
            <PageHeader pollAddress={pollAddress} />

            {currentPollState >= 0 && (
                <div className="animate-fade-in-up animate-fade-in-up-1 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm px-6 py-5">
                    <StateProgress current={currentPollState} />
                </div>
            )}

            <TrustBanner />
            <StatusBanner msg={statusMsg} type={statusType} isTxConfirming={isTxConfirming} isTxSuccess={isTxSuccess} />

            <main className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <section className="space-y-6">
                    {currentPollState === 0 && (
                        <RegisterCard
                            participantCount={participantCount}
                            isConnected={isConnected}
                            isProcessing={isProcessing}
                            disabled={voteDisabled}
                            onRegister={() => startTransition(async () => await handleRegister())}
                        />
                    )}
                    {currentPollState === 1 && (
                        <CommitCard
                            pollOptions={pollOptions}
                            selectedOption={selectedOption}
                            onSelectOption={setSelectedOption}
                            onCommit={() => startTransition(async () => await handleCommitVote())}
                            hasCommitted={hasCommitted}
                            hasSavedCommit={hasSavedCommit}
                            isConnected={isConnected}
                            isProcessing={isProcessing}
                            disabled={voteDisabled}
                        />
                    )}
                    {currentPollState === 2 && !finalized && (
                        <RevealCard
                            revealDeadline={revealDeadline}
                            hasCommitted={hasCommitted}
                            hasRevealed={hasRevealed}
                            onReveal={() => startTransition(async () => await handleRevealVote())}
                            isProcessing={isProcessing}
                            disabled={voteDisabled}
                        />
                    )}
                    {currentPollState === 2 && finalized && <FinalizedCard />}
                    {!isConnected && currentPollState >= 0 && <NotConnectedCard />}
                </section>

                <section className="space-y-6">
                    <ResultsBars
                        pollOptions={pollOptions}
                        voteCounts={voteCounts}
                        totalVotes={totalVotes}
                        participantCount={participantCount}
                        currentPollState={currentPollState}
                        finalized={finalized}
                    />
                    {isAdmin && (
                        <AdminPanel
                            currentPollState={currentPollState}
                            finalized={finalized}
                            isConnected={isConnected}
                            isWrongNetwork={isWrongNetwork}
                            isPending={isPending}
                            pollOptions={pollOptions}
                            newOptionLabel={newOptionLabel}
                            onChangeNewOptionLabel={setNewOptionLabel}
                            onStartVoting={handleStartVoting}
                            onEndVoting={handleEndVoting}
                            onFinalizeResults={handleFinalizeResults}
                            onAddOption={() => startTransition(async () => await handleAddOption())}
                        />
                    )}
                </section>
            </main>
        </div>
    )
}
