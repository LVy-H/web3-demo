import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import IZkPollABI from '../abi/IZkPoll.json'

export function usePollState(pollAddress: `0x${string}`) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'getState',
        query: { refetchInterval: 2000 },
    })
}

export function usePollOptions(pollAddress: `0x${string}`) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'getOptions',
        query: { refetchInterval: 5000 },
    })
}

export function usePollResults(pollAddress: `0x${string}`) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'getResults',
        query: { refetchInterval: 3000 },
    })
}

export function usePollOwner(pollAddress: `0x${string}`) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'owner',
    })
}

export function useParticipantCount(pollAddress: `0x${string}`) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'getParticipantCount',
        query: { refetchInterval: 3000 },
    })
}

export function useVerifyParticipation(pollAddress: `0x${string}`, nullifierHash: bigint | undefined) {
    return useReadContract({
        address: pollAddress,
        abi: IZkPollABI.abi,
        functionName: 'verifyParticipation',
        args: nullifierHash !== undefined ? [nullifierHash] : undefined,
        query: { enabled: nullifierHash !== undefined },
    })
}

export function usePollWrite() {
    const { data: hash, mutateAsync, isPending } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })
    return { mutateAsync, isPending, isConfirming, isSuccess, hash }
}
