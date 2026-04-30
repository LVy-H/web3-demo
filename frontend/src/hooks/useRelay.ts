import { useState } from 'react'
import { RELAYER_URL } from '../config'

interface RelayResult {
    success: boolean
    txHash?: string
    error?: string
}

export function useRelayVote() {
    const [isRelaying, setIsRelaying] = useState(false)

    async function relayVote(
        pollAddress: string,
        vote: number,
        proof: {
            merkleTreeDepth: number | bigint
            merkleTreeRoot: bigint
            nullifier: bigint
            message: bigint
            scope: bigint
            points: bigint[]
        }
    ): Promise<RelayResult> {
        setIsRelaying(true)
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
                    points: proof.points.map((p) => p.toString()),
                },
            }

            const res = await fetch(`${RELAYER_URL}/api/relay/vote`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body),
            })

            const data = await res.json()

            if (!res.ok) {
                return { success: false, error: data.error || 'Relay failed' }
            }

            return { success: true, txHash: data.txHash }
        } catch (err) {
            const message = err instanceof Error ? err.message : String(err)
            return { success: false, error: message }
        } finally {
            setIsRelaying(false)
        }
    }

    return { relayVote, isRelaying }
}

export function useRelayStatus() {
    async function fetchStatus(): Promise<{
        relayer: string
        balance: string
    } | null> {
        try {
            const res = await fetch(`${RELAYER_URL}/api/relay/status`)
            if (!res.ok) return null
            return await res.json()
        } catch {
            return null
        }
    }

    return { fetchStatus }
}
