import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { REGISTRY_ADDRESS } from '../config'
import PollRegistryABI from '../abi/PollRegistry.json'

export interface PollInfo {
    pollAddress: string;
    moduleType: string;
    title: string;
    description: string;
    creator: string;
    createdAt: bigint;
}

export function useAllPolls() {
    return useReadContract({
        address: REGISTRY_ADDRESS,
        abi: PollRegistryABI.abi,
        functionName: 'getAllPolls',
        query: { refetchInterval: 5000 },
    })
}

export function useCreatePoll() {
    const { data: hash, mutateAsync, isPending } = useWriteContract()
    const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

    async function createPoll(
        moduleType: string,
        title: string,
        description: string,
        initData: `0x${string}`
    ) {
        return mutateAsync({
            address: REGISTRY_ADDRESS,
            abi: PollRegistryABI.abi,
            functionName: 'createPoll',
            args: [moduleType, title, description, initData],
        })
    }

    return { createPoll, isPending, isConfirming, isSuccess, hash }
}
