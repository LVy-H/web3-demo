# Approval Decisions

Approval voting lets a voter approve any number of options. Each approved option
receives one point.

## Server Method

- `method: "approval"`
- Ballot payload: `{ "kind": "approval", "choices": [<option-index>, ...] }`
- Abstain payload: `{ "kind": "abstain" }`

The server validates every option index. Duplicate indices in a ballot are
deduplicated by the tally, so one ballot can add at most one approval point to a
given option.

## Modes

Approval works in both open and secret ballot modes. Secret mode uses the same
blind-signature credential flow as the other methods; the credential proves
eligibility and the serial enforces one accepted ballot per credential.

## Verification

The verifier recomputes the approval counts from the public ballot payloads and
checks the result against the signed Merkle/anchor bundle.
