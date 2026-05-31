import { useEffect, useState } from 'react'
import { useSearchParams, Link } from 'react-router-dom'
import { ShieldCheck, ShieldAlert, ShieldQuestion, Loader2, ArrowLeft, ArrowUpRight } from 'lucide-react'
import { config } from '../config'
import { getPublicClient } from 'wagmi/actions'
import ZkAnonVotingABI from '../abi/ZkAnonVoting.json'

/**
 * Receipt verifier — anyone (no wallet) can confirm a voter receipt by
 * scanning the QR or opening the URL. Reads the public `isNullifierUsed`
 * mapping on the named poll contract. Does NOT reveal which option the
 * voter chose — the verifier confirms participation only, matching the
 * receipt-freeness contract documented in ReceiptModal.tsx.
 *
 * URL: /verify?poll=0x...&nullifier=<decimalString>&block=<n>
 *
 * The `block` query param is informational (shown to the user as "claimed
 * block"); the on-chain check is independent of it (the mapping is current
 * state, not block-scoped).
 */

type Verdict =
    | { kind: 'idle' }
    | { kind: 'loading' }
    | { kind: 'verified'; pollAddress: string; nullifier: string; claimedBlock: string | null }
    | { kind: 'not-found'; pollAddress: string; nullifier: string }
    | { kind: 'error'; message: string }

function isValidAddress(s: string | null): s is string {
    return Boolean(s && /^0x[a-fA-F0-9]{40}$/.test(s))
}

function isValidDecimal(s: string | null): s is string {
    return Boolean(s && /^\d+$/.test(s))
}

export default function Verify() {
    const [params] = useSearchParams()
    const poll = params.get('poll')
    const nullifier = params.get('nullifier')
    const claimedBlock = params.get('block')

    const [verdict, setVerdict] = useState<Verdict>({ kind: 'idle' })

    useEffect(() => {
        let cancelled = false
        async function run() {
            if (!poll || !nullifier) {
                setVerdict({ kind: 'error', message: 'Missing required URL parameters: poll, nullifier' })
                return
            }
            if (!isValidAddress(poll)) {
                setVerdict({ kind: 'error', message: `Invalid poll address shape: ${poll}` })
                return
            }
            if (!isValidDecimal(nullifier)) {
                const sample = String(nullifier).slice(0, 32)
                setVerdict({ kind: 'error', message: `Invalid nullifier — expected decimal string, got: ${sample}` })
                return
            }
            setVerdict({ kind: 'loading' })
            try {
                const client = getPublicClient(config)
                if (!client) throw new Error('No public client configured')
                const used = await client.readContract({
                    address: poll as `0x${string}`,
                    abi: ZkAnonVotingABI.abi,
                    functionName: 'isNullifierUsed',
                    args: [BigInt(nullifier)],
                })
                if (cancelled) return
                if (used) {
                    setVerdict({ kind: 'verified', pollAddress: poll, nullifier, claimedBlock })
                } else {
                    setVerdict({ kind: 'not-found', pollAddress: poll, nullifier })
                }
            } catch (e) {
                if (cancelled) return
                const msg = (e as { shortMessage?: string; message?: string })
                setVerdict({ kind: 'error', message: msg.shortMessage ?? msg.message ?? 'On-chain read failed' })
            }
        }
        void run()
        return () => { cancelled = true }
    }, [poll, nullifier, claimedBlock])

    return (
        <div className="text-db-chalk max-w-3xl mx-auto">
            <div className="py-4 border-b border-db-rule mb-8">
                <Link
                    to="/"
                    className="text-db-mute hover:text-db-chalk font-mono text-[11px] tracking-[0.16em] uppercase inline-flex items-center gap-1.5"
                >
                    <ArrowLeft className="w-3.5 h-3.5" />
                    Voting Hub
                </Link>
            </div>

            <header className="mb-10">
                <h1 className="font-sans font-extrabold text-[clamp(40px,6vw,72px)] tracking-[-0.03em] leading-[0.95]">
                    VERIFY
                    <br />
                    A VOTE
                </h1>
                <p className="mt-4 font-mono text-[12px] text-db-mute leading-relaxed max-w-[60ch]">
                    Anyone — no wallet required — can confirm whether a given nullifier was
                    spent in the named poll. This proves the holder of the receipt voted, but
                    NOT which option they chose.
                </p>
            </header>

            <VerdictPanel verdict={verdict} />

            <ReceiptDetails poll={poll} nullifier={nullifier} block={claimedBlock} />

            <div className="mt-12 border-t border-db-rule pt-6 font-mono text-[11px] text-db-mute leading-relaxed">
                <p>
                    <strong className="text-db-chalk-dim">How this works:</strong>{' '}
                    Each Semaphore vote burns a unique nullifier on the poll contract — a public
                    mapping (`isNullifierUsed`). We call that mapping with the supplied nullifier and
                    return the result. There is no link from nullifier → voter address, and the vote
                    direction (which option) is never embedded in the receipt.
                </p>
            </div>
        </div>
    )
}

function VerdictPanel({ verdict }: { verdict: Verdict }) {
    if (verdict.kind === 'idle' || verdict.kind === 'loading') {
        return (
            <div className="bg-db-slate border border-db-rule p-6 flex items-center gap-3 mb-8">
                <Loader2 className="w-5 h-5 text-db-mute animate-spin" />
                <span className="font-mono text-[12px] text-db-chalk-dim uppercase tracking-[0.12em]">
                    {verdict.kind === 'idle' ? 'Awaiting verification…' : 'Reading from chain…'}
                </span>
            </div>
        )
    }
    if (verdict.kind === 'verified') {
        return (
            <div className="bg-db-slate border-l-2 border-db-success p-6 mb-8 relative">
                <div className="absolute left-0 right-0 top-0 h-1 bg-db-success" />
                <div className="flex items-start gap-4">
                    <ShieldCheck className="w-10 h-10 text-db-success shrink-0 mt-1" />
                    <div>
                        <p className="font-sans font-extrabold text-[20px] tracking-[-0.01em] uppercase text-db-chalk">
                            Vote Verified
                        </p>
                        <p className="font-mono text-[12px] text-db-chalk-dim leading-relaxed mt-2">
                            The supplied nullifier IS recorded on the named poll contract. The
                            holder of this receipt cast a valid ZK vote. Vote direction (which
                            option) remains private by Semaphore design.
                        </p>
                    </div>
                </div>
            </div>
        )
    }
    if (verdict.kind === 'not-found') {
        return (
            <div className="bg-db-slate border-l-2 border-db-segnale p-6 mb-8 relative">
                <div className="absolute left-0 right-0 top-0 h-1 bg-db-segnale" />
                <div className="flex items-start gap-4">
                    <ShieldAlert className="w-10 h-10 text-db-segnale shrink-0 mt-1" />
                    <div>
                        <p className="font-sans font-extrabold text-[20px] tracking-[-0.01em] uppercase text-db-chalk">
                            Not Found
                        </p>
                        <p className="font-mono text-[12px] text-db-chalk-dim leading-relaxed mt-2">
                            The supplied nullifier is NOT recorded on this poll contract. The
                            receipt may be forged, the poll may be wrong, or the vote may have
                            been on a different chain.
                        </p>
                    </div>
                </div>
            </div>
        )
    }
    return (
        <div className="bg-db-slate border-l-2 border-db-mute p-6 mb-8">
            <div className="flex items-start gap-4">
                <ShieldQuestion className="w-10 h-10 text-db-mute shrink-0 mt-1" />
                <div>
                    <p className="font-sans font-extrabold text-[16px] tracking-[-0.01em] uppercase text-db-chalk">
                        Verification Error
                    </p>
                    <p className="font-mono text-[11px] text-db-mute leading-relaxed mt-2">{verdict.message}</p>
                </div>
            </div>
        </div>
    )
}

function ReceiptDetails({
    poll,
    nullifier,
    block,
}: {
    poll: string | null
    nullifier: string | null
    block: string | null
}) {
    return (
        <dl className="space-y-3 font-mono text-[12px] border border-db-rule p-5 bg-db-slate-3">
            <Row label="Poll address" value={poll} />
            <Row label="Nullifier (claimed)" value={nullifier} />
            <Row label="Block (claimed)" value={block} />
            {poll && (
                <div className="pt-2 mt-2 border-t border-db-rule">
                    <Link
                        to={`/poll/${poll}`}
                        className="font-mono text-[11px] text-db-segnale hover:text-db-chalk uppercase tracking-[0.16em] inline-flex items-center gap-1"
                    >
                        Open this poll <ArrowUpRight className="w-3.5 h-3.5" />
                    </Link>
                </div>
            )}
        </dl>
    )
}

function Row({ label, value }: { label: string; value: string | null }) {
    return (
        <div>
            <dt className="text-db-mute uppercase tracking-[0.18em] text-[10px] mb-1">{label}</dt>
            <dd className="text-db-chalk-dim break-all">{value ?? <em className="text-db-mute-dim">—</em>}</dd>
        </div>
    )
}
