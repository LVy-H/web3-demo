interface Props {
  code: string
}

/**
 * ConfirmationCode (S1.5) — the big 4-digit code the voter holds up so the
 * organizer can read it off the phone face-to-face and match it in the queue.
 */
export function ConfirmationCode({ code }: Props) {
  const digits = code.padStart(4, '0').slice(0, 4).split('')
  return (
    <div className="flex flex-col items-center gap-3">
      <p className="font-mono text-[11px] text-db-mute tracking-[0.18em] uppercase">
        Show this code to the organizer
      </p>
      <div className="flex items-center gap-3" data-testid="confirmation-code" aria-label={`Confirmation code ${code}`}>
        {digits.map((d, i) => (
          <span
            key={i}
            className="grid place-items-center w-16 h-20 sm:w-20 sm:h-24 bg-db-slate border border-db-rule font-sans font-extrabold text-[44px] sm:text-[56px] tabular-nums text-db-chalk"
          >
            {d}
          </span>
        ))}
      </div>
    </div>
  )
}
