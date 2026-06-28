# UX Design Principles

Tessera is for community organizers and voters who should not need crypto
knowledge to run or verify a trustworthy decision.

## Product Rules

- The first-run local demo must work without wallet setup.
- Primary copy should say "decision", "ballot", "receipt", "verify", and
  "server"; avoid protocol jargon in user-facing screens.
- Verification should feel like a normal product action, not a developer-only
  escape hatch.
- Explain trust honestly: Tessera is verifiable, not trustless.
- Prefer concrete status over abstract phases: draft, open, closed, published.

## Organizer Flow

- Create should ask for title, options, method, visibility, and result policy in
  product language.
- If the admin token is missing, the UI should say to paste the server admin
  token in Settings -> Network.
- Closing and publishing should make it clear when voting is stopped and when a
  verifier can check the final bundle.

## Voter Flow

- A voter should be able to open a shared decision, understand whether voting is
  open, cast a ballot, and keep a receipt.
- Ballot widgets should mirror the method: radios for single choice, checkboxes
  for approval/survey, ordered controls for ranked, steppers/sliders for
  quadratic.
- Receipts should show participation proof data without implying receipt-free or
  coercion-resistant voting.

## Language

| Avoid | Prefer |
| --- | --- |
| Contract address | Decision id |
| Chain state | Server status |
| Nullifier | Receipt/check code, unless in advanced details |
| Prover | Verification engine, unless in developer docs |
| Trustless | Verifiable |

Technical details can appear in advanced panels, diagnostics, API docs, and
verifier output.
