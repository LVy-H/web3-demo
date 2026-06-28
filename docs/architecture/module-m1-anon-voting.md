# Single-Choice Decisions

Single-choice is the simplest Tessera method. A ballot selects exactly one
option, or abstains.

## Server Method

- `method: "single"`
- Ballot payload: `{ "kind": "single", "choice": <option-index> }`
- Abstain payload: `{ "kind": "abstain" }`

The server validates that `choice` is an integer in range for the decision's
option list. The tally adds one point to the selected option and counts abstain
ballots toward turnout without adding option score.

## Modes

Single-choice decisions can be open or secret:

- Open mode gates eligibility through the decision's configured method
  (`open`, `passcode`, or `domain`) and records no voter identifier in the
  public leaf.
- Secret mode uses a per-decision blind-signature credential. The ballot carries
  `(serial, credentialSig)`, the server verifies it against the issuer public
  key, and the serial prevents double voting without linking issuance to cast.

## Verification

The public verifier recomputes every ballot hash, rebuilds the Merkle root,
checks the signed anchor, recomputes the single-choice tally, and checks that the
published verdict matches.
