import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import ZkBlindVotingABI from '../abi/ZkBlindVoting.json'

export function useBlindPollRevealDeadline(pollAddress: `0x${string}`) {
  return useReadContract({
    address: pollAddress,
    abi: ZkBlindVotingABI.abi,
    functionName: 'getRevealDeadline',
    query: { refetchInterval: 5000 },
  })
}

export function useBlindPollFinalized(pollAddress: `0x${string}`) {
  return useReadContract({
    address: pollAddress,
    abi: ZkBlindVotingABI.abi,
    functionName: 'isFinalized',
    query: { refetchInterval: 3000 },
  })
}

export function useHasVoted(pollAddress: `0x${string}`, voter: `0x${string}` | undefined) {
  return useReadContract({
    address: pollAddress,
    abi: ZkBlindVotingABI.abi,
    functionName: 'hasVoted',
    args: voter ? [voter] : undefined,
    query: { enabled: !!voter, refetchInterval: 3000 },
  })
}

export function useHasRevealed(pollAddress: `0x${string}`, voter: `0x${string}` | undefined) {
  return useReadContract({
    address: pollAddress,
    abi: ZkBlindVotingABI.abi,
    functionName: 'hasRevealed',
    args: voter ? [voter] : undefined,
    query: { enabled: !!voter, refetchInterval: 3000 },
  })
}

export function useBlindPollWrite() {
  const { data: hash, mutateAsync, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })
  return { mutateAsync, isPending, isConfirming, isSuccess, hash, error }
}
