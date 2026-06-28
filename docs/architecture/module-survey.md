# Survey Decisions

Survey is the aggregate multi-select method in the current server. It is useful
for collecting selections where more than one answer can be counted.

## Server Method

- `method: "survey"`
- Ballot payload: `{ "kind": "survey", "choices": [<option-index>, ...] }`
- Abstain payload: `{ "kind": "abstain" }`

The server validates all indices. The tally treats survey choices like approval:
each distinct in-range option selected by a ballot receives one point.

## Current Scope

The server's canonical payload is a flat option list. Some app-side UI still has
question-builder concepts from earlier design work; when using the current REST
server path, the adapter maps survey creation to the option set the server can
tally.

## Verification

Survey verification is the same public recomputation path as the other methods:
validate ballot payloads, recompute scores, rebuild the Merkle root, and check
the signed anchor and verdict.
