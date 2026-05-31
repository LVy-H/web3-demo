import { useEffect, useMemo, useRef, useState } from 'react'
import { useParams, useSearchParams } from 'react-router-dom'
import { useChainId, usePublicClient, useReadContract } from 'wagmi'
import { isAddress, parseAbiItem } from 'viem'
import { Identity } from '@semaphore-protocol/identity'
import { Group } from '@semaphore-protocol/group'
import { generateProof } from '@semaphore-protocol/proof'
import { RefreshCw, Clock, CheckCircle2 } from 'lucide-react'
import { decodeTicket } from '../lib/ticket'
import { confirmationCode } from '../lib/confirmationCode'
import { postPending } from '../lib/liveRelay'
import { friendlyError } from '../lib/pollErrors'
import { useRelayVote } from '../hooks/useRelay'
import { usePollOptions, usePollState } from '../hooks/usePoll'
import { ConfirmationCode } from '../components/live/ConfirmationCode'
import { ReceiptModal, type VoterReceipt } from '../components/poll/ReceiptModal'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'

const REGISTRATION = 0
const ENDED = 2

function FreshCodeNotice({ message }: { message: string }) {
  return (
    <div className="max-w-md mx-auto mt-16 text-center space-y-4">
      <Clock className="w-10 h-10 text-db-segnale mx-auto" />
      <h1 className="font-sans font-extrabold text-[24px] uppercase text-db-chalk">Code expired</h1>
      <p className="font-mono text-[13px] text-db-mute leading-relaxed">{message}</p>
      <p className="font-mono text-[12px] text-db-mute inline-flex items-center gap-2">
        <RefreshCw className="w-4 h-4" /> Scan the projected QR again for a fresh code.
      </p>
    </div>
  )
}

export default function LiveVote() {
  const { pollId: pollIdParam } = useParams<{ pollId: string }>()
  const [params] = useSearchParams()
  const ticket = params.get('t') ?? ''
  const pollId = (pollIdParam ?? '') as `0x${string}`
  const valid = isAddress(pollId)

  const publicClient = usePublicClient()
  const chainId = useChainId()
  const { relayVote } = useRelayVote()

  // One ephemeral Semaphore identity per page mount (no wallet, never persisted
  // to a real account). A reload mints a fresh one → re-scan for a fresh code.
  const [identity] = useState(() => new Identity())
  const commitment = identity.commitment

  const decoded = useMemo(() => {
    try {
      return ticket ? decodeTicket(ticket) : null
    } catch {
      return null
    }
  }, [ticket])
  const code = decoded ? confirmationCode(decoded.n, commitment) : ''

  const [ticketError, setTicketError] = useState<string | null>(null)
  const posted = useRef(false)

  // Announce ourselves to the relayer queue once (fresh ticket required). The
  // relayer authoritatively verifies the ticket signature AND expiry; we just
  // surface its verdict — setState lands in the async .then callback, not
  // synchronously in the effect body.
  useEffect(() => {
    if (posted.current || !valid || !decoded) return
    posted.current = true
    void postPending(pollId, ticket, commitment.toString(), code).then((r) => {
      if (!r.ok) {
        setTicketError(
          r.status === 409 ? 'This code was already used.' : 'This code has expired or is invalid.',
        )
      }
    })
  }, [valid, decoded, pollId, ticket, commitment, code])

  // Three-state gate: registeredCommitments(commitment) AND getState().
  const { data: regData } = useReadContract({
    address: valid ? pollId : undefined,
    abi: ZkAnonVotingABI.abi,
    functionName: 'registeredCommitments',
    args: [commitment],
    query: { enabled: valid && !ticketError, refetchInterval: 3000 },
  })
  const registered = Boolean(regData)
  const { data: stateData } = usePollState(valid ? pollId : ('0x' as `0x${string}`))
  const phase = typeof stateData === 'number' ? stateData : Number(stateData ?? -1)
  const { data: optionsData } = usePollOptions(valid ? pollId : ('0x' as `0x${string}`))
  const options = (optionsData as string[] | undefined) ?? []

  const [selectedOption, setSelectedOption] = useState<number | null>(null)
  const [voting, setVoting] = useState(false)
  const [status, setStatus] = useState('')
  const [receipt, setReceipt] = useState<VoterReceipt | null>(null)

  async function handleVote() {
    if (selectedOption === null || !publicClient) return
    setVoting(true)
    setStatus('Generating zero-knowledge proof… this can take 10–30s.')
    try {
      // Build the group from on-chain registrations — only valid now, after
      // registration has closed and the Merkle root is frozen.
      const logs = await publicClient.getLogs({
        address: pollId,
        event: parseAbiItem('event VoterRegistered(uint256 identityCommitment)'),
        fromBlock: 0n,
      })
      const group = new Group()
      const seen = new Set<string>()
      for (const log of logs) {
        const c = log.args.identityCommitment
        if (c === undefined || c === null) continue
        const key = c.toString()
        if (seen.has(key)) continue
        seen.add(key)
        group.addMember(BigInt(key))
      }
      if (group.indexOf(commitment) === -1) {
        throw new Error('Your identity is not registered yet. Wait for the organizer to confirm you.')
      }

      const proof = await generateProof(identity, group, selectedOption, pollId)
      setStatus('Submitting your vote via the relayer…')
      const result = await relayVote(pollId, selectedOption, proof)
      if (!result.success || !result.txHash) throw new Error(result.error || 'Relay failed')

      const txReceipt = await publicClient.waitForTransactionReceipt({ hash: result.txHash })
      if (txReceipt.status !== 'success') throw new Error('Vote reverted on-chain.')

      setReceipt({
        pollAddress: pollId,
        pollTitle: 'Live Meeting Poll',
        nullifier: proof.nullifier.toString(),
        txHash: result.txHash,
        blockNumber: txReceipt.blockNumber,
        timestamp: Date.now(),
        optionLabel: options[selectedOption] ?? `Option #${selectedOption + 1}`,
        chainId,
        appOrigin: window.location.origin,
      })
      setStatus('')
    } catch (e) {
      setStatus(friendlyError(e))
    } finally {
      setVoting(false)
    }
  }

  if (!valid) return <FreshCodeNotice message="This voting link is malformed." />
  if (!ticket || !decoded || ticketError) {
    return <FreshCodeNotice message={ticketError ?? 'This voting code has expired.'} />
  }

  // State 1 — waiting for the organizer to confirm (register on-chain).
  if (!registered) {
    return (
      <div className="max-w-md mx-auto mt-12 space-y-8 text-center">
        <ConfirmationCode code={code} />
        <p className="font-mono text-[12px] text-db-mute inline-flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-db-segnale animate-pulse" />
          Waiting for the organizer to confirm you…
        </p>
      </div>
    )
  }

  // State 2 — confirmed, but voting hasn't opened yet (registerVoter done,
  // startVoting not yet). Showing options here would revert (NotInVoting).
  if (registered && phase === REGISTRATION) {
    return (
      <div className="max-w-md mx-auto mt-16 text-center space-y-4">
        <CheckCircle2 className="w-10 h-10 text-db-segnale mx-auto" />
        <h1 className="font-sans font-extrabold text-[22px] uppercase text-db-chalk">You're confirmed</h1>
        <p className="font-mono text-[13px] text-db-mute leading-relaxed">
          Waiting for the organizer to open voting. Your ballot will appear here automatically.
        </p>
      </div>
    )
  }

  if (phase === ENDED) {
    return (
      <div className="max-w-md mx-auto mt-16 text-center">
        <h1 className="font-sans font-extrabold text-[22px] uppercase text-db-chalk">Voting has ended</h1>
      </div>
    )
  }

  // State 3 — registered AND voting open → show the ballot.
  return (
    <div className="max-w-md mx-auto mt-10 space-y-6">
      <header className="text-center">
        <h1 className="font-sans font-extrabold text-[26px] uppercase text-db-chalk">Cast your vote</h1>
        <p className="font-mono text-[11px] text-db-mute mt-1">Anonymous · zero-knowledge · no wallet</p>
      </header>

      <div className="flex flex-col gap-px bg-db-rule">
        {options.map((opt, i) => (
          <button
            key={i}
            type="button"
            disabled={voting}
            onClick={() => setSelectedOption(i)}
            className={`text-left px-5 py-4 font-sans font-extrabold text-[16px] uppercase tracking-[0.04em] transition-colors disabled:opacity-50 cursor-pointer ${
              selectedOption === i ? 'bg-db-segnale text-db-void' : 'bg-db-void text-db-chalk hover:bg-db-slate'
            }`}
          >
            <span className="font-mono text-[12px] mr-3 opacity-70">{String(i + 1).padStart(2, '0')}</span>
            {opt}
          </button>
        ))}
      </div>

      <button
        type="button"
        disabled={selectedOption === null || voting}
        onClick={handleVote}
        data-testid="cast-vote"
        className="w-full min-h-[52px] bg-db-segnale text-db-void font-sans font-extrabold text-[14px] tracking-[0.2em] uppercase disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
      >
        {voting ? 'Working…' : 'Cast vote'}
      </button>

      {status && <p className="font-mono text-[12px] text-db-mute text-center leading-relaxed">{status}</p>}

      {receipt && <ReceiptModal receipt={receipt} onClose={() => setReceipt(null)} />}
    </div>
  )
}
