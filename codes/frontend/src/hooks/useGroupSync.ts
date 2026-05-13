import { useEffect, useRef, useState, useCallback } from 'react'
import { Group } from '@semaphore-protocol/group'
import { parseAbiItem } from 'viem'
import type { PublicClient } from 'viem'

/**
 * useGroupSync — owns the Semaphore group state for a single poll.
 *
 * Replaces the module-scope `let group` / `let isGroupSynced` previously
 * declared at the top of `Poll.tsx`. Module globals leak across
 * navigation and HMR; this hook scopes the state to the component
 * instance and resets it whenever `pollAddress` changes.
 *
 * The returned `group` is the live `Group` instance kept in a ref —
 * callers should call `sync()` before reading group membership.
 */
export function useGroupSync(
    pollAddress: string | undefined,
    contractGroupId: bigint | null,
    publicClient: PublicClient | undefined,
    typedPollAddr: `0x${string}` | undefined,
) {
    const groupRef = useRef<Group | null>(null)
    const [isSyncing, setIsSyncing] = useState(false)
    const [isSynced, setIsSynced] = useState(false)

    // Reset all internal state whenever the poll changes.
    useEffect(() => {
        groupRef.current = null
        setIsSynced(false)
        setIsSyncing(false)
    }, [pollAddress])

    const sync = useCallback(async (): Promise<Group | null> => {
        if (
            !pollAddress
            || !publicClient
            || !typedPollAddr
            || contractGroupId === undefined
            || contractGroupId === null
        ) {
            return groupRef.current
        }
        if (groupRef.current) {
            // Already synced for this poll.
            return groupRef.current
        }
        setIsSyncing(true)
        try {
            const group = new Group()
            const logs = await publicClient.getLogs({
                address: typedPollAddr,
                event: parseAbiItem('event VoterRegistered(uint256 identityCommitment)'),
                fromBlock: 0n,
            })
            const seen = new Set<string>()
            logs.forEach(log => {
                const c = log.args.identityCommitment
                if (c === undefined || c === null) return
                const key = c.toString()
                if (seen.has(key)) return
                seen.add(key)
                try {
                    group.addMember(BigInt(key))
                } catch (e: unknown) {
                    const err = e as { message?: string }
                    console.warn('group.addMember failed for commitment', key, err.message)
                }
            })
            groupRef.current = group
            setIsSynced(true)
            return group
        } catch (e) {
            console.error('Failed to sync group', e)
            throw e
        } finally {
            setIsSyncing(false)
        }
    }, [pollAddress, publicClient, typedPollAddr, contractGroupId])

    const reset = useCallback(() => {
        groupRef.current = null
        setIsSynced(false)
    }, [])

    return {
        group: groupRef.current,
        isSyncing,
        isSynced,
        sync,
        reset,
    }
}
