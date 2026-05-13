import { useState } from 'react'
import { RELAYER_URL } from '../config'

/**
 * useRelay — client for the gasless relayer service.
 *
 * The relayer accepts a Semaphore zero-knowledge proof and forwards the
 * `castVote` transaction on the user's behalf, so a voter without a
 * funded wallet can still participate. Identity, ZK proof, and option
 * choice never leave the browser unencrypted; the relayer only sees the
 * proof payload it submits.
 *
 * Surface:
 *  - useRelayVote()   -> { relayVote, isRelaying }
 *  - useRelayStatus() -> { fetchStatus }    (one-shot poll-on-demand)
 */

export interface RelayProof {
    merkleTreeDepth: number | bigint
    merkleTreeRoot: bigint
    nullifier: bigint
    message: bigint
    scope: bigint
    points: readonly bigint[]
}

export interface RelayResult {
    success: boolean
    txHash?: `0x${string}`
    error?: string
}

export interface RelayStatus {
    relayer: string // 0x address
    balance: string // wei as decimal string
}

const DEFAULT_TIMEOUT_MS = 30_000

export function useRelayVote() {
    const [isRelaying, setIsRelaying] = useState(false)

    async function relayVote(
        pollAddress: string,
        vote: number,
        proof: RelayProof,
        opts?: { signal?: AbortSignal; timeoutMs?: number },
    ): Promise<RelayResult> {
        setIsRelaying(true)
        const ac = new AbortController()
        const timeoutId = setTimeout(
            () => ac.abort('relay-timeout'),
            opts?.timeoutMs ?? DEFAULT_TIMEOUT_MS,
        )
        // Chain external signal if caller provided one.
        if (opts?.signal) {
            const ext = opts.signal
            ext.addEventListener('abort', () => ac.abort(ext.reason))
        }

        try {
            const body = {
                pollAddress,
                vote,
                proof: {
                    merkleTreeDepth: Number(proof.merkleTreeDepth),
                    merkleTreeRoot: proof.merkleTreeRoot.toString(),
                    nullifier: proof.nullifier.toString(),
                    message: proof.message.toString(),
                    scope: proof.scope.toString(),
                    points: proof.points.map(p => p.toString()),
                },
            }
            const res = await fetch(`${RELAYER_URL}/api/relay/vote`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body),
                signal: ac.signal,
            })
            const data = (await res.json().catch(() => ({}))) as {
                error?: string
                txHash?: `0x${string}`
            }
            if (!res.ok) {
                return { success: false, error: data.error || `HTTP ${res.status}` }
            }
            return { success: true, txHash: data.txHash }
        } catch (err) {
            const message =
                err instanceof Error
                    ? err.name === 'AbortError'
                        ? 'Relayer did not respond within 30s.'
                        : err.message
                    : String(err)
            return { success: false, error: message }
        } finally {
            clearTimeout(timeoutId)
            setIsRelaying(false)
        }
    }

    return { relayVote, isRelaying }
}

export function useRelayStatus() {
    async function fetchStatus(): Promise<RelayStatus | null> {
        try {
            const res = await fetch(`${RELAYER_URL}/api/relay/status`, {
                signal: AbortSignal.timeout(5_000),
            })
            if (!res.ok) return null
            return (await res.json()) as RelayStatus
        } catch {
            return null
        }
    }
    return { fetchStatus }
}
