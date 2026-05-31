import { useState } from 'react'
import { ReceiptModal, type VoterReceipt } from '../components/poll/ReceiptModal'
import { Link } from 'react-router-dom'
import { ArrowLeft } from 'lucide-react'

/**
 * `/demo/receipt` — opens the ReceiptModal with hardcoded fixture data.
 *
 * Reason for existing: the modal fires on real vote completion, which
 * requires invite-token + ZK proof + on-chain inclusion (~10-30s) and is
 * therefore not exercised by the standard E2E suite. This route lets us
 * (a) screenshot the modal for docs/demos, (b) verify the layout in every
 * theme, (c) test JSON / PDF / Copy actions without needing a real vote.
 *
 * Production safety: this is a routed dev surface. The fixture data
 * contains a synthetic nullifier that won't verify against any real poll —
 * the verifier returns "Not Found", which is the correct behaviour. No
 * sensitive data is exposed.
 */

const FIXTURE: VoterReceipt = {
    pollAddress: '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
    pollTitle: 'Q3 Treasury Allocation — Demo',
    nullifier:
        '12345678901234567890123456789012345678901234567890123456789012345678901234567890',
    txHash: '0xabcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01',
    blockNumber: 42n,
    timestamp: Date.now(),
    optionLabel: 'Engineering & infra',
    chainId: 31337,
    appOrigin: typeof window !== 'undefined' ? window.location.origin : '',
}

export default function DemoReceipt() {
    const [open, setOpen] = useState(true)

    return (
        <div className="text-db-chalk max-w-3xl mx-auto py-8">
            <Link
                to="/"
                className="text-db-mute hover:text-db-chalk font-mono text-[11px] tracking-[0.16em] uppercase inline-flex items-center gap-1.5 mb-8"
            >
                <ArrowLeft className="w-3.5 h-3.5" />
                Voting Hub
            </Link>
            <h1 className="font-sans font-extrabold text-[clamp(40px,6vw,72px)] tracking-[-0.03em] leading-[0.95] mb-4">
                RECEIPT
                <br />
                DEMO
            </h1>
            <p className="font-mono text-[12px] text-db-mute leading-relaxed max-w-[60ch] mb-6">
                Mounts the cryptographic voter receipt modal with synthetic fixture data.
                The nullifier is fake, so the verifier (open via QR / link) returns
                "Not Found" — that's the correct cryptographic response.
            </p>
            <button
                onClick={() => setOpen(true)}
                className="px-4 py-2 bg-db-segnale hover:bg-db-segnale/90 text-db-void font-sans font-extrabold text-[12px] tracking-[0.16em] uppercase cursor-pointer"
            >
                Open Receipt Modal
            </button>
            {open && <ReceiptModal receipt={FIXTURE} onClose={() => setOpen(false)} />}
        </div>
    )
}
