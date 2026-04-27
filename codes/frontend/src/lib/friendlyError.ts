/**
 * Translate raw on-chain revert messages and wallet errors into user-friendly
 * strings. Each page passes its own `ERROR_MAP` because the set of revert
 * reasons differs between contracts.
 *
 * Shared between Poll and BlindPoll pages.
 */
export type ErrorMap = Record<string, string>

export function friendlyError(err: unknown, errorMap: ErrorMap): string {
    const msg =
        (err as { shortMessage?: string; message?: string })?.shortMessage
        ?? (err as { message?: string })?.message
        ?? String(err)
    for (const [key, friendly] of Object.entries(errorMap)) {
        if (msg.includes(key)) return friendly
    }
    return 'Something went wrong. Please check your wallet and try again.'
}
