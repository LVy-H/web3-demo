import { Fragment } from 'react'
import { Check } from 'lucide-react'

/**
 * 3-step progress indicator for a blind poll: Registration → Voting → Reveal/Ended.
 * `current` is the active step index (0-based, matches contract poll state).
 */
export function StateProgress({ current }: { current: number }) {
    const steps = ['Registration', 'Voting', 'Reveal / Ended']
    return (
        <div className="flex items-center gap-1">
            {steps.map((step, i) => (
                <Fragment key={i}>
                    {i > 0 && (
                        <div className={`flex-1 h-0.5 rounded-full transition-all duration-500 ${
                            i <= current ? 'bg-teal-500' : 'bg-stone-200 dark:bg-stone-700'
                        }`} />
                    )}
                    <div className="flex flex-col items-center gap-1.5">
                        <div className="relative">
                            <div
                                className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold transition-all duration-300
                                    ${i < current
                                        ? 'bg-teal-600 text-white'
                                        : i === current
                                            ? 'bg-white dark:bg-stone-800 border-2 border-teal-500 text-teal-600 dark:text-teal-400'
                                            : 'bg-stone-200 dark:bg-stone-700 text-stone-400 dark:text-stone-500'
                                    }`}
                            >
                                {i < current ? <Check className="w-3.5 h-3.5" /> : i + 1}
                            </div>
                            {i === current && (
                                <span className="absolute inset-0 rounded-full animate-ping bg-teal-400 opacity-15" />
                            )}
                        </div>
                        <span className={`text-xs font-medium ${i === current ? 'text-teal-700 dark:text-teal-400 font-semibold' : i < current ? 'text-teal-600 dark:text-teal-500' : 'text-stone-400 dark:text-stone-500'}`}>
                            {step}
                        </span>
                    </div>
                </Fragment>
            ))}
        </div>
    )
}
