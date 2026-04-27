import {
    useReadContract,
    useWatchContractEvent,
    useWriteContract,
    useWaitForTransactionReceipt,
} from 'wagmi'
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

/**
 * Hybrid event-driven poll list (P4-22).
 *
 * Initial data comes from a single `getAllPolls()` view call (so we get
 * full PollInfo including `description` and `createdAt`, which are NOT in
 * the `PollCreated` event). After mount, we listen for `PollCreated` and
 * trigger a single `refetch()` whenever a new poll is created. No more
 * 5-second polling between events.
 *
 * Tradeoff vs full client-side log reconstruction: each event costs one
 * extra `getAllPolls` round-trip instead of zero, but we avoid maintaining
 * a separate Map<address, PollInfo> and don't need a contract change to
 * surface description / createdAt. Acceptable until the registry grows
 * large enough that `getAllPolls` itself needs pagination (P4-21).
 */
export function useAllPolls() {
    const result = useReadContract({
        address: REGISTRY_ADDRESS,
        abi: PollRegistryABI.abi,
        functionName: 'getAllPolls',
        // No refetchInterval — we listen to PollCreated events instead.
    })

    useWatchContractEvent({
        address: REGISTRY_ADDRESS,
        abi: PollRegistryABI.abi,
        eventName: 'PollCreated',
        onLogs() {
            result.refetch()
        },
    })

    return result
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
