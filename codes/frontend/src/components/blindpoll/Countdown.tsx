import { useEffect, useState } from 'react'

/**
 * Live HH:MM:SS countdown to a unix-second deadline. Switches to a red
 * "Deadline passed" label once `deadline <= now`.
 */
export function Countdown({ deadline }: { deadline: number }) {
    const [now, setNow] = useState(Math.floor(Date.now() / 1000))

    useEffect(() => {
        const interval = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000)
        return () => clearInterval(interval)
    }, [])

    const remaining = deadline - now
    if (remaining <= 0) {
        return <span className="text-rose-600 dark:text-rose-400 font-bold">Deadline passed</span>
    }

    const hrs = Math.floor(remaining / 3600)
    const mins = Math.floor((remaining % 3600) / 60)
    const secs = remaining % 60

    return (
        <span className="font-mono font-bold text-2xl tabular-nums text-white">
            {hrs.toString().padStart(2, '0')}:{mins.toString().padStart(2, '0')}:{secs.toString().padStart(2, '0')}
        </span>
    )
}
