import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAccount } from 'wagmi'
import { encodeFunctionData } from 'viem'
import { SEMAPHORE_ADDRESS } from '../config'
import { useCreatePoll } from '../hooks/useRegistry'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'
import ZkBlindVotingABI from '../abi/ZkBlindVoting.json'
import {
    ArrowLeft,
    ShieldCheck,
    EyeOff,
    Plus,
    X,
    AlertTriangle,
    Send,
} from 'lucide-react'
import { CreateFeedback } from '../components/create/CreateFeedback'
import { PreviewPanel } from '../components/create/PreviewPanel'
import { HowItWorks } from '../components/create/HowItWorks'
import { PollTemplatesPicker, type PollTemplate } from '../components/create/PollTemplates'
import { getOptionTone } from '../lib/createOptionTone'
import creativeDesigner from '../assets/illustrations/creative-designer.svg'

type PollType = 'anon-vote' | 'blind-vote'

export default function CreatePoll() {
    // ---- Data layer (preserved verbatim from pre-Impl-4 implementation) ----
    const { address, isConnected } = useAccount()
    const navigate = useNavigate()
    const [title, setTitle] = useState('')
    const [description, setDescription] = useState('')
    const [options, setOptions] = useState<string[]>(['', ''])
    const [errorMsg, setErrorMsg] = useState('')
    const [pollType, setPollType] = useState<PollType>('anon-vote')
    const [revealDuration, setRevealDuration] = useState(3600)

    const { createPoll, isPending, isConfirming, isSuccess } = useCreatePoll()

    async function handleCreatePoll(e: React.FormEvent) {
        e.preventDefault()
        setErrorMsg('')
        if (!address) return
        const validOptions = options.filter(o => o.trim() !== '')
        if (validOptions.length < 2) {
            setErrorMsg('Please provide at least 2 options.')
            return
        }

        try {
            let initData: `0x${string}`
            if (pollType === 'blind-vote') {
                initData = encodeFunctionData({
                    abi: ZkBlindVotingABI.abi,
                    functionName: 'initialize',
                    args: [address, validOptions, BigInt(revealDuration)],
                }) as `0x${string}`
            } else {
                initData = encodeFunctionData({
                    abi: ZkAnonVotingABI.abi,
                    functionName: 'initialize',
                    args: [SEMAPHORE_ADDRESS, address, validOptions],
                }) as `0x${string}`
            }

            await createPoll(pollType, title, description, initData)
            setTitle('')
            setDescription('')
            setOptions(['', ''])
            // Navigate home after short delay to show success
            setTimeout(() => navigate('/'), 1500)
        } catch (err: unknown) {
            const e = err as { shortMessage?: string; message?: string }
            setErrorMsg(e.shortMessage ?? e.message ?? 'Transaction failed.')
        }
    }

    const updateOption = (index: number, value: string) => {
        const updated = [...options]
        updated[index] = value
        setOptions(updated)
    }

    const addOption = () => setOptions([...options, ''])

    const removeOption = (index: number) => {
        if (options.length <= 2) return
        setOptions(options.filter((_, i) => i !== index))
    }

    function applyTemplate(template: PollTemplate) {
        // Replace ALL form state — the user can edit afterwards.
        // Confirm only when the form has user-typed content; otherwise just apply.
        const formIsDirty = title.trim() !== '' || description.trim() !== '' ||
            options.some(o => o.trim() !== '')
        if (formIsDirty && !confirm('Apply template? This will replace the current form values.')) return

        setTitle(template.title)
        setDescription(template.description)
        setOptions(template.options.length >= 2 ? [...template.options] : ['', ''])
        setPollType(template.pollType)
        setErrorMsg('')
    }

    const validOptions = options.filter(o => o.trim() !== '')
    // ---- End preserved data layer ----------------------------------------

    const optionsLegendIndex = pollType === 'blind-vote' ? '05' : '04'
    const allowListCaption =
        pollType === 'anon-vote'
            ? 'voters are added later · admin generates invite tokens after the poll is deployed'
            : 'registration opens automatically · voters add themselves by wallet address during the registration phase'

    return (
        <div className="space-y-6">
            {/* -- Breadcrumb ----------------------------------------------- */}
            <div className="flex items-center gap-2 py-4 border-b border-db-rule animate-fade-in-up">
                <Link
                    to="/"
                    className="text-db-mute hover:text-db-chalk font-mono text-[11px] tracking-[0.16em] uppercase flex items-center gap-1.5 transition-colors"
                >
                    <ArrowLeft className="w-3.5 h-3.5" />
                    Dashboard
                </Link>
                <span className="text-db-rule font-mono text-[11px]">/</span>
                <span className="font-mono text-[11px] text-db-chalk tracking-[0.16em] uppercase">CREATE POLL</span>
            </div>

            {/* -- 12-col form-builder poster ------------------------------- */}
            <div className="grid grid-cols-1 lg:grid-cols-12 gap-px lg:gap-8 bg-db-rule lg:bg-transparent">
                {/* -- Form region (8 cols) -------------------------------- */}
                <div className="relative lg:col-span-8 bg-db-void p-6 lg:p-10 space-y-8 overflow-hidden animate-fade-in-up">
                    {/* Watermark — desktop only, behind hero (per MANIFEST) */}
                    <img
                        src={creativeDesigner}
                        alt=""
                        aria-hidden="true"
                        className="hidden lg:block absolute top-0 right-0 w-[300px] opacity-15 pointer-events-none select-none"
                    />

                    {/* Hero */}
                    <header className="relative">
                        <h1 className="font-sans font-extrabold text-[clamp(36px,5vw,64px)] leading-[1.05] tracking-[-0.02em] text-db-chalk uppercase">
                            Create<br />a new poll
                        </h1>
                        <div className="w-16 h-px bg-db-segnale mt-4 mb-4" />
                        <p className="font-mono text-[12px] text-db-mute leading-relaxed max-w-[480px]">
                            Configure poll metadata, options, and visibility. The poll is published on-chain in a single transaction.
                        </p>
                    </header>

                    {/* Feedback messages (above the form, not inside) */}
                    {(isPending || isConfirming || isSuccess || errorMsg) && (
                        <div className="space-y-2 relative">
                            {isPending && <CreateFeedback type="pending">submitting transaction…</CreateFeedback>}
                            {isConfirming && <CreateFeedback type="pending">awaiting on-chain confirmation…</CreateFeedback>}
                            {isSuccess && <CreateFeedback type="success">poll deployed · redirecting to dashboard…</CreateFeedback>}
                            {errorMsg && <CreateFeedback type="error">{errorMsg}</CreateFeedback>}
                        </div>
                    )}

                    {/* -- Form: hairline-rule fields, no inner card ------- */}
                    <form onSubmit={handleCreatePoll} className="space-y-6 relative">
                        {/* 00 · Templates — pre-fills the form for common archetypes */}
                        <PollTemplatesPicker onApply={applyTemplate} />

                        {/* 01 · Title — hairline-bottom-rule, 24px Inter 800 echo */}
                        <div className="flex flex-col gap-2 pb-6 border-b border-db-rule">
                            <label
                                htmlFor="poll-title"
                                className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em] flex items-center gap-2"
                            >
                                <span>01 · TITLE</span>
                                <span className="text-db-segnale">*</span>
                            </label>
                            <input
                                id="poll-title"
                                type="text"
                                placeholder="e.g., Q3 Treasury Allocation"
                                value={title}
                                onChange={e => setTitle(e.target.value)}
                                className="bg-transparent border-0 border-b border-db-rule focus:border-db-segnale focus:outline-none px-0 py-3 text-db-chalk placeholder:text-db-mute font-sans font-extrabold text-[24px] tracking-[-0.01em] caret-db-segnale"
                                required
                            />
                        </div>

                        {/* 02 · Description */}
                        <div className="flex flex-col gap-2 pb-6 border-b border-db-rule">
                            <label
                                htmlFor="poll-description"
                                className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em] flex items-center gap-2"
                            >
                                <span>02 · DESCRIPTION</span>
                                <span className="font-mono text-[10px] text-db-mute normal-case opacity-60">(optional)</span>
                            </label>
                            <textarea
                                id="poll-description"
                                placeholder="What is this poll about?"
                                value={description}
                                onChange={e => setDescription(e.target.value)}
                                rows={3}
                                className="bg-transparent border-0 border-b border-db-rule focus:border-db-segnale focus:outline-none px-0 py-2 text-db-chalk placeholder:text-db-mute font-mono text-[13px] leading-relaxed caret-db-segnale resize-y"
                            />
                        </div>

                        {/* 03 · Poll type — mono ( ) / (•) radio glyphs */}
                        <div className="flex flex-col gap-3 pb-6 border-b border-db-rule">
                            <span className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em]">03 · POLL TYPE</span>
                            <div
                                role="radiogroup"
                                aria-label="Poll type"
                                className="grid grid-cols-1 sm:grid-cols-2 gap-px bg-db-rule"
                            >
                                <button
                                    type="button"
                                    role="radio"
                                    aria-checked={pollType === 'anon-vote'}
                                    onClick={() => setPollType('anon-vote')}
                                    className={`p-5 flex flex-col gap-3 text-left transition-colors cursor-pointer ${
                                        pollType === 'anon-vote'
                                            ? 'bg-db-slate border-l-2 border-db-segnale'
                                            : 'bg-db-void hover:bg-db-slate border-l-2 border-transparent'
                                    }`}
                                >
                                    <div className="flex items-center gap-3">
                                        <span className="font-mono text-[14px] text-db-segnale" aria-hidden="true">
                                            {pollType === 'anon-vote' ? '(•)' : '( )'}
                                        </span>
                                        <ShieldCheck
                                            className={`w-4 h-4 ${pollType === 'anon-vote' ? 'text-db-segnale' : 'text-db-mute'}`}
                                        />
                                        <span className="font-sans font-extrabold text-[14px] tracking-[0.05em] uppercase text-db-chalk">
                                            Anonymous · ZK
                                        </span>
                                    </div>
                                    <p className="font-mono text-[11px] text-db-mute leading-relaxed">
                                        Zero-knowledge proofs. Admin distributes invite tokens. No on-chain link between identity and vote.
                                    </p>
                                </button>

                                <button
                                    type="button"
                                    role="radio"
                                    aria-checked={pollType === 'blind-vote'}
                                    onClick={() => setPollType('blind-vote')}
                                    className={`p-5 flex flex-col gap-3 text-left transition-colors cursor-pointer ${
                                        pollType === 'blind-vote'
                                            ? 'bg-db-slate border-l-2 border-db-oltremare'
                                            : 'bg-db-void hover:bg-db-slate border-l-2 border-transparent'
                                    }`}
                                >
                                    <div className="flex items-center gap-3">
                                        <span className="font-mono text-[14px] text-db-oltremare" aria-hidden="true">
                                            {pollType === 'blind-vote' ? '(•)' : '( )'}
                                        </span>
                                        <EyeOff
                                            className={`w-4 h-4 ${pollType === 'blind-vote' ? 'text-db-oltremare' : 'text-db-mute'}`}
                                        />
                                        <span className="font-sans font-extrabold text-[14px] tracking-[0.05em] uppercase text-db-chalk">
                                            Blind · Commit-Reveal
                                        </span>
                                    </div>
                                    <p className="font-mono text-[11px] text-db-mute leading-relaxed">
                                        Votes sealed until reveal phase. Address-based registration. No invite token needed.
                                    </p>
                                </button>
                            </div>
                        </div>

                        {/* 04 · Reveal window — blind only */}
                        {pollType === 'blind-vote' && (
                            <div className="flex flex-col gap-2 pb-6 border-b border-db-rule animate-fade-in-up">
                                <label
                                    htmlFor="reveal-duration"
                                    className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em]"
                                >
                                    04 · REVEAL WINDOW <span className="opacity-60 normal-case">(seconds)</span>
                                </label>
                                <input
                                    id="reveal-duration"
                                    type="number"
                                    min={60}
                                    value={revealDuration}
                                    onChange={e => setRevealDuration(Number(e.target.value))}
                                    className="w-48 bg-transparent border-0 border-b border-db-rule focus:border-db-oltremare focus:outline-none px-0 py-3 text-db-chalk font-sans font-extrabold text-[24px] tabular-nums caret-db-oltremare"
                                />
                                <p className="font-mono text-[11px] text-db-mute">default: 3600 (1 hour) · minimum: 60s</p>
                            </div>
                        )}

                        {/* 04/05 · Voting options — dynamic list, per-index colours */}
                        <fieldset className="flex flex-col gap-3 pb-6 border-b border-db-rule">
                            <legend className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em]">
                                {optionsLegendIndex} · VOTING OPTIONS <span className="opacity-60 normal-case">(min 2)</span>
                            </legend>
                            <div className="flex flex-col gap-px bg-db-rule">
                                {options.map((opt, i) => {
                                    const tone = getOptionTone(i)
                                    return (
                                        <div key={i} className="flex items-center gap-4 bg-db-void px-4 py-3">
                                            <label htmlFor={`option-${i}`} className="sr-only">
                                                Option {i + 1}
                                            </label>
                                            <span className={`font-sans font-extrabold text-[14px] tabular-nums w-8 shrink-0 ${tone.text}`}>
                                                {String(i + 1).padStart(2, '0')}
                                            </span>
                                            <input
                                                id={`option-${i}`}
                                                type="text"
                                                placeholder={`Option ${i + 1}`}
                                                value={opt}
                                                onChange={e => updateOption(i, e.target.value)}
                                                className="flex-1 bg-transparent border-0 focus:outline-none px-0 py-2 text-db-chalk placeholder:text-db-mute font-mono text-[14px] caret-db-segnale"
                                                required
                                            />
                                            {options.length > 2 && (
                                                <button
                                                    type="button"
                                                    onClick={() => removeOption(i)}
                                                    className="text-db-mute hover:text-db-segnale font-mono text-[11px] tracking-[0.12em] uppercase flex items-center gap-1 cursor-pointer transition-colors shrink-0"
                                                    aria-label={`Remove option ${i + 1}`}
                                                >
                                                    <X className="w-3.5 h-3.5" /> REMOVE
                                                </button>
                                            )}
                                        </div>
                                    )
                                })}
                            </div>
                            <button
                                type="button"
                                onClick={addOption}
                                className="self-start inline-flex items-center gap-2 bg-db-slate hover:bg-db-rule text-db-chalk border border-db-rule font-sans font-extrabold text-[11px] tracking-[0.18em] uppercase px-4 py-2.5 transition-colors cursor-pointer"
                            >
                                <Plus className="w-3.5 h-3.5" />
                                ADD OPTION
                            </button>
                        </fieldset>

                        {/*
                         * NOTE: the original design hint mentioned an "allow-list" field at
                         * poll-creation time. The underlying contract surface (see
                         * `handleCreatePoll` above + ZkAnonVoting.initialize /
                         * ZkBlindVoting.initialize ABI args) does NOT accept an allow-list at
                         * create-time — invite tokens are generated post-creation (anon path)
                         * and registration is open-by-address (blind path). The caption below
                         * is the documented fallback (spec §2.2) so users see where voters
                         * actually come from. Adding a real allow-list field would require a
                         * contract change, out of Impl-4 scope.
                         */}
                        <p className="font-mono text-[11px] text-db-mute leading-relaxed border-l-2 border-db-mute pl-3 pb-6 border-b border-db-rule">
                            {allowListCaption}
                        </p>

                        {/* Deploy (8 cols) + Cancel (4 cols) footer row */}
                        <div className="grid grid-cols-12 gap-px bg-db-rule">
                            <button
                                type="submit"
                                disabled={!isConnected || isPending || isConfirming}
                                className="col-span-12 sm:col-span-8 bg-db-segnale hover:bg-db-segnale/90 text-db-void font-sans font-extrabold text-[14px] tracking-[0.20em] uppercase px-6 py-5 flex items-center justify-between transition-colors disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
                            >
                                <span>
                                    {!isConnected
                                        ? 'CONNECT WALLET TO DEPLOY'
                                        : isPending
                                            ? 'SUBMITTING TX…'
                                            : isConfirming
                                                ? 'CONFIRMING…'
                                                : 'DEPLOY POLL ON-CHAIN'}
                                </span>
                                <Send className="w-4 h-4" />
                            </button>
                            <Link
                                to="/"
                                className="col-span-12 sm:col-span-4 bg-db-slate hover:bg-db-rule text-db-mute hover:text-db-chalk font-sans font-extrabold text-[14px] tracking-[0.20em] uppercase px-6 py-5 flex items-center justify-center transition-colors"
                            >
                                CANCEL
                            </Link>
                        </div>
                    </form>
                </div>

                {/* -- Sidebar (4 cols) ----------------------------------- */}
                <aside className="lg:col-span-4 bg-db-void p-6 lg:p-10 space-y-6 animate-fade-in-up animate-fade-in-up-2">
                    <PreviewPanel
                        title={title}
                        description={description}
                        pollType={pollType}
                        validOptions={validOptions}
                    />

                    <HowItWorks pollType={pollType} />

                    {!isConnected && (
                        <div className="bg-db-slate border-l-2 border-db-segnale p-5 flex items-start gap-3">
                            <AlertTriangle className="w-4 h-4 text-db-segnale shrink-0 mt-0.5" />
                            <div className="space-y-1">
                                <p className="font-sans font-extrabold text-[12px] tracking-[0.12em] uppercase text-db-chalk">
                                    Wallet not connected
                                </p>
                                <p className="font-mono text-[11px] text-db-mute leading-relaxed">
                                    Connect your wallet using the button in the header to deploy a poll.
                                </p>
                            </div>
                        </div>
                    )}
                </aside>
            </div>
        </div>
    )
}
