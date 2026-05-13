import { Check, Loader2, X } from 'lucide-react'
import type { ReactNode } from 'react'

export type FeedbackType = 'success' | 'error' | 'pending'

interface Config {
    /** Tailwind text-color utility for the icon glyph. */
    iconClass: string
    /** Tailwind border-color utility for the left bar. */
    borderClass: string
    icon: ReactNode
}

const CONFIG: Record<FeedbackType, Config> = {
    pending: {
        iconClass: 'text-db-oltremare',
        borderClass: 'border-db-oltremare',
        icon: <Loader2 className="w-4 h-4 animate-spin" />,
    },
    success: {
        iconClass: 'text-db-success',
        borderClass: 'border-db-success',
        icon: <Check className="w-4 h-4" />,
    },
    error: {
        iconClass: 'text-db-segnale',
        borderClass: 'border-db-segnale',
        icon: <X className="w-4 h-4" />,
    },
}

interface Props {
    type: FeedbackType
    children: ReactNode
}

/**
 * Bauhaus-flavoured replacement for the old rounded-card FeedbackMessage.
 *
 * Surface: `bg-db-slate`, hairline left rule in signal colour, mono caption.
 * Used for transaction pending / success / error feedback above the form.
 */
export function CreateFeedback({ type, children }: Props) {
    const cfg = CONFIG[type]
    return (
        <div
            role="alert"
            className={`flex items-center gap-3 px-4 py-3 bg-db-slate border-l-2 ${cfg.borderClass} font-mono text-[12px] text-db-chalk`}
        >
            <span className={cfg.iconClass}>{cfg.icon}</span>
            <span>{children}</span>
        </div>
    )
}
