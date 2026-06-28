# Test Coverage

> Updated for the self-hosted Tessera architecture. The retired contract/relayer
> test matrix lives in git history and the changelog; it is not the active
> release gate.

## Active Gates

| Area | Command | Coverage |
| --- | --- | --- |
| Server | `cd codes/server && npm test` | DB schema/repos, append-only behavior, auth, lifecycle, routes, effective close, tally/verdict, Merkle/checkpoints, blind credentials, verifier, e2e decision flows. |
| Control plane | `cd codes/control && npm test` | Slugs, config, registry repos, admin auth/routes, host router/proxy, orchestrator runtime/provisioner, two-org isolation. |
| Flutter workspace | `cd codes/app && dart run melos run analyze && dart run melos run test` | Domain journey rules, voting algorithms, storage, relay/server clients, feature widgets, routing, app shell, visual/a11y-focused widget checks. |

## Current Server Coverage

- Decision create/open/close/publish/cancel lifecycle.
- Convener token auth and forbidden/not-found cases.
- Ballot append with idempotency and conflict handling.
- Signed receipts and running Merkle root updates.
- Public read APIs: decisions, ballots, root, results, anchor, verify.
- Tally methods: single, approval, ranked IRV, quadratic, survey, abstain.
- Verdict rules and quorum/tie behavior.
- Blind-signature registration and secret-ballot serial reuse rejection.
- Independent verifier checks over the public bundle.

## Current Client Coverage

- App composition root and provider wiring.
- Router/deep-link guards.
- Create/organize flows and server-backed organizer adapter.
- Vote flows and server-backed voter adapter.
- Receipt, verify, settings, and diagnostics surfaces.
- Core voting algorithms shared with the server where applicable.

## Known Gaps

- Web payload size/cold-load CI budget is still open.
- Full manual product demo should still be run before a release:
  `./demo.sh up`, create a decision, cast ballots, close/publish, and verify.
- Security review and durability/crash-hardening belong to Phase 6.
