import { useEffect, useState, useCallback } from 'react'
import QRCode from 'react-qr-code'

interface Props {
  /** Poll address — goes into the /live/:pollId/vote URL. */
  pollId: string
  /** Mints a fresh signed ticket. Wrap in useCallback so the QR re-mints on a
   *  fixed interval, not on every render. */
  makeTicket: () => Promise<string> | string
  /** How often to rotate the ticket (ms). Short by design (attack A3/A4). */
  refreshMs?: number
}

/**
 * RotatingQR (S1.4) — the projector QR. Encodes the wallet-free voter URL and
 * re-mints a fresh ticket every ~25s with a visible countdown, so a QR
 * photographed and reshared is useless within seconds.
 */
export function RotatingQR({ pollId, makeTicket, refreshMs = 25000 }: Props) {
  const [ticket, setTicket] = useState<string | null>(null)
  const [secondsLeft, setSecondsLeft] = useState(Math.floor(refreshMs / 1000))

  const mint = useCallback(async () => {
    try {
      const t = await makeTicket()
      setTicket(t)
      setSecondsLeft(Math.floor(refreshMs / 1000))
    } catch {
      setTicket(null)
    }
  }, [makeTicket, refreshMs])

  useEffect(() => {
    // Async initial mint + interval refresh — setState lands in a microtask,
    // not synchronously, so the cascading-render concern doesn't apply here.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void mint()
    const refresh = setInterval(() => void mint(), refreshMs)
    const countdown = setInterval(() => setSecondsLeft((s) => (s > 0 ? s - 1 : 0)), 1000)
    return () => {
      clearInterval(refresh)
      clearInterval(countdown)
    }
  }, [mint, refreshMs])

  const url = ticket
    ? `${window.location.origin}/live/${pollId}/vote?t=${encodeURIComponent(ticket)}`
    : ''

  return (
    <div className="flex flex-col items-center gap-4" data-testid="rotating-qr">
      <div className="bg-white p-5 rounded-sm">
        {url ? (
          <QRCode value={url} size={260} level="M" data-testid="rotating-qr-code" />
        ) : (
          <div className="w-[260px] h-[260px] grid place-items-center text-db-void font-mono text-xs">
            preparing…
          </div>
        )}
      </div>
      <p className="font-mono text-[11px] text-db-mute tracking-[0.16em] uppercase">
        Scan to vote · refreshes in <span className="text-db-segnale tabular-nums">{secondsLeft}s</span>
      </p>
    </div>
  )
}
