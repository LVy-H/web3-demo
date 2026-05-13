/**
 * Deprecated — kept as a thin shim so existing consumers of
 * `<StateProgress current={...} />` continue to compile during the
 * Impl-3 rollout. New code should import `PhaseStrip` directly from
 * `components/shared/PhaseStrip.tsx` and pass the full `steps` array
 * (BlindPoll uses 4 phases: Registration → Commit → Reveal → Ended).
 *
 * BlindPoll.tsx switches over to the direct import in the same Impl-3
 * series; this file will be deleted once that consumer is updated.
 */

import { Check, Lock, Unlock, Users } from 'lucide-react'
import { PhaseStrip, type PhaseStripStep } from '../shared/PhaseStrip'

const BLIND_POLL_STEPS: PhaseStripStep[] = [
    { label: 'Registration', icon: Users },
    { label: 'Commit', icon: Lock },
    { label: 'Reveal', icon: Unlock },
    { label: 'Ended', icon: Check },
]

export function StateProgress({ current }: { current: number }) {
    return <PhaseStrip steps={BLIND_POLL_STEPS} current={current} />
}
