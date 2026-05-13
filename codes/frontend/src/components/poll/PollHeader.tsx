import { Link } from 'react-router-dom'
import { ArrowLeft } from 'lucide-react'

/**
 * Top-of-page header: back link, ZK mode tag, address pill. Rectangles only
 * (no rounded corners) per Dark Bauhaus grammar.
 */
export function PollHeader({
    pollAddress,
}: {
    pollAddress: string | undefined
}) {
    const short = pollAddress
        ? `${pollAddress.slice(0, 6)}…${pollAddress.slice(-4)}`
        : '0x…'

    return (
        <div className="flex items-center justify-between py-4 border-b border-db-rule">
            <Link
                to="/"
                className="flex items-center gap-1.5 text-db-mute hover:text-db-chalk font-mono text-[11px] tracking-[0.16em] uppercase focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-db-chalk transition-colors"
            >
                <ArrowLeft className="w-3.5 h-3.5" />
                Back to polls
            </Link>
            <div className="flex items-center gap-2">
                <span className="bg-db-segnale text-db-void font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase px-3 py-1.5">
                    ZK · ANON
                </span>
                <span className="font-mono text-[11px] text-db-mute bg-db-slate border border-db-rule px-2.5 py-1.5 tracking-[0.05em]">
                    {short}
                </span>
            </div>
        </div>
    )
}
