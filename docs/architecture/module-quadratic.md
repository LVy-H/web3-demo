# Quadratic Decisions

Quadratic voting lets a voter allocate vote weight across options under a fixed
credit budget. The cost of assigning `v` votes to an option is `v^2`.

## Server Method

- `method: "quadratic"`
- Ballot payload: `{ "kind": "quadratic", "votes": [<votes-per-option>, ...] }`
- Abstain payload: `{ "kind": "abstain" }`

The `votes` array must have one non-negative integer slot per option. The server
rejects a ballot when:

```text
sum(votes[i] * votes[i]) > 100
```

The tally sums the vote values per option.

## Verification

The verifier checks the same budget rule from the public payloads, recomputes
the option scores, and binds the ballot set to the signed Merkle/anchor bundle.
