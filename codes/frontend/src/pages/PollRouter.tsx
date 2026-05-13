import { useParams, Link } from 'react-router-dom'
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
    const { data: polls, isLoading, isError } = useReadContract({
        address: REGISTRY_ADDRESS,
        abi: PollRegistryABI.abi,
        functionName: 'getAllPolls',
    })

    const pollList = (polls as Array<{ pollAddress: string; moduleType: string }>) || []
    const thisPoll = pollList.find(
        (p) => p.pollAddress.toLowerCase() === address?.toLowerCase()
    )

    if (isLoading) {
        return <LoadingSkeleton />
    }

    if (isError || (polls !== undefined && !thisPoll)) {
        return (
            <div className="max-w-lg mx-auto mt-16 p-8 bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-700 rounded-xl shadow-sm text-center space-y-4">
                <h2 className="text-lg font-bold text-stone-900 dark:text-stone-100">Poll Not Found</h2>
                <p className="text-sm text-stone-500 dark:text-stone-400">
                    This poll does not exist or the system has been restarted. Polls are reset when the blockchain node restarts.
                </p>
                <Link
                    to="/"
                    className="inline-block px-5 py-2.5 bg-teal-600 hover:bg-teal-700 text-white rounded-xl text-sm font-medium transition-colors"
                >
                    Back to Dashboard
                </Link>
            </div>
        )
    }

    if (!thisPoll) {
        return <LoadingSkeleton />
    }

    if (thisPoll.moduleType === 'blind-vote') {
        return <BlindPoll />
    }

    return <Poll />
}
