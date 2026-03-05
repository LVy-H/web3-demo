import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { FACTORY_ADDRESS } from '../config'
import ZKVotingFactoryABI from '../ZkVotingFactory.json'

export default function Home() {
    const [title, setTitle] = useState('')
    const [description, setDescription] = useState('')

    interface PollData {
        pollAddress: string;
        title: string;
        description: string;
    }

    const { data: polls } = useReadContract({
        address: FACTORY_ADDRESS,
        abi: ZKVotingFactoryABI.abi,
        functionName: 'getAllPolls',
        query: { refetchInterval: 5000 },
    })

    const { data: hash, mutateAsync: writeContractAsync } = useWriteContract()
    const { isLoading: isTxConfirming, isSuccess: isTxSuccess } = useWaitForTransactionReceipt({ hash })

    const handleCreatePoll = async (e: React.FormEvent) => {
        e.preventDefault()
        if (!title || !description) return
        try {
            await writeContractAsync({
                address: FACTORY_ADDRESS as `0x${string}`,
                abi: ZKVotingFactoryABI.abi,
                functionName: 'createPoll',
                args: [title, description],
            })
            setTitle('')
            setDescription('')
        } catch (err) {
            console.error(err)
        }
    }

    const pollsArray = (polls as PollData[]) || []

    return (
        <div className="space-y-12">
            <section className="bg-white border border-slate-200 rounded-3xl p-8 shadow-sm">
                <h2 className="text-xl font-semibold mb-6 text-slate-900 border-b border-slate-100 pb-4 flex items-center gap-2">
                    Host a New Poll
                </h2>
                {isTxConfirming && <p className="text-amber-600 text-sm font-medium mb-4 animate-pulse">Creating poll transaction pending...</p>}
                {isTxSuccess && <p className="text-emerald-600 text-sm font-medium mb-4">Poll created successfully!</p>}

                <form onSubmit={handleCreatePoll} className="flex flex-col sm:flex-row gap-4">
                    <input
                        type="text"
                        placeholder="Poll Title (e.g., Q3 Board Election)"
                        value={title}
                        onChange={e => setTitle(e.target.value)}
                        className="flex-1 bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 text-sm text-slate-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        required
                    />
                    <input
                        type="text"
                        placeholder="Description..."
                        value={description}
                        onChange={e => setDescription(e.target.value)}
                        className="flex-1 bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 text-sm text-slate-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        required
                    />
                    <button type="submit" className="px-6 py-3 bg-slate-900 hover:bg-slate-800 text-white transition-colors rounded-xl text-sm font-medium shadow-sm whitespace-nowrap">
                        Create Poll
                    </button>
                </form>
            </section>

            <section>
                <h2 className="text-xl font-semibold mb-6 text-slate-900">Active Polls Dashboard</h2>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                    {pollsArray.length === 0 ? (
                        <div className="col-span-full text-center py-12 text-slate-500 border-2 border-dashed border-slate-200 rounded-3xl">
                            No polls have been created yet. Be the first!
                        </div>
                    ) : (
                        [...pollsArray].reverse().map((poll: PollData) => (
                            <Link
                                key={poll.pollAddress}
                                to={`/poll/${poll.pollAddress}`}
                                className="group p-6 bg-white border border-slate-200 rounded-3xl hover:border-blue-300 hover:shadow-md transition-all flex flex-col items-start gap-4"
                            >
                                <div>
                                    <h3 className="text-lg font-bold text-slate-900 group-hover:text-blue-600 transition-colors">{poll.title}</h3>
                                    <p className="text-sm text-slate-500 mt-1 line-clamp-2">{poll.description}</p>
                                </div>
                                <div className="mt-auto pt-4 border-t border-slate-100 w-full flex justify-between items-center">
                                    <span className="text-xs font-mono text-slate-400 bg-slate-50 px-2 py-1 rounded-md border border-slate-100">
                                        {poll.pollAddress.slice(0, 6)}...{poll.pollAddress.slice(-4)}
                                    </span>
                                    <span className="text-blue-600 text-sm font-medium group-hover:translate-x-1 transition-transform inline-flex items-center">
                                        Enter
                                        <svg className="w-4 h-4 ml-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" /></svg>
                                    </span>
                                </div>
                            </Link>
                        ))
                    )}
                </div>
            </section>
        </div>
    )
}
