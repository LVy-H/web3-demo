/**
 * Poll-page-scoped error map + a single-argument `friendlyError` wrapper.
 *
 * The shared `lib/friendlyError.ts` takes a 2-arg signature `(err, errorMap)`;
 * the existing Poll handlers (`handleVote`, `handleRelayVote`, etc.) call
 * `friendlyError(e)` single-arg from a local function. By re-exporting a
 * Poll-bound wrapper here we let those call sites stay byte-identical after
 * the Dark Bauhaus rewrite — preserving validation gate #7 ("zero changes to
 * lines 256–502 modulo the two `selectedOption === null` guards").
 */

import { friendlyError as baseFriendlyError } from './friendlyError'

export const ERROR_MAP: Record<string, string> = {
    'Not in voting phase': "Voting hasn't started yet. Wait for the poll admin to open voting.",
    'You have already voted': "You've already voted in this poll. Each identity can only vote once.",
    'Invalid option index': 'Invalid vote selection. Please try again.',
    'Not owner': 'Only the poll creator can perform this action.',
    'Not in registration phase': 'Registration is closed. Voting has already begun.',
    'Need at least 2 options': 'A poll needs at least 2 options before voting can start.',
    'Already registered': 'This identity is already registered for this poll.',
    'nullifier consumed': 'This vote token has already been used.',
    'Relay failed': 'Relayer service could not process the vote. Please try again.',
    'Failed to fetch': 'Cannot reach relayer service. Make sure it is running on port 3001.',
    'NetworkError': 'Network error connecting to relayer. Check your connection.',
}

export function friendlyError(err: unknown): string {
    return baseFriendlyError(err, ERROR_MAP)
}
