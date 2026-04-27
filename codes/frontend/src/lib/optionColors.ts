/**
 * Solid Tailwind background-color classes used to color the option bars in
 * poll result charts. Indexed by option position (mod length).
 *
 * Shared between Poll and BlindPoll pages.
 */
export const OPTION_BAR_COLORS = [
    'bg-teal-500',
    'bg-indigo-500',
    'bg-amber-500',
    'bg-rose-500',
    'bg-violet-500',
    'bg-cyan-500',
    'bg-orange-500',
    'bg-emerald-500',
    'bg-pink-500',
    'bg-sky-500',
] as const
