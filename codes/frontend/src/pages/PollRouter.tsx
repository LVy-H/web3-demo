import { useParams } from 'react-router-dom'
import { useReadContract } from 'wagmi'
import { REGISTRY_ADDRESS } from '../config'
import PollRegistryABI from '../abi/PollRegistry.json'
import Poll from './Poll'
import BlindPoll from './BlindPoll'

function LoadingSkeleton() {
    return (
        <div className="space-y-6 animate-pulse">
            {/* Header skeleton */}
            <div className="flex items-center justify-between">
                <div className="h-4 w-28 bg-stone-200 dark:bg-stone-700 rounded-lg" />
                <div className="flex items-center gap-2">
                    <div className="h-6 w-24 bg-stone-200 dark:bg-stone-700 rounded-full" />
                    <div className="h-6 w-28 bg-stone-200 dark:bg-stone-700 rounded-lg" />
                </div>
            </div>
            {/* Progress bar skeleton */}
            <div className="bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm px-6 py-5">
                <div className="flex items-center gap-4">
                    <div className="w-8 h-8 rounded-full bg-stone-200 dark:bg-stone-700" />
                    <div className="flex-1 h-1 bg-stone-200 dark:bg-stone-700 rounded-full" />
                    <div className="w-8 h-8 rounded-full bg-stone-200 dark:bg-stone-700" />
                    <div className="flex-1 h-1 bg-stone-200 dark:bg-stone-700 rounded-full" />
                    <div className="w-8 h-8 rounded-full bg-stone-200 dark:bg-stone-700" />
                </div>
            </div>
            {/* Trust signal skeleton */}
            <div className="bg-teal-50 dark:bg-teal-900/20 border border-teal-200 dark:border-teal-800 rounded-xl px-5 py-4">
                <div className="h-4 w-3/4 bg-teal-200 dark:bg-teal-800 rounded-lg" />
            </div>
            {/* Main grid skeleton */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div className="bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6 space-y-4">
                    <div className="h-5 w-24 bg-stone-200 dark:bg-stone-700 rounded-lg" />
                    <div className="h-4 w-full bg-stone-200 dark:bg-stone-700 rounded-lg" />
                    <div className="h-10 w-full bg-stone-200 dark:bg-stone-700 rounded-xl" />
                </div>
                <div className="bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm p-6 space-y-4">
                    <div className="h-5 w-28 bg-stone-200 dark:bg-stone-700 rounded-lg" />
                    <div className="space-y-3">
                        <div className="h-3 w-full bg-stone-200 dark:bg-stone-700 rounded-full" />
                        <div className="h-3 w-4/5 bg-stone-200 dark:bg-stone-700 rounded-full" />
                        <div className="h-3 w-3/5 bg-stone-200 dark:bg-stone-700 rounded-full" />
                    </div>
                </div>
            </div>
        </div>
    )
}

export default function PollRouter() {
    const { address } = useParams<{ address: string }>()

    // Find this poll's module type from the registry
    const { data: polls } = useReadContract({
        address: REGISTRY_ADDRESS,
        abi: PollRegistryABI.abi,
        functionName: 'getAllPolls',
    })

    const pollList = (polls as Array<{ pollAddress: string; moduleType: string }>) || []
    const thisPoll = pollList.find(
        (p) => p.pollAddress.toLowerCase() === address?.toLowerCase()
    )

    if (!thisPoll) {
        return <LoadingSkeleton />
    }

    if (thisPoll.moduleType === 'blind-vote') {
        return <BlindPoll />
    }

    return <Poll />
}
