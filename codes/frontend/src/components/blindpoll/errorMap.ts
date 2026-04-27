import type { ErrorMap } from '../../lib/friendlyError'

/**
 * BlindPoll's revert-string → user-message lookup table.
 * Strings on the left must match substrings of the revert reasons emitted
 * by ZkBlindVoting and IZkPoll.
 */
export const BLIND_POLL_ERROR_MAP: ErrorMap = {
    'Not in voting phase': "Voting hasn't started yet. Wait for the poll admin to open voting.",
    'Already committed': "You've already committed a vote in this poll.",
    'Not registered': 'You are not registered for this poll. Register first.',
    'Invalid option index': 'Invalid vote selection. Please try again.',
    'Not owner': 'Only the poll creator can perform this action.',
    'Not in registration phase': 'Registration is closed. Voting has already begun.',
    'Need at least 2 options': 'A poll needs at least 2 options before voting can start.',
    'Already registered': 'You are already registered for this poll.',
    'Not in ended phase': 'The poll has not ended yet.',
    'Reveal deadline passed': 'The reveal window has closed.',
    'No commit found': 'You did not commit a vote.',
    'Already revealed': 'You have already revealed your vote.',
    'Hash mismatch': 'Your reveal data does not match your commitment. Did you use the correct browser?',
    'Reveal deadline not passed': 'The reveal window has not closed yet.',
    'Already finalized': 'Results have already been finalized.',
    'Need at least 1 voter': 'At least one voter must be registered before starting.',
}
