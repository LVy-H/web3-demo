/**
 * Live Meeting Vote — typed client for the relayer's ticket endpoints (S1.2 API).
 *
 * ALL relayer ticket calls go through here (the cross-client boundary, spec
 * §2.5): CreatePoll issues the org pubkey, the voter page posts itself pending,
 * the host dashboard reads the queue, and the confirm flow redeems. A future
 * Flutter client reimplements this one module against the same HTTP contract.
 */
import { RELAYER_URL } from '../config'

export type PendingStatus = 'pending' | 'confirmed' | 'rejected'

export interface PendingVoter {
  ticketNonce: string
  ticket: string
  ephemeralIdentityCommitment: string
  confirmationCode: string
  status: PendingStatus
  createdAt: number
}

const DEFAULT_TIMEOUT_MS = 8_000

async function postJson(
  path: string,
  body: unknown,
  opts?: { signal?: AbortSignal; timeoutMs?: number },
): Promise<{ ok: boolean; status: number; data: Record<string, unknown> }> {
  const ac = new AbortController()
  const timer = setTimeout(() => ac.abort('timeout'), opts?.timeoutMs ?? DEFAULT_TIMEOUT_MS)
  if (opts?.signal) opts.signal.addEventListener('abort', () => ac.abort(opts.signal?.reason))
  try {
    const res = await fetch(`${RELAYER_URL}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: ac.signal,
    })
    const data = (await res.json().catch(() => ({}))) as Record<string, unknown>
    return { ok: res.ok, status: res.status, data }
  } finally {
    clearTimeout(timer)
  }
}

/** Register the organizer's per-poll ed25519 PUBLIC key (verification anchor). */
export async function issueOrgKey(pollId: string, orgPubKey: string): Promise<void> {
  const r = await postJson('/api/relay/tickets/issue', { pollId, orgPubKey })
  if (!r.ok) throw new Error(typeof r.data.error === 'string' ? r.data.error : `issue failed (HTTP ${r.status})`)
}

export interface PostPendingResult {
  ok: boolean
  status: number
  error?: string
}

/** Voter announces itself with a fresh ticket + its ephemeral commitment + code. */
export async function postPending(
  pollId: string,
  ticket: string,
  ephemeralIdentityCommitment: string,
  confirmationCode: string,
  opts?: { signal?: AbortSignal },
): Promise<PostPendingResult> {
  const r = await postJson(
    '/api/relay/tickets/pending',
    { pollId, ticket, ephemeralIdentityCommitment, confirmationCode },
    opts,
  )
  return { ok: r.ok, status: r.status, error: typeof r.data.error === 'string' ? r.data.error : undefined }
}

/** Organizer dashboard reads the pending-voter queue for a poll. */
export async function fetchQueue(
  pollId: string,
  opts?: { signal?: AbortSignal; timeoutMs?: number },
): Promise<PendingVoter[]> {
  const ac = new AbortController()
  const timer = setTimeout(() => ac.abort('timeout'), opts?.timeoutMs ?? DEFAULT_TIMEOUT_MS)
  if (opts?.signal) opts.signal.addEventListener('abort', () => ac.abort(opts.signal?.reason))
  try {
    const res = await fetch(`${RELAYER_URL}/api/relay/tickets/queue?pollId=${pollId}`, { signal: ac.signal })
    if (!res.ok) throw new Error(`queue failed (HTTP ${res.status})`)
    const data = (await res.json()) as { voters?: PendingVoter[] }
    return Array.isArray(data.voters) ? data.voters : []
  } finally {
    clearTimeout(timer)
  }
}

/** Mark a ticket consumed once the organizer has confirmed the voter. */
export async function redeemTicket(pollId: string, ticket: string): Promise<void> {
  const r = await postJson('/api/relay/tickets/redeem', { pollId, ticket })
  if (!r.ok) throw new Error(typeof r.data.error === 'string' ? r.data.error : `redeem failed (HTTP ${r.status})`)
}
