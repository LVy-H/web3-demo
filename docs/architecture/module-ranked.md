# Ranked Decisions

Ranked voting records an ordered preference list and uses instant-runoff voting
(IRV) to determine the winner.

## Server Method

- `method: "ranked"`
- Ballot payload: `{ "kind": "ranked", "ranking": [<option-index>, ...] }`
- Abstain payload: `{ "kind": "abstain" }`

The server validates indices against the option list. The tally exposes first
preference counts for display and an auditable IRV round trace for verification.

## IRV Rule

1. Each continuing ballot counts for its highest-ranked non-eliminated option.
2. A candidate wins a round only with strict majority:
   `2 * votes > continuingBallots`.
3. If nobody has strict majority, eliminate the continuing option with the
   fewest votes.
4. Ties for elimination are resolved by lowest option index.
5. Repeat until a strict-majority winner appears or only one continuing option
   remains.

## Verification

The verifier replays the same IRV algorithm over the published ballots and
checks the tally, round trace, verdict, Merkle root, and signed anchor.
