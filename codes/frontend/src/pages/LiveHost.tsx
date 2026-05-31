import { useCallback, useMemo, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useAccount, usePublicClient, useWriteContract } from 'wagmi'
import { isAddress } from 'viem'
import { ArrowLeft, Play, Square, AlertTriangle } from 'lucide-react'
import { usePollOwner, usePollState } from '../hooks/usePoll'
import { useLiveQueue } from '../hooks/useLiveQueue'
import { getOrCreateOrgKeypair } from '../lib/orgKeypair'
import { createTicketPayload, signTicket } from '../lib/ticket'
import type { PendingVoter } from '../lib/liveRelay'
import { RotatingQR } from '../components/live/RotatingQR'
import { PendingVoterList } from '../components/live/PendingVoterList'
import { LiveTally } from '../components/live/LiveTally'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'

// PollState enum (IZkPoll): 0 Registration · 1 Voting · 2 Ended
const REGISTRATION = 0
const VOTING = 1
const ENDED = 2

const PHASE_LABEL: Record<number, string> = {
  [REGISTRATION]: 'Registration',
  [VOTING]: 'Voting',
  [ENDED]: 'Ended',
}

export default function LiveHost() {
  const { pollId: pollIdParam } = useParams<{ pollId: string }>()
  const pollId = (pollIdParam ?? '') as `0x${string}`
  const valid = isAddress(pollId)

  const { address } = useAccount()
  const publicClient = usePublicClient()
  const { writeContractAsync } = useWriteContract()

  const { data: ownerData } = usePollOwner(valid ? pollId : ('0x' as `0x${string}`))
  const { data: stateData } = usePollState(valid ? pollId : ('0x' as `0x${string}`))
  const phase = typeof stateData === 'number' ? stateData : Number(stateData ?? -1)

  const isOwner =
    !!address && !!ownerData && address.toLowerCase() === (ownerData as string).toLowerCase()

  const { queue, error, remove, confirmVoter, confirmingCommitment } = useLiveQueue(valid ? pollId : undefined)
  const [actionError, setActionError] = useState<string | null>(null)
  const [transitioning, setTransitioning] = useState<string | null>(null)

  // Per-poll ed25519 ticket-signing key (distinct from the MetaMask wallet).
  const orgKey = useMemo(() => (valid ? getOrCreateOrgKeypair(pollId) : null), [valid, pollId])
  const makeTicket = useCallback(() => {
    if (!orgKey) throw new Error('no org key')
    const payload = createTicketPayload(pollId, Math.floor(Date.now() / 1000))
    return signTicket(payload, orgKey.privKey)
  }, [orgKey, pollId])

  const onConfirm = useCallback(
    async (voter: PendingVoter) => {
      setActionError(null)
      try {
        await confirmVoter(voter)
      } catch (e) {
        setActionError(e instanceof Error ? e.message : 'Failed to register voter')
      }
    },
    [confirmVoter],
  )

  const transition = useCallback(
    async (fn: 'startVoting' | 'endVoting') => {
      if (!publicClient) return
      setActionError(null)
      setTransitioning(fn)
      try {
        const hash = await writeContractAsync({
          address: pollId,
          abi: ZkAnonVotingABI.abi,
          functionName: fn,
        })
        await publicClient.waitForTransactionReceipt({ hash })
      } catch (e) {
        const err = e as { shortMessage?: string; message?: string }
        setActionError(err.shortMessage ?? err.message ?? 'Transaction failed')
      } finally {
        setTransitioning(null)
      }
    },
    [publicClient, writeContractAsync, pollId],
  )

  if (!valid) {
    return (
      <div className="py-16 text-center font-mono text-db-mute">
        Invalid poll address in URL.
        <div className="mt-4">
          <Link to="/" className="text-db-segnale underline">Back to dashboard</Link>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Breadcrumb + phase banner */}
      <div className="flex items-center justify-between gap-2 py-4 border-b border-db-rule">
        <Link to="/" className="text-db-mute hover:text-db-chalk font-mono text-[11px] tracking-[0.16em] uppercase flex items-center gap-1.5">
          <ArrowLeft className="w-3.5 h-3.5" /> Dashboard
        </Link>
        <span
          data-testid="phase-label"
          className="font-mono text-[11px] tracking-[0.18em] uppercase px-3 py-1 border border-db-rule text-db-segnale"
        >
          {PHASE_LABEL[phase] ?? '—'}
        </span>
      </div>

      <header>
        <h1 className="font-sans font-extrabold text-[clamp(28px,4vw,48px)] leading-none tracking-[-0.02em] text-db-chalk uppercase">
          Live Meeting
        </h1>
        <p className="font-mono text-[11px] text-db-mute mt-2 break-all">{pollId}</p>
      </header>

      {!isOwner && (
        <div className="bg-db-slate border-l-2 border-db-segnale p-5 flex items-start gap-3">
          <AlertTriangle className="w-4 h-4 text-db-segnale shrink-0 mt-0.5" />
          <p className="font-mono text-[12px] text-db-mute leading-relaxed">
            Connect the organizer wallet that <strong className="text-db-chalk">owns this poll</strong> to run the meeting.
            The host controls (confirm voters, start/end voting) are hidden until then.
          </p>
        </div>
      )}

      {error && (
        <p className="font-mono text-[11px] text-db-mute">Relayer: {error} — queue paused, page still live.</p>
      )}
      {actionError && (
        <p className="font-mono text-[12px] text-db-segnale" data-testid="host-error">{actionError}</p>
      )}

      {isOwner && phase === REGISTRATION && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          {/* QR */}
          <section className="bg-db-void p-6 flex flex-col items-center gap-6">
            <RotatingQR pollId={pollId} makeTicket={makeTicket} />
            <button
              type="button"
              disabled={transitioning !== null}
              onClick={() => transition('startVoting')}
              data-testid="start-voting"
              className="inline-flex items-center gap-2 min-h-[44px] px-6 bg-db-segnale text-db-void font-sans font-extrabold text-[13px] tracking-[0.18em] uppercase disabled:opacity-50 cursor-pointer"
            >
              <Play className="w-4 h-4" />
              {transitioning === 'startVoting' ? 'Opening…' : 'Start Voting'}
            </button>
            <p className="font-mono text-[10px] text-db-mute text-center max-w-[280px] leading-relaxed">
              Confirm everyone present first. Once voting opens, no new voters can be added.
            </p>
          </section>
          {/* Queue */}
          <section className="bg-db-void p-6 space-y-4">
            <h2 className="font-mono text-[11px] text-db-mute tracking-[0.18em] uppercase">Pending voters</h2>
            <PendingVoterList
              voters={queue}
              onConfirm={onConfirm}
              onReject={remove}
              confirmingCommitment={confirmingCommitment}
              canConfirm={isOwner && phase === REGISTRATION}
            />
          </section>
        </div>
      )}

      {(phase === VOTING || phase === ENDED) && (
        <section className="bg-db-void p-6 space-y-6">
          <div className="flex items-center justify-between">
            <h2 className="font-mono text-[11px] text-db-mute tracking-[0.18em] uppercase">
              {phase === VOTING ? 'Live tally' : 'Final results'}
            </h2>
            {isOwner && phase === VOTING && (
              <button
                type="button"
                disabled={transitioning !== null}
                onClick={() => transition('endVoting')}
                data-testid="end-voting"
                className="inline-flex items-center gap-2 min-h-[44px] px-6 bg-db-slate text-db-chalk border border-db-rule font-sans font-extrabold text-[12px] tracking-[0.18em] uppercase disabled:opacity-50 cursor-pointer"
              >
                <Square className="w-4 h-4" />
                {transitioning === 'endVoting' ? 'Ending…' : 'End Voting'}
              </button>
            )}
          </div>
          <LiveTally pollAddress={pollId} />
        </section>
      )}
    </div>
  )
}
