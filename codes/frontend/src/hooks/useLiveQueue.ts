import { useCallback, useEffect, useRef, useState } from 'react'
import { usePublicClient, useWriteContract } from 'wagmi'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'
import { fetchQueue, redeemTicket, type PendingVoter } from '../lib/liveRelay'

/**
 * useLiveQueue — the organizer host's view of the pending-voter queue (S1.4)
 * plus the on-chain confirm flow (S1.6).
 *
 * Polls the relayer queue every 2s (degrades to empty + error if the relayer is
 * down, so the page still renders). `remove` is a client-side Reject (no chain
 * call). `confirmVoter` registers the voter on-chain FROM THE ORGANIZER'S OWN
 * WALLET (registerVoter is onlyOwner), waits for that specific tx receipt, then
 * marks the relayer ticket consumed. The voter's page enables only after the
 * registration is mined (it reads registeredCommitments on-chain) — never on
 * tx-send. registerVoter only works in the Registration phase.
 */
const POLL_INTERVAL_MS = 2000
const REGISTER_GAS = 15_000_000n

export interface UseLiveQueueResult {
  queue: PendingVoter[]
  isLoading: boolean
  error: string | null
  refresh: () => Promise<void>
  remove: (commitment: string) => void
  confirmVoter: (voter: PendingVoter) => Promise<void>
  confirmingCommitment: string | null
}

function isAlreadyRegistered(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err)
  return /AlreadyRegistered/i.test(msg)
}

export function useLiveQueue(pollAddress: `0x${string}` | undefined): UseLiveQueueResult {
  const publicClient = usePublicClient()
  const { writeContractAsync } = useWriteContract()
  const [queue, setQueue] = useState<PendingVoter[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [confirmingCommitment, setConfirmingCommitment] = useState<string | null>(null)
  // Commitments rejected locally — filtered out so a Reject sticks across polls.
  const rejected = useRef<Set<string>>(new Set())

  const refresh = useCallback(async () => {
    if (!pollAddress) return
    setIsLoading(true)
    try {
      const voters = await fetchQueue(pollAddress)
      setQueue(voters.filter((v) => !rejected.current.has(v.ephemeralIdentityCommitment)))
      setError(null)
    } catch (err) {
      // Degrade: keep the page usable, surface the error.
      setError(err instanceof Error ? err.message : 'Relayer unavailable')
      setQueue([])
    } finally {
      setIsLoading(false)
    }
  }, [pollAddress])

  useEffect(() => {
    rejected.current = new Set()
    if (!pollAddress) return
    let active = true
    const tick = () => {
      if (active) void refresh()
    }
    tick()
    const id = setInterval(tick, POLL_INTERVAL_MS)
    return () => {
      active = false
      clearInterval(id)
    }
  }, [pollAddress, refresh])

  const remove = useCallback((commitment: string) => {
    rejected.current.add(commitment)
    setQueue((q) => q.filter((v) => v.ephemeralIdentityCommitment !== commitment))
  }, [])

  const confirmVoter = useCallback(
    async (voter: PendingVoter) => {
      if (!pollAddress || !publicClient) throw new Error('Wallet/chain not ready')
      const commitment = BigInt(voter.ephemeralIdentityCommitment)
      setConfirmingCommitment(voter.ephemeralIdentityCommitment)
      try {
        let mined = false
        try {
          const hash = await writeContractAsync({
            address: pollAddress,
            abi: ZkAnonVotingABI.abi,
            functionName: 'registerVoter',
            args: [commitment],
            gas: REGISTER_GAS,
          })
          await publicClient.waitForTransactionReceipt({ hash })
          mined = true
        } catch (err) {
          // Idempotent: a retry of an already-registered voter is success, as
          // long as the chain confirms the commitment really is registered.
          if (!isAlreadyRegistered(err)) throw err
          const reg = (await publicClient.readContract({
            address: pollAddress,
            abi: ZkAnonVotingABI.abi,
            functionName: 'registeredCommitments',
            args: [commitment],
          })) as boolean
          if (!reg) throw err
          mined = true
        }
        if (mined) {
          await redeemTicket(pollAddress, voter.ticket)
          await refresh()
        }
      } finally {
        setConfirmingCommitment(null)
      }
    },
    [pollAddress, publicClient, writeContractAsync, refresh],
  )

  return { queue, isLoading, error, refresh, remove, confirmVoter, confirmingCommitment }
}
