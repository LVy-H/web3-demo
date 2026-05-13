import { useEffect, useState } from 'react'

/**
 * Live HH:MM:SS countdown to a unix-second deadline, restyled to the
 * Dark Bauhaus display-extrabold 40 px treatment (see
 * `.tmp/impl-specs/impl-3-blind-vote-page.md` §2.9). The 60 s danger
 * threshold flips the text to `text-db-segnale` and adds an animate-pulse.
 * Once the deadline passes the component renders a compact red label.
 */
export function Countdown({ deadline }: { deadline: number }) {
    const [now, setNow] = useState(Math.floor(Date.now() / 1000))

    useEffect(() => {
        const interval = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000)
        return () => clearInterval(interval)
    }, [])

    const remaining = deadline - now
    if (remaining <= 0) {
        return (
            <span
                className="font-display font-extrabold text-[20px] uppercase tracking-[0.18em] text-db-segnale"
                aria-live="polite"
            >
                Deadline Passed
            </span>
        )
    }

    const hrs = Math.floor(remaining / 3600)
    const mins = Math.floor((remaining % 3600) / 60)
    const secs = remaining % 60
    const dangerZone = remaining < 60

    return (
        <span
            className={`font-display font-extrabold text-[40px] tabular-nums tracking-[0.04em] ${
                dangerZone ? 'text-db-segnale animate-pulse' : 'text-db-chalk'
            }`}
            aria-live="polite"
        >
            {hrs.toString().padStart(2, '0')}:{mins.toString().padStart(2, '0')}:{secs.toString().padStart(2, '0')}
        </span>
    )
}
