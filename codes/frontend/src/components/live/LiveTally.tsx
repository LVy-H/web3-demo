import { useWatchContractEvent } from 'wagmi'
import { usePollOptions, usePollResults } from '../../hooks/usePoll'
import { ResultsBarsDb } from '../poll/ResultsBarsDb'
import ZkAnonVotingABI from '../../abi/ZkAnonVoting.json'

interface Props {
  pollAddress: `0x${string}`
}

/**
 * LiveTally (S1.4) — real-time bars on the projector. Seeds from getResults and
 * refetches on every VoteCast event (the http transport polls, so we trigger a
 * refetch rather than incrementing locally — avoids double-counting on
 * reconnect; same pattern as useRegistry). A 3s poll backstops missed events.
 */
export function LiveTally({ pollAddress }: Props) {
  const { data: optionsData } = usePollOptions(pollAddress)
  const results = usePollResults(pollAddress)

  useWatchContractEvent({
    address: pollAddress,
    abi: ZkAnonVotingABI.abi,
    eventName: 'VoteCast',
    onLogs() {
      void results.refetch()
    },
  })

  const pollOptions = (optionsData as string[] | undefined) ?? []
  const voteCounts = ((results.data as readonly bigint[] | undefined) ?? []).map((n) => Number(n))
  const totalVotes = voteCounts.reduce((a, b) => a + b, 0)

  return <ResultsBarsDb pollOptions={pollOptions} voteCounts={voteCounts} totalVotes={totalVotes} />
}
