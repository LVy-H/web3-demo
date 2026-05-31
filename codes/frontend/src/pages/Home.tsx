/**
 * Browse Polls — Dark Bauhaus v8 stateful-card grammar.
 *
 * Three card lifecycle states (active / upcoming / ended) share one
 * shell but mutate surface, border style, top-accent intensity, state
 * chip, hero stat block, and watermark glyph. The grammar is sourced
 * from `.tmp/ui-demos/13-browse-polls-stateful-cards.html` (v8) and
 * `.tmp/ui-proposals/05-dark-bauhaus.md`.
 *
 * Data caveat — `PollInfo` (from `useAllPolls`) carries no end-time,
 * vote-count, eligible-voter, or category data. So:
 *   - Category is derived deterministically from `pollAddress`
 *     (last hex digit mod 4 → governance / treasury / tech / social)
 *     so each card gets a stable hue without contract changes.
 *   - Lifecycle is always "active" for real polls (no end-time means
 *     we cannot mark anything ended; no schedule means nothing is
 *     upcoming). The Upcoming/Ended branches are wired and reachable
 *     via the status filter pills but render the empty state until
 *     the registry surfaces phase data — that wiring is a follow-up.
 *   - Vote count + countdown + participation bar in the Active hero
 *     show "—" placeholders for the same reason; the "opened Xh ago"
 *     line still tells the user the card is live.
 */

import { Link } from 'react-router-dom'
import { useState, useMemo } from 'react'
import { useAllPolls } from '../hooks/useRegistry'
import type { PollInfo } from '../hooks/useRegistry'
import {
    FileText,
    Plus,
    Search,
    Lock,
    ArrowUpRight,
    ChevronDown,
} from 'lucide-react'

/* ────────────────────────────────────────────────────────────────────── */
/* Domain enums + derivations                                              */
/* ────────────────────────────────────────────────────────────────────── */

type Category = 'governance' | 'treasury' | 'tech' | 'social'
type LifecyclePhase = 'active' | 'upcoming' | 'ended'

const CATEGORIES: ReadonlyArray<Category> = ['governance', 'treasury', 'tech', 'social']
const CATEGORY_LABEL: Record<Category, string> = {
    governance: 'Governance',
    treasury: 'Treasury',
    tech: 'Tech',
    social: 'Social',
}

/**
 * Derive a stable category from the poll address — last hex digit mod 4.
 * Deterministic per poll, gives visual variety, no contract change needed.
 */
function deriveCategory(pollAddress: string): Category {
    const last = pollAddress.slice(-1).toLowerCase()
    const n = parseInt(last, 16)
    if (Number.isNaN(n)) return 'tech'
    // n % 4 is always 0..3 — CATEGORIES has length 4 — but
    // `noUncheckedIndexedAccess` still types the lookup as `T | undefined`.
    return CATEGORIES[n % 4] ?? 'tech'
}

/**
 * Currently every real poll is "active" (no end-time on chain).
 * Returns `active` for all real polls — kept as a function so the
 * upcoming/ended branches are easy to wire up later.
 */
function derivePhase(_poll: PollInfo): LifecyclePhase {
    return 'active'
}

function relativeTime(unixSec: number): string {
    const now = Math.floor(Date.now() / 1000)
    const diff = now - unixSec
    if (diff < 60) return 'just now'
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
    return `${Math.floor(diff / 86400)}d ago`
}

function shortAddr(addr: string): string {
    if (!addr || addr.length < 10) return addr
    return `${addr.slice(0, 6)}·${addr.slice(-4)}`.toUpperCase()
}

/* ────────────────────────────────────────────────────────────────────── */
/* Inline SVG watermark symbols (sourced from v8 demo).                    */
/* Each glyph uses `currentColor` strokes so the parent's `color` (set     */
/* per state — segnale red / oltremare blue / success green) tints it.     */
/* ────────────────────────────────────────────────────────────────────── */

function WatermarkSymbols() {
    return (
        <svg
            xmlns="http://www.w3.org/2000/svg"
            width="0"
            height="0"
            aria-hidden="true"
            style={{ position: 'absolute', width: 0, height: 0, overflow: 'hidden' }}
        >
            <defs>
                {/* ACTIVE — ballot envelope + check */}
                <symbol id="illo-vote" viewBox="0 0 140 140">
                    <rect x="22" y="60" width="96" height="58" fill="none" stroke="currentColor" strokeWidth="3" />
                    <line x1="38" y1="60" x2="102" y2="60" stroke="currentColor" strokeWidth="3" />
                    <line x1="46" y1="60" x2="94" y2="60" stroke="currentColor" strokeWidth="6" opacity="0.5" />
                    <rect x="46" y="18" width="48" height="40" fill="none" stroke="currentColor" strokeWidth="3" />
                    <polyline
                        points="56,38 67,49 86,28"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="4"
                        strokeLinecap="square"
                        strokeLinejoin="miter"
                    />
                    <line x1="38" y1="80" x2="58" y2="80" stroke="currentColor" strokeWidth="2" opacity="0.65" />
                    <line x1="38" y1="92" x2="74" y2="92" stroke="currentColor" strokeWidth="2" opacity="0.45" />
                    <line x1="38" y1="104" x2="50" y2="104" stroke="currentColor" strokeWidth="2" opacity="0.3" />
                </symbol>

                {/* UPCOMING — clock + tiny padlock */}
                <symbol id="illo-schedule" viewBox="0 0 140 140">
                    <circle cx="70" cy="62" r="38" fill="none" stroke="currentColor" strokeWidth="3" />
                    <line x1="70" y1="28" x2="70" y2="34" stroke="currentColor" strokeWidth="3" />
                    <line x1="70" y1="90" x2="70" y2="96" stroke="currentColor" strokeWidth="3" />
                    <line x1="36" y1="62" x2="42" y2="62" stroke="currentColor" strokeWidth="3" />
                    <line x1="98" y1="62" x2="104" y2="62" stroke="currentColor" strokeWidth="3" />
                    <line x1="70" y1="62" x2="90" y2="46" stroke="currentColor" strokeWidth="4" strokeLinecap="square" />
                    <line x1="70" y1="62" x2="70" y2="40" stroke="currentColor" strokeWidth="3" strokeLinecap="square" />
                    <circle cx="70" cy="62" r="3" fill="currentColor" />
                    <rect x="56" y="112" width="28" height="18" fill="none" stroke="currentColor" strokeWidth="3" />
                    <path d="M62 112 v-6 a8 8 0 0 1 16 0 v6" fill="none" stroke="currentColor" strokeWidth="3" />
                </symbol>

                {/* ENDED — laurel-framed seal + check */}
                <symbol id="illo-trophy" viewBox="0 0 140 140">
                    <path d="M44 24 C 30 44, 30 96, 44 116" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="square" />
                    <path d="M44 36 q -8 6 -8 14" fill="none" stroke="currentColor" strokeWidth="2" />
                    <path d="M42 56 q -10 4 -10 14" fill="none" stroke="currentColor" strokeWidth="2" />
                    <path d="M42 76 q -10 4 -10 14" fill="none" stroke="currentColor" strokeWidth="2" />
                    <path d="M44 96 q -8 4 -8 12" fill="none" stroke="currentColor" strokeWidth="2" />
                    <path d="M96 24 C 110 44, 110 96, 96 116" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="square" />
                    <path d="M96 36 q 8 6 8 14" fill="none" stroke="currentColor" strokeWidth="2" />
                    <path d="M98 56 q 10 4 10 14" fill="none" stroke="currentColor" strokeWidth="2" />
                    <path d="M98 76 q 10 4 10 14" fill="none" stroke="currentColor" strokeWidth="2" />
                    <path d="M96 96 q 8 4 8 12" fill="none" stroke="currentColor" strokeWidth="2" />
                    <rect x="54" y="50" width="32" height="36" fill="none" stroke="currentColor" strokeWidth="3" />
                    <polyline
                        points="60,68 68,76 80,60"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="3.5"
                        strokeLinecap="square"
                        strokeLinejoin="miter"
                    />
                    <line x1="40" y1="120" x2="100" y2="120" stroke="currentColor" strokeWidth="3" />
                </symbol>
            </defs>
        </svg>
    )
}

/* ────────────────────────────────────────────────────────────────────── */
/* Per-category style maps                                                 */
/* ────────────────────────────────────────────────────────────────────── */

const CAT_STRIP: Record<Category, string> = {
    governance: 'bg-db-cat-governance',
    treasury: 'bg-db-cat-treasury',
    tech: 'bg-db-cat-tech',
    social: 'bg-db-cat-social',
}
const CAT_HOVER_BORDER: Record<Category, string> = {
    governance: 'hover:border-db-cat-governance',
    treasury: 'hover:border-db-cat-treasury',
    tech: 'hover:border-db-cat-tech',
    social: 'hover:border-db-cat-social',
}
const CAT_INK: Record<Category, string> = {
    governance: 'text-db-cat-governance',
    treasury: 'text-db-cat-treasury',
    tech: 'text-db-cat-tech',
    social: 'text-db-cat-social',
}
const CAT_SWATCH: Record<Category, string> = {
    governance: 'bg-db-cat-governance',
    treasury: 'bg-db-cat-treasury',
    tech: 'bg-db-cat-tech',
    social: 'bg-db-cat-social',
}

/* ────────────────────────────────────────────────────────────────────── */
/* Card                                                                    */
/* ────────────────────────────────────────────────────────────────────── */

interface CardProps {
    poll: PollInfo
    category: Category
    phase: LifecyclePhase
}

function PollCard({ poll, category, phase }: CardProps) {
    const createdAt = Number(poll.createdAt)
    const openedAgo = createdAt > 0 ? `opened ${relativeTime(createdAt)}` : 'opened recently'

    // State-dependent surface + watermark colour
    const surfaceClass =
        phase === 'active'
            ? 'bg-db-slate border-solid'
            : phase === 'upcoming'
                ? 'bg-db-slate-2 border-dashed'
                : 'bg-db-slate-dim border-solid [filter:saturate(0.6)]'

    const stripOpacity =
        phase === 'active' ? 'opacity-100' : phase === 'upcoming' ? 'opacity-50' : 'opacity-30'

    const wmHref =
        phase === 'active' ? '#illo-vote' : phase === 'upcoming' ? '#illo-schedule' : '#illo-trophy'
    const wmTint =
        phase === 'active'
            ? 'text-db-segnale opacity-[0.20]'
            : phase === 'upcoming'
                ? 'text-db-oltremare opacity-[0.25]'
                : 'text-db-success opacity-[0.18]'

    return (
        <Link
            to={`/poll/${poll.pollAddress}`}
            data-cat={category}
            data-phase={phase}
            className={[
                'group relative flex flex-col gap-[0.6rem]',
                'border border-db-rule pt-[calc(1.25rem+4px)] pb-5 px-6',
                'min-h-[248px] overflow-hidden no-underline text-left',
                'text-db-chalk-dim hover:text-db-chalk',
                'transition-[border-color,background,transform,color] duration-150',
                'hover:-translate-y-px',
                CAT_HOVER_BORDER[category],
                'focus-visible:outline-none focus-visible:border-db-chalk',
                surfaceClass,
            ].join(' ')}
        >
            {/* Top 4px accent strip — per-category hue */}
            <span
                aria-hidden
                className={`absolute left-0 right-0 top-0 h-1 z-[2] ${CAT_STRIP[category]} ${stripOpacity}`}
            />

            {/* Watermark — bottom-right corner, currentColor-tinted symbol */}
            <span
                aria-hidden
                className={`absolute -right-3 -bottom-3.5 w-[140px] h-[140px] z-0 pointer-events-none ${wmTint}`}
            >
                <svg width="100%" height="100%" className="block">
                    <use href={wmHref} />
                </svg>
            </span>

            {/* Header: category label + state chip */}
            <header className="flex items-center justify-between gap-3 relative z-[1]">
                <span
                    className={`inline-flex items-center gap-2 font-mono text-[10px] uppercase tracking-[0.22em] ${
                        phase === 'ended' ? 'text-db-mute' : CAT_INK[category]
                    }`}
                >
                    <span
                        className={`inline-block w-2 h-2 ${
                            phase === 'ended' ? 'bg-db-mute-dim' : CAT_SWATCH[category]
                        }`}
                    />
                    {CATEGORY_LABEL[category]}
                </span>
                <StateChip phase={phase} />
            </header>

            {/* Title (2-line clamp) */}
            <h2
                className={[
                    'relative z-[1] font-sans text-[19px] leading-[1.28] tracking-[-0.005em]',
                    'line-clamp-2 min-h-[calc(19px*1.28*2)]',
                    phase === 'ended' ? 'font-medium text-db-mute' : 'font-semibold text-db-chalk',
                ].join(' ')}
            >
                {poll.title}
            </h2>

            {/* Meta row */}
            <div className="flex flex-wrap items-center gap-2.5 font-mono text-[11px] text-db-mute tracking-[0.04em] relative z-[1]">
                <span className={phase === 'ended' ? 'text-db-mute' : 'text-db-chalk-dim'}>
                    {shortAddr(poll.creator)}
                </span>
                <span className="text-db-mute-dim">·</span>
                <span>{openedAgo}</span>
            </div>

            {/* Hero stat block */}
            <HeroStat phase={phase} category={category} />

            {/* Hover-arrow hint */}
            <ArrowUpRight
                aria-hidden
                className={[
                    'absolute right-3.5 bottom-3.5 w-[18px] h-[18px] z-[3]',
                    'text-db-mute-dim transition-[color,transform] duration-150',
                    'group-hover:translate-x-0.5 group-hover:-translate-y-0.5',
                    phase === 'ended' ? 'group-hover:text-db-mute' : `group-hover:${CAT_INK[category]}`,
                ].join(' ')}
            />
        </Link>
    )
}

function StateChip({ phase }: { phase: LifecyclePhase }) {
    if (phase === 'active') {
        return (
            <span className="inline-flex items-center gap-1.5 px-2 py-1 font-mono text-[9.5px] uppercase tracking-[0.18em] bg-db-segnale border border-db-segnale text-white">
                <span className="inline-block w-1.5 h-1.5 bg-white" />
                Voting
            </span>
        )
    }
    if (phase === 'upcoming') {
        return (
            <span className="inline-flex items-center gap-1.5 px-2 py-1 font-mono text-[9.5px] uppercase tracking-[0.18em] bg-transparent border border-db-oltremare text-db-oltremare">
                <span className="inline-block w-1.5 h-1.5 bg-db-oltremare" />
                Upcoming
            </span>
        )
    }
    return (
        <span className="inline-flex items-center gap-1.5 px-2 py-1 font-mono text-[9.5px] uppercase tracking-[0.18em] bg-db-slate-4 border border-db-rule text-db-mute">
            <Lock className="w-[11px] h-[11px]" />
            Ended
        </span>
    )
}

/**
 * Hero stat — active shows live count + countdown + per-category bar
 * (placeholder values since `PollInfo` has none of them); upcoming
 * shows oltremare-blue countdown; ended shows verdict + final tally.
 */
function HeroStat({ phase, category }: { phase: LifecyclePhase; category: Category }) {
    const barOnInk: Record<Category, string> = {
        governance: 'text-db-cat-governance',
        treasury: 'text-db-cat-treasury',
        tech: 'text-db-cat-tech',
        social: 'text-db-cat-social',
    }

    if (phase === 'active') {
        return (
            <div className="relative z-[1] mt-auto pt-3.5 border-t border-db-rule-soft flex flex-col gap-1.5">
                <div className="flex items-baseline gap-2.5">
                    <span className="font-sans font-bold text-[30px] leading-none text-db-chalk tracking-[-0.02em] tabular-nums [font-feature-settings:'tnum']">
                        —
                    </span>
                    <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-db-mute">
                        votes
                    </span>
                    <span className="ml-auto font-mono text-[13px] uppercase tracking-[0.1em] text-db-segnale">
                        <span className="text-db-segnale-d text-[10px] tracking-[0.18em] mr-1">T-MINUS</span>
                        —
                    </span>
                </div>
                <div className="flex items-center gap-2 font-mono text-[10px] text-db-mute tracking-[0.06em]">
                    <span className="text-[13px] leading-none select-none text-db-chalk-dim">
                        <span className={barOnInk[category]}>██</span>
                        <span className="text-db-rule">░░░░░░░░</span>
                    </span>
                    <span className="text-db-chalk-dim tracking-[0.04em]">
                        — of — eligible
                    </span>
                </div>
            </div>
        )
    }

    if (phase === 'upcoming') {
        return (
            <div className="relative z-[1] mt-auto pt-3.5 border-t border-db-rule-soft flex flex-col gap-1.5">
                <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-db-mute">
                    Opens in
                </div>
                <div className="font-sans font-bold text-[30px] leading-none text-db-oltremare tracking-[-0.02em] tabular-nums [font-feature-settings:'tnum']">
                    —
                    <span className="font-mono text-[13px] tracking-[0.06em] font-medium ml-px">h</span>
                </div>
                <div className="text-[13px] text-db-mute-dim">Registration phase</div>
                <div className="font-mono text-[10.5px] text-db-mute tracking-[0.08em] inline-flex items-center gap-2 mt-0.5">
                    ELIGIBLE VOTERS <span className="text-db-chalk-dim">—</span>
                </div>
            </div>
        )
    }

    // ended
    return (
        <div className="relative z-[1] mt-auto pt-3.5 border-t border-db-rule-soft flex flex-col gap-1.5">
            <div className="font-sans font-bold text-[20px] leading-[1.2] text-db-chalk tracking-[-0.01em] line-clamp-2">
                <span className="font-mono text-[10px] tracking-[0.22em] font-semibold mr-2 text-db-success">
                    PASSED
                </span>
                —
            </div>
            <div className="flex items-center gap-2.5 font-mono text-[11px] text-db-chalk-dim tracking-[0.04em]">
                <span className="text-[13px] leading-none select-none">
                    <span className="text-db-chalk-dim">██████████</span>
                    <span className="text-db-rule">░░</span>
                </span>
                <span>— · — votes</span>
            </div>
            <div className="font-mono text-[10px] text-db-mute tracking-[0.1em] inline-flex items-center gap-2.5">
                <span>Ended —</span>
                <span className="text-db-mute-dim">·</span>
                <span>
                    Quorum <span className="text-db-success">✓</span>
                </span>
            </div>
        </div>
    )
}

/* ────────────────────────────────────────────────────────────────────── */
/* Filter strip                                                            */
/* ────────────────────────────────────────────────────────────────────── */

type CategoryFilter = Category | 'all'
type StatusFilter = LifecyclePhase | 'all'
type SortBy = 'newest' | 'oldest' | 'title-asc' | 'title-desc'

const SORT_LABEL: Record<SortBy, string> = {
    'newest': 'Newest first',
    'oldest': 'Oldest first',
    'title-asc': 'Title A→Z',
    'title-desc': 'Title Z→A',
}

interface FiltersProps {
    cat: CategoryFilter
    setCat: (c: CategoryFilter) => void
    status: StatusFilter
    setStatus: (s: StatusFilter) => void
    searchQuery: string
    setSearchQuery: (q: string) => void
    sortBy: SortBy
    setSortBy: (s: SortBy) => void
}

function FilterStrip({ cat, setCat, status, setStatus, searchQuery, setSearchQuery, sortBy, setSortBy }: FiltersProps) {
    return (
        <nav
            aria-label="Filter polls"
            className="flex flex-wrap items-stretch border border-db-rule bg-db-slate-3 mb-6"
        >
            <div className="inline-flex items-stretch border-r border-db-rule flex-wrap">
                <span className="px-3.5 py-2.5 border-r border-db-rule font-mono text-[10px] text-db-mute uppercase tracking-[0.18em] self-center">
                    Category
                </span>
                <FilterPill active={cat === 'all'} onClick={() => setCat('all')} state="all">
                    All
                </FilterPill>
                {CATEGORIES.map(c => (
                    <FilterPill
                        key={c}
                        active={cat === c}
                        onClick={() => setCat(c)}
                        state="all"
                        category={c}
                    >
                        <span className={`inline-block w-2.5 h-[3px] ${cat === c ? CAT_STRIP[c] : 'bg-db-mute-dim'}`} />
                        {CATEGORY_LABEL[c]}
                    </FilterPill>
                ))}
            </div>

            <div className="inline-flex items-stretch border-r border-db-rule flex-wrap">
                <span className="px-3.5 py-2.5 border-r border-db-rule font-mono text-[10px] text-db-mute uppercase tracking-[0.18em] self-center">
                    Status
                </span>
                <FilterPill active={status === 'active'} onClick={() => setStatus('active')} state="active">
                    Active
                </FilterPill>
                <FilterPill active={status === 'upcoming'} onClick={() => setStatus('upcoming')} state="upcoming">
                    Upcoming
                </FilterPill>
                <FilterPill active={status === 'ended'} onClick={() => setStatus('ended')} state="ended">
                    <Lock className="w-2.5 h-2.5" />
                    Ended
                </FilterPill>
                <FilterPill active={status === 'all'} onClick={() => setStatus('all')} state="all-status">
                    All
                </FilterPill>
            </div>

            {/* Search input — was an inert label, now actually filters. */}
            <div className="ml-auto inline-flex items-center gap-2 px-4 border-l border-db-rule">
                <Search className="w-3.5 h-3.5 text-db-mute shrink-0" aria-hidden />
                <input
                    type="search"
                    placeholder="SEARCH POLLS"
                    value={searchQuery}
                    onChange={e => setSearchQuery(e.target.value)}
                    aria-label="Search polls by title or description"
                    className="bg-transparent border-0 focus:outline-none placeholder:text-db-mute font-mono text-[11px] uppercase tracking-[0.1em] text-db-chalk caret-db-segnale py-2 w-40 lg:w-56"
                />
            </div>

            {/* Sort dropdown — newest / oldest / title. */}
            <div className="inline-flex items-center gap-2 px-4 border-l border-db-rule">
                <label htmlFor="poll-sort" className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em] shrink-0">
                    Sort
                </label>
                <select
                    id="poll-sort"
                    value={sortBy}
                    onChange={e => setSortBy(e.target.value as SortBy)}
                    className="bg-transparent border-0 focus:outline-none font-mono text-[11px] uppercase tracking-[0.1em] text-db-chalk-dim hover:text-db-chalk cursor-pointer py-2 pr-1"
                >
                    {(Object.keys(SORT_LABEL) as SortBy[]).map(k => (
                        <option key={k} value={k} className="bg-db-slate-3 text-db-chalk">
                            {SORT_LABEL[k]}
                        </option>
                    ))}
                </select>
            </div>
        </nav>
    )
}

interface PillProps {
    active: boolean
    onClick: () => void
    state: 'active' | 'upcoming' | 'ended' | 'all' | 'all-status'
    category?: Category
    children: React.ReactNode
}

function FilterPill({ active, onClick, state, children }: PillProps) {
    // Status-pill active states mirror the card grammar.
    const activeClass = !active
        ? ''
        : state === 'active'
            ? 'bg-db-segnale text-white border-db-segnale'
            : state === 'upcoming'
                ? 'bg-transparent text-db-oltremare shadow-[inset_0_0_0_1px_var(--color-db-oltremare)]'
                : state === 'ended'
                    ? 'bg-db-slate-4 text-db-mute'
                    : 'bg-db-slate text-db-chalk'

    return (
        <button
            type="button"
            onClick={onClick}
            className={[
                'px-4 py-2.5 font-mono text-[11px] uppercase tracking-[0.1em]',
                'border-r border-db-rule last:border-r-0',
                'inline-flex items-center gap-2',
                'transition-[background,color,border-color] duration-100',
                active ? activeClass : 'bg-transparent text-db-chalk-dim hover:bg-db-slate hover:text-db-chalk',
            ].join(' ')}
        >
            {children}
        </button>
    )
}

/* ────────────────────────────────────────────────────────────────────── */
/* Page                                                                    */
/* ────────────────────────────────────────────────────────────────────── */

export default function Home() {
    // wagmi useReadContract returns isLoading too — drives the skeleton state.
    const { data: polls, isLoading: isLoadingPolls } = useAllPolls()
    const pollsArray = (polls as PollInfo[]) || []

    const [cat, setCat] = useState<CategoryFilter>('all')
    const [status, setStatus] = useState<StatusFilter>('active')
    const [searchQuery, setSearchQuery] = useState('')
    const [sortBy, setSortBy] = useState<SortBy>('newest')

    // Decorate each poll with its derived category + phase once, then filter.
    const decorated = useMemo(
        () =>
            pollsArray.map(p => ({
                poll: p,
                category: deriveCategory(p.pollAddress),
                phase: derivePhase(p),
            })),
        [pollsArray],
    )

    const filtered = useMemo(() => {
        const q = searchQuery.trim().toLowerCase()
        const matchedByCatAndStatus = decorated.filter(d => {
            const catMatch = cat === 'all' || d.category === cat
            const statusMatch = status === 'all' || d.phase === status
            return catMatch && statusMatch
        })
        const matchedBySearch = q
            ? matchedByCatAndStatus.filter(
                  d =>
                      d.poll.title.toLowerCase().includes(q) ||
                      d.poll.description.toLowerCase().includes(q),
              )
            : matchedByCatAndStatus

        // Sort — clone first so we don't mutate the memo.
        const sorted = [...matchedBySearch]
        switch (sortBy) {
            case 'newest':
                sorted.sort((a, b) => Number(b.poll.createdAt - a.poll.createdAt))
                break
            case 'oldest':
                sorted.sort((a, b) => Number(a.poll.createdAt - b.poll.createdAt))
                break
            case 'title-asc':
                sorted.sort((a, b) => a.poll.title.localeCompare(b.poll.title))
                break
            case 'title-desc':
                sorted.sort((a, b) => b.poll.title.localeCompare(a.poll.title))
                break
        }
        return sorted
    }, [decorated, cat, status, searchQuery, sortBy])

    const counts = useMemo(() => {
        let active = 0
        let upcoming = 0
        let ended = 0
        for (const d of decorated) {
            if (d.phase === 'active') active++
            else if (d.phase === 'upcoming') upcoming++
            else ended++
        }
        return { active, upcoming, ended, total: decorated.length }
    }, [decorated])

    return (
        <div className="text-db-chalk">
            <WatermarkSymbols />

            {/* Page head */}
            <section className="flex flex-wrap items-end justify-between gap-8 mb-9">
                <div>
                    <h1 className="font-sans font-extrabold text-[clamp(48px,8vw,80px)] tracking-[-0.035em] leading-[0.94] text-db-chalk">
                        POLLS
                    </h1>
                    <p className="mt-3 text-db-chalk-dim text-[14px] leading-[1.6] max-w-[48ch]">
                        Active proposals across the community.
                        <span className="text-db-mute">
                            {' '}
                            {counts.total} total · {counts.active} active · {counts.upcoming} upcoming ·{' '}
                            {counts.ended} ended.
                        </span>
                    </p>
                </div>
                <Link
                    to="/create"
                    className="inline-flex items-center gap-2.5 px-3.5 py-2.5 border border-db-rule bg-db-slate-3 font-mono text-[11px] text-db-chalk-dim uppercase tracking-[0.1em] hover:border-db-chalk hover:text-db-chalk transition-colors no-underline"
                >
                    <Plus className="w-3 h-3" />
                    <span>New poll</span>
                    <ChevronDown className="w-3 h-3 text-db-mute" />
                </Link>
            </section>

            {/* Filter strip */}
            <FilterStrip
                cat={cat}
                setCat={setCat}
                status={status}
                setStatus={setStatus}
                searchQuery={searchQuery}
                setSearchQuery={setSearchQuery}
                sortBy={sortBy}
                setSortBy={setSortBy}
            />

            {/* Card grid — skeleton while loading; empty state if nothing matches. */}
            {isLoadingPolls && pollsArray.length === 0 ? (
                <PollCardSkeletons />
            ) : filtered.length === 0 ? (
                <EmptyState totalPolls={pollsArray.length} status={status} cat={cat} />
            ) : (
                <section
                    aria-label="Poll cards"
                    className="grid gap-4 mb-8"
                    style={{
                        gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))',
                    }}
                >
                    {filtered.map(d => (
                        <PollCard
                            key={d.poll.pollAddress}
                            poll={d.poll}
                            category={d.category}
                            phase={d.phase}
                        />
                    ))}
                </section>
            )}

            {/* Foot count */}
            {filtered.length > 0 && (
                <footer className="flex flex-wrap items-center justify-between gap-3.5 mt-2 pt-4 border-t border-db-rule-soft">
                    <span className="font-mono text-[11px] text-db-mute uppercase tracking-[0.14em]">
                        Showing <b className="text-db-chalk-dim font-semibold">{filtered.length}</b> of{' '}
                        <b className="text-db-chalk-dim font-semibold">{counts.total}</b> polls ·{' '}
                        <b className="text-db-chalk-dim font-semibold">{counts.active}</b> active ·{' '}
                        <b className="text-db-chalk-dim font-semibold">{counts.upcoming}</b> upcoming ·{' '}
                        <b className="text-db-chalk-dim font-semibold">{counts.ended}</b> ended
                    </span>
                </footer>
            )}
        </div>
    )
}

/**
 * Loading skeleton — shown while useAllPolls is fetching its first batch.
 * Replaces the previous "blank panel until data loads" with shape-matched
 * shimmers so the user knows content is coming, not broken.
 */
function PollCardSkeletons() {
    return (
        <section
            aria-label="Loading polls"
            aria-busy="true"
            className="grid gap-4 mb-8"
            style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))' }}
        >
            {[0, 1, 2].map(i => (
                <div
                    key={i}
                    className="relative border border-db-rule bg-db-slate p-5 h-[260px] flex flex-col gap-4 overflow-hidden"
                >
                    {/* Top accent strip */}
                    <div className="absolute left-0 right-0 top-0 h-1 bg-db-rule" />
                    {/* Header row */}
                    <div className="flex items-center justify-between">
                        <div className="h-3 w-16 bg-db-rule animate-pulse" />
                        <div className="h-3 w-12 bg-db-rule animate-pulse" />
                    </div>
                    {/* Title */}
                    <div className="space-y-2 mt-4">
                        <div className="h-5 w-3/4 bg-db-rule animate-pulse" />
                        <div className="h-5 w-1/2 bg-db-rule animate-pulse" />
                    </div>
                    {/* Body line */}
                    <div className="space-y-2 mt-auto">
                        <div className="h-3 w-2/3 bg-db-rule animate-pulse" />
                        <div className="h-3 w-1/3 bg-db-rule animate-pulse" />
                    </div>
                </div>
            ))}
        </section>
    )
}

function EmptyState({
    totalPolls,
    status,
    cat,
}: {
    totalPolls: number
    status: StatusFilter
    cat: CategoryFilter
}) {
    const filtered = totalPolls > 0
    return (
        <div className="flex flex-col items-center justify-center py-16 px-8 border border-db-rule bg-db-slate-3 text-center">
            <FileText className="w-12 h-12 text-db-mute-dim mb-3" />
            <h3 className="font-sans font-bold text-[18px] tracking-[-0.01em] text-db-chalk mb-2">
                {filtered ? 'No polls match this filter' : 'No polls yet'}
            </h3>
            <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-db-mute mb-6 max-w-sm">
                {filtered
                    ? `${status !== 'all' ? status : ''}${
                        status !== 'all' && cat !== 'all' ? ' · ' : ''
                    }${cat !== 'all' ? CATEGORY_LABEL[cat] : ''} returned 0 results`
                    : 'Be the first to open a proposal'}
            </p>
            <Link
                to="/create"
                className="inline-flex items-center gap-2 px-4 py-2.5 border border-db-rule bg-db-slate hover:bg-db-slate-2 hover:border-db-chalk text-db-chalk font-mono text-[11px] uppercase tracking-[0.12em] no-underline transition-colors"
            >
                <Plus className="w-3.5 h-3.5" />
                Create poll
            </Link>
        </div>
    )
}
