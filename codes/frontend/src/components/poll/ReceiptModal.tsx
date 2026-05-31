import { useState } from 'react'
import { QRCode } from 'react-qr-code'
import { ShieldCheck, Download, FileText, Copy, X, Check } from 'lucide-react'

/**
 * Cryptographic Voter Receipt — flagship feature.
 *
 * Privacy contract:
 *   - The receipt PROVES participation (this nullifier was spent in this poll).
 *   - The receipt does NOT reveal the vote DIRECTION (which option you chose).
 *
 * This is the property Aragon explicitly avoids (their MACI design enforces
 * "receipt-freeness" to prevent vote-buying). Semaphore's nullifier model lets
 * us thread the needle: anyone with the nullifier + poll address can call the
 * contract's public `isNullifierUsed` mapping and confirm the vote happened —
 * but the option-index is never embedded in the receipt artifact.
 *
 * Verification path: third party scans the QR code → opens /verify → page
 * reads the contract's isNullifierUsed mapping → ✓/✗ result. No wallet needed.
 *
 * The optionLabel field IS shown to the voter for personal reference but is
 * marked clearly as "private — not in the QR or shared receipt." It's omitted
 * from the JSON / PDF / QR exports.
 */

export interface VoterReceipt {
    pollAddress: string
    pollTitle: string
    nullifier: string         // Decimal string (Semaphore nullifier hash)
    txHash: string
    blockNumber: bigint
    timestamp: number          // ms since epoch, when the modal first rendered
    optionLabel?: string       // Voter's personal record only — never exported
    chainId: number
    appOrigin: string          // For verifier URL
}

interface Props {
    receipt: VoterReceipt
    onClose: () => void
}

function shortHex(h: string, head = 8, tail = 6): string {
    if (h.length <= head + tail + 2) return h
    return `${h.slice(0, head)}…${h.slice(-tail)}`
}

function buildVerifyUrl(r: VoterReceipt): string {
    const params = new URLSearchParams({
        poll: r.pollAddress,
        nullifier: r.nullifier,
        block: r.blockNumber.toString(),
    })
    return `${r.appOrigin}/verify?${params.toString()}`
}

function buildReceiptJson(r: VoterReceipt): string {
    // Deliberately omits `optionLabel` — receipt is privacy-preserving for
    // direction. Anyone reading the JSON can verify participation, NOT choice.
    const payload = {
        version: 1,
        kind: 'voter-receipt-zk',
        protocol: 'Semaphore-v4',
        pollAddress: r.pollAddress,
        pollTitle: r.pollTitle,
        nullifier: r.nullifier,
        txHash: r.txHash,
        blockNumber: r.blockNumber.toString(),
        timestamp: new Date(r.timestamp).toISOString(),
        chainId: r.chainId,
        verifyUrl: buildVerifyUrl(r),
        notice:
            'This receipt proves the holder voted in the named poll. It does NOT prove which option was selected.',
    }
    return JSON.stringify(payload, null, 2)
}

export function ReceiptModal({ receipt, onClose }: Props) {
    const [copied, setCopied] = useState<'nullifier' | 'verify' | null>(null)
    const [pdfBusy, setPdfBusy] = useState(false)
    const [pdfError, setPdfError] = useState<string | null>(null)

    const verifyUrl = buildVerifyUrl(receipt)

    function downloadJson() {
        const blob = new Blob([buildReceiptJson(receipt)], { type: 'application/json' })
        const url = URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        a.download = `vote-receipt-${receipt.pollAddress.slice(0, 10)}-${receipt.blockNumber}.json`
        document.body.appendChild(a)
        a.click()
        a.remove()
        // Revoke async so the download has time to start.
        setTimeout(() => URL.revokeObjectURL(url), 1000)
    }

    async function downloadPdf() {
        setPdfBusy(true)
        setPdfError(null)
        try {
            // Dynamic import — keeps jsPDF (~240KB) out of the main bundle.
            const { jsPDF } = await import('jspdf')
            const doc = new jsPDF({ unit: 'pt', format: 'letter' })
            const margin = 48
            let y = margin

            doc.setFont('helvetica', 'bold')
            doc.setFontSize(18)
            doc.text('Voter Receipt — Zero-Knowledge', margin, y)
            y += 24
            doc.setFont('helvetica', 'normal')
            doc.setFontSize(10)
            doc.setTextColor(120)
            doc.text('Proof of participation. Vote direction NOT included.', margin, y)
            y += 28

            doc.setTextColor(0)
            doc.setFontSize(11)
            const rows: [string, string][] = [
                ['Poll', receipt.pollTitle],
                ['Poll address', receipt.pollAddress],
                ['Nullifier (privacy-safe)', receipt.nullifier],
                ['Tx hash', receipt.txHash],
                ['Block', receipt.blockNumber.toString()],
                ['Chain ID', receipt.chainId.toString()],
                ['Timestamp', new Date(receipt.timestamp).toISOString()],
                ['Protocol', 'Semaphore v4'],
            ]
            for (const [k, v] of rows) {
                doc.setFont('helvetica', 'bold')
                doc.text(`${k}:`, margin, y)
                doc.setFont('helvetica', 'normal')
                const lines = doc.splitTextToSize(v, 380)
                doc.text(lines, margin + 130, y)
                y += 18 * Math.max(1, lines.length)
            }

            // QR — render via react-qr-code's canvas approach is heavy here;
            // simpler: encode the verify URL as text.
            y += 8
            doc.setDrawColor(180)
            doc.line(margin, y, 612 - margin, y)
            y += 18
            doc.setFont('helvetica', 'bold')
            doc.text('Verification URL (open or scan QR in JSON download):', margin, y)
            y += 16
            doc.setFont('courier', 'normal')
            doc.setFontSize(9)
            const urlLines = doc.splitTextToSize(verifyUrl, 500)
            doc.text(urlLines, margin, y)
            y += 14 * urlLines.length

            doc.save(`vote-receipt-${receipt.pollAddress.slice(0, 10)}-${receipt.blockNumber}.pdf`)
        } catch (e) {
            setPdfError((e as Error).message ?? 'PDF export failed')
        } finally {
            setPdfBusy(false)
        }
    }

    async function copyTo(kind: 'nullifier' | 'verify', value: string) {
        try {
            await navigator.clipboard.writeText(value)
            setCopied(kind)
            setTimeout(() => setCopied(null), 1500)
        } catch {
            /* clipboard API not available — silent fallback */
        }
    }

    return (
        <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="receipt-modal-title"
            className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm p-4 animate-fade-in-up"
            onClick={onClose}
        >
            <div
                className="relative bg-db-void border border-db-rule max-w-3xl w-full max-h-[92vh] overflow-y-auto"
                onClick={e => e.stopPropagation()}
            >
                {/* Top accent strip — green for success */}
                <div className="absolute left-0 right-0 top-0 h-1 bg-db-success" />

                {/* Close */}
                <button
                    onClick={onClose}
                    aria-label="Close receipt"
                    className="absolute top-3 right-3 p-2 text-db-mute hover:text-db-chalk hover:bg-db-slate transition-colors cursor-pointer"
                >
                    <X className="w-4 h-4" />
                </button>

                <div className="grid grid-cols-1 lg:grid-cols-12 gap-px bg-db-rule">
                    {/* Left: receipt body */}
                    <div className="lg:col-span-7 bg-db-void p-6 lg:p-8">
                        <div className="flex items-center gap-3 mb-6">
                            <ShieldCheck className="w-6 h-6 text-db-success" />
                            <h2
                                id="receipt-modal-title"
                                className="font-sans font-extrabold text-[24px] tracking-[-0.01em] text-db-chalk uppercase"
                            >
                                Vote Receipt
                            </h2>
                        </div>

                        <p className="font-mono text-[11px] text-db-mute leading-relaxed border-l-2 border-db-success pl-3 mb-6">
                            <strong className="text-db-chalk-dim">Privacy preserved:</strong> this receipt
                            proves you voted in this poll. It does NOT reveal which option you
                            chose — Aragon-style "receipt-freeness for direction" plus
                            verifiable participation.
                        </p>

                        <dl className="space-y-3 font-mono text-[12px]">
                            <div>
                                <dt className="text-db-mute uppercase tracking-[0.18em] text-[10px] mb-1">Poll</dt>
                                <dd className="text-db-chalk">{receipt.pollTitle}</dd>
                            </div>
                            <div>
                                <dt className="text-db-mute uppercase tracking-[0.18em] text-[10px] mb-1">Poll address</dt>
                                <dd className="text-db-chalk-dim break-all">{receipt.pollAddress}</dd>
                            </div>
                            <div>
                                <dt className="text-db-mute uppercase tracking-[0.18em] text-[10px] mb-1">
                                    Nullifier (anonymous, on-chain)
                                </dt>
                                <dd className="text-db-chalk-dim break-all flex items-start gap-2">
                                    <code className="flex-1">{shortHex(receipt.nullifier, 14, 10)}</code>
                                    <button
                                        onClick={() => copyTo('nullifier', receipt.nullifier)}
                                        className="text-db-mute hover:text-db-chalk shrink-0 cursor-pointer"
                                        aria-label="Copy nullifier"
                                    >
                                        {copied === 'nullifier' ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
                                    </button>
                                </dd>
                            </div>
                            <div>
                                <dt className="text-db-mute uppercase tracking-[0.18em] text-[10px] mb-1">Block</dt>
                                <dd className="text-db-chalk-dim">#{receipt.blockNumber.toString()}</dd>
                            </div>
                            <div>
                                <dt className="text-db-mute uppercase tracking-[0.18em] text-[10px] mb-1">Tx hash</dt>
                                <dd className="text-db-chalk-dim break-all">
                                    <code>{shortHex(receipt.txHash, 12, 10)}</code>
                                </dd>
                            </div>
                            {receipt.optionLabel && (
                                <div>
                                    <dt className="text-db-mute uppercase tracking-[0.18em] text-[10px] mb-1">
                                        Your vote (PRIVATE — not in receipt)
                                    </dt>
                                    <dd className="text-db-chalk italic">{receipt.optionLabel}</dd>
                                </div>
                            )}
                        </dl>

                        {/* Action row */}
                        <div className="grid grid-cols-1 sm:grid-cols-3 gap-px bg-db-rule mt-6">
                            <button
                                onClick={downloadJson}
                                className="bg-db-segnale hover:bg-db-segnale/90 text-db-void font-sans font-extrabold text-[12px] tracking-[0.18em] uppercase px-4 py-3 inline-flex items-center justify-center gap-2 cursor-pointer transition-colors"
                            >
                                <Download className="w-3.5 h-3.5" />
                                JSON
                            </button>
                            <button
                                onClick={downloadPdf}
                                disabled={pdfBusy}
                                className="bg-db-slate hover:bg-db-slate-2 text-db-chalk font-sans font-extrabold text-[12px] tracking-[0.18em] uppercase px-4 py-3 inline-flex items-center justify-center gap-2 cursor-pointer transition-colors disabled:opacity-50"
                            >
                                <FileText className="w-3.5 h-3.5" />
                                {pdfBusy ? 'Loading…' : 'PDF'}
                            </button>
                            <button
                                onClick={() => copyTo('verify', verifyUrl)}
                                className="bg-db-slate hover:bg-db-slate-2 text-db-chalk-dim hover:text-db-chalk font-sans font-extrabold text-[12px] tracking-[0.18em] uppercase px-4 py-3 inline-flex items-center justify-center gap-2 cursor-pointer transition-colors"
                            >
                                {copied === 'verify' ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
                                {copied === 'verify' ? 'Copied' : 'Verify URL'}
                            </button>
                        </div>
                        {pdfError && (
                            <p className="font-mono text-[11px] text-db-segnale mt-3">PDF: {pdfError}</p>
                        )}
                    </div>

                    {/* Right: QR code */}
                    <aside className="lg:col-span-5 bg-db-slate p-6 lg:p-8 flex flex-col items-center gap-4">
                        <p className="font-mono text-[10px] text-db-mute uppercase tracking-[0.18em] text-center">
                            SCAN TO VERIFY
                        </p>
                        <div className="bg-db-chalk p-4 inline-block">
                            <QRCode
                                value={verifyUrl}
                                size={200}
                                level="M"
                                bgColor="#f5f7fa"
                                fgColor="#0a0c10"
                            />
                        </div>
                        <p className="font-mono text-[11px] text-db-mute leading-relaxed text-center max-w-[260px]">
                            Anyone can scan or open this URL to confirm your vote was counted —
                            no wallet required, only a public-mapping read.
                        </p>
                        <a
                            href={verifyUrl}
                            target="_blank"
                            rel="noreferrer noopener"
                            className="font-mono text-[10px] text-db-success hover:text-db-chalk uppercase tracking-[0.16em] inline-flex items-center gap-1 underline-offset-4 hover:underline"
                        >
                            Open verifier
                        </a>
                    </aside>
                </div>
            </div>
        </div>
    )
}
