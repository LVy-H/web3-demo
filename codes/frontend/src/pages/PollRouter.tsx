import { useParams } from 'react-router-dom'
import { useReadContract } from 'wagmi'
import { REGISTRY_ADDRESS } from '../config'
import PollRegistryABI from '../abi/PollRegistry.json'
import Poll from './Poll'
import BlindPoll from './BlindPoll'

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
    return <div className="text-center py-20 text-slate-500">Loading poll...</div>
  }

  if (thisPoll.moduleType === 'blind-vote') {
    return <BlindPoll />
  }

  return <Poll />
}
