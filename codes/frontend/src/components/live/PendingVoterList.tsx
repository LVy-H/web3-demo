import { Check, X, Loader2 } from 'lucide-react'
import type { PendingVoter } from '../../lib/liveRelay'

interface Props {
  voters: PendingVoter[]
  onConfirm: (voter: PendingVoter) => void
  onReject: (commitment: string) => void
  /** The commitment currently being registered on-chain (spinner + disable). */
  confirmingCommitment: string | null
  /** False outside the Registration phase or when the viewer isn't the owner. */
  canConfirm: boolean
}

/**
 * PendingVoterList (S1.4) — the organizer's queue. Each row shows the voter's
 * 4-digit code; Confirm registers them on-chain (S1.6), Reject drops them with
 * no transaction. Confirm/Reject only act during the Registration phase.
 */
export function PendingVoterList({ voters, onConfirm, onReject, confirmingCommitment, canConfirm }: Props) {
  if (voters.length === 0) {
    return (
      <div className="border border-dashed border-db-rule p-6 text-center">
        <p className="font-mono text-[12px] text-db-mute">
          No voters waiting. As people scan the QR, their codes appear here.
        </p>
      </div>
    )
  }

  return (
    <ul className="flex flex-col gap-px bg-db-rule" data-testid="pending-voter-list">
      {voters.map((v) => {
        const busy = confirmingCommitment === v.ephemeralIdentityCommitment
        return (
          <li
            key={v.ticketNonce}
            className="bg-db-void flex items-center justify-between gap-4 px-4 py-3"
          >
            <span className="font-sans font-extrabold text-[28px] tabular-nums tracking-[0.12em] text-db-chalk">
              {v.confirmationCode}
            </span>
            <div className="flex items-center gap-2">
              <button
                type="button"
                disabled={!canConfirm || busy}
                onClick={() => onConfirm(v)}
                className="inline-flex items-center gap-1.5 min-h-[44px] px-4 bg-db-segnale text-db-void font-sans font-extrabold text-[11px] tracking-[0.16em] uppercase disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
              >
                {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Check className="w-4 h-4" />}
                {busy ? 'Registering…' : 'Confirm'}
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={() => onReject(v.ephemeralIdentityCommitment)}
                className="inline-flex items-center gap-1.5 min-h-[44px] px-4 bg-db-slate text-db-mute hover:text-db-chalk font-sans font-extrabold text-[11px] tracking-[0.16em] uppercase disabled:opacity-40 cursor-pointer"
                aria-label={`Reject voter ${v.confirmationCode}`}
              >
                <X className="w-4 h-4" />
                Reject
              </button>
            </div>
          </li>
        )
      })}
    </ul>
  )
}
