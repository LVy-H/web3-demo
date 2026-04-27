import { useCallback, useEffect, useState } from 'react'
import { encodePacked, keccak256 } from 'viem'
import ZkBlindVotingABI from '../abi/ZkBlindVoting.json'
import { useBlindPollWrite } from './useBlindPoll'
import { friendlyError } from '../lib/friendlyError'
import { BLIND_POLL_ERROR_MAP } from '../components/blindpoll/errorMap'

type SavedCommit = {
    optionIndex: number
    salt: `0x${string}`
}

function storageKey(pollAddress: string | undefined): string | null {
    if (!pollAddress) return null
    return `blind-vote-${pollAddress}`
}

/**
 * Owns the blind-vote flow: commitment generation, localStorage persistence,
 * commit + reveal transactions, and per-page transaction status.
 *
 * `hasCommitted` is sourced from the on-chain read so it stays accurate even
 * if the user switches browsers; `hasSavedCommit` reflects whether *this*
 * browser still has the salt+option needed to reveal.
 */
export function useBlindVote(params: {
    pollAddress: `0x${string}` | undefined
    hasCommitted: boolean
}) {
    const { pollAddress, hasCommitted } = params

    const {
        mutateAsync: writeContractAsync,
        isConfirming: isTxConfirming,
        isSuccess: isTxSuccess,
    } = useBlindPollWrite()

    const [hasSavedCommit, setHasSavedCommit] = useState(false)

    // Refresh the localStorage flag when poll or commit-state changes.
    useEffect(() => {
        const key = storageKey(pollAddress)
        if (!key) {
            setHasSavedCommit(false)
            return
        }
        setHasSavedCommit(localStorage.getItem(key) !== null)
    }, [pollAddress, hasCommitted])

    /**
     * Generate a fresh 32-byte salt, compute the commitment hash, persist the
     * preimage to localStorage, and submit `commitVote` on-chain.
     *
     * Returns void; throws on failure with a friendly message attached.
     */
    const commit = useCallback(
        async (selectedOption: number): Promise<void> => {
            if (!pollAddress) throw new Error('No poll address')
            const key = storageKey(pollAddress)!

            // Random salt (32 bytes)
            const saltBytes = new Uint8Array(32)
            crypto.getRandomValues(saltBytes)
            const salt = ('0x' +
                Array.from(saltBytes)
                    .map(b => b.toString(16).padStart(2, '0'))
                    .join('')) as `0x${string}`

            // commitHash = keccak256(abi.encodePacked(optionIndex, salt))
            const commitHash = keccak256(
                encodePacked(['uint256', 'bytes32'], [BigInt(selectedOption), salt]),
            )

            // Save preimage BEFORE submitting so we never lose it.
            const saved: SavedCommit = { optionIndex: selectedOption, salt }
            localStorage.setItem(key, JSON.stringify(saved))

            await writeContractAsync({
                address: pollAddress,
                abi: ZkBlindVotingABI.abi,
                functionName: 'commitVote',
                args: [commitHash],
            })

            setHasSavedCommit(true)
        },
        [pollAddress, writeContractAsync],
    )

    /**
     * Read the saved preimage from localStorage and submit `revealVote`.
     * Throws (with a marker) when no commit was saved in this browser.
     */
    const reveal = useCallback(async (): Promise<void> => {
        if (!pollAddress) throw new Error('No poll address')
        const key = storageKey(pollAddress)!

        const saved = localStorage.getItem(key)
        if (!saved) {
            throw new Error('NO_SAVED_COMMIT')
        }
        const { optionIndex, salt } = JSON.parse(saved) as SavedCommit

        await writeContractAsync({
            address: pollAddress,
            abi: ZkBlindVotingABI.abi,
            functionName: 'revealVote',
            args: [BigInt(optionIndex), salt],
        })
    }, [pollAddress, writeContractAsync])

    /**
     * Submit a generic admin write (start/end/finalize/addOption) using the
     * same transaction-status plumbing.
     */
    const adminWrite = useCallback(
        async (functionName: string, args?: readonly unknown[]) => {
            if (!pollAddress) throw new Error('No poll address')
            await writeContractAsync({
                address: pollAddress,
                abi: ZkBlindVotingABI.abi,
                functionName,
                args: args as unknown as readonly [],
            })
        },
        [pollAddress, writeContractAsync],
    )

    const friendly = useCallback(
        (err: unknown) => friendlyError(err, BLIND_POLL_ERROR_MAP),
        [],
    )

    return {
        // flow
        commit,
        reveal,
        adminWrite,
        // transaction status
        isTxConfirming,
        isTxSuccess,
        // local cache
        hasSavedCommit,
        // helpers
        friendlyError: friendly,
    }
}
