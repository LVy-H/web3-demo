# journeys/ — the journey contract (R2a)

Shared contract for the four Tessera journeys (Revolution spec §3 principle 3,
§4.2). Every journey is an explicit typed state machine; the UI renders the
*current state's* one next action; illegal transitions throw and can never be
expressed silently.

## Files (shared contract — FROZEN for journey PRs)

| File | Contents |
|---|---|
| `journey.dart` | `JourneyState`, `NextAction`, `JourneyEvent` + common events (`Refresh`, `Retry`, `Timeout`, `ExternalPhaseChanged`), `JourneyMachine`, `JourneyTransition`, `JourneyViolation`, `CancellationToken`, `EffectInProgress`, `JourneyErrorState` |
| `capabilities.dart` | `Capabilities` value object + `Capability` enum (honest capability surface, spec §4.3) |
| `policy.dart` | `ResultsPolicy` (default `sealedUntilClose`), `PollVisibility` (default `unlisted`) — spec §5 |
| `guards.dart` | `RouteGuard` + sealed `GuardResult` (`allow` / `redirect` / `block`) for the R2f router layer |

## File-ownership rule (prevents merge conflicts between parallel PRs)

Each journey agent adds **exactly one** implementation file plus its tests:

```
lib/journeys/voter_journey.dart        + test/journeys/voter_journey_test.dart
lib/journeys/blind_journey.dart        + test/journeys/blind_journey_test.dart
lib/journeys/live_journey.dart         + test/journeys/live_journey_test.dart   (live-voter + host)
lib/journeys/organizer_journey.dart    + test/journeys/organizer_journey_test.dart
```

**Never edit the shared files above** (including this README) in a journey PR.
If the contract is missing something, raise it — don't patch it in your branch;
four parallel branches editing `journey.dart` cannot merge.

## Conventions (the reference implementation in `test/journeys/demo_journey.dart` shows all of them)

1. **Sealed root per journey.** Declare
   `sealed class VoterState extends JourneyState` and `final` leaf states in
   your one file. The shared base is `abstract base` (not `sealed`) because
   Dart seals per-library and each journey owns its own file — your journey's
   root being `sealed` is what makes `switch`es over it exhaustive.
2. **Stable state ids.** `id` is `<journey>.<state>` in lowerCamelCase
   (`voter.ballot`, `organizer.votingOpen`). Ids feed telemetry, persistence
   and `GuardResult.redirect` targets — never rename a shipped id.
3. **One next action.** Every state decides its `NextAction?` (the getter is
   deliberately abstract). Labels and disabled reasons are localization keys
   (`action.*`, `reason.*`) — jargon-free copy lives in the app layer, never
   in core_domain.
4. **Explicit transition table.** Legal behavior is the `transitions` list:
   exact (state type × event type), optional guard. Anything else throws
   `JourneyViolation` (an `Error` — a bug, not a flow). Events must be
   `final` classes: matching is on exact runtime type.
5. **Async effects are states, not flags.** Anything that proves, relays or
   fetches is a `*InProgress` state mixing in `EffectInProgress` with a fresh
   `CancellationToken` per entry. Start the effect in `onEnter`
   (fire-and-forget), have it check `isCancelled` before dispatching its
   completion event. The machine auto-cancels the token whenever the state is
   left or the machine is disposed — an abandoned effect can never write back
   (this codifies the historical "save hang" bug class).
6. **Failures are typed states with an exit.** Effect failure transitions to
   a state mixing in `JourneyErrorState`, which names its `recoveryEvent`
   (usually `Retry`) and `messageKey`. No dead ends.
7. **Phase truth is external.** React to chain phase changes via
   `ExternalPhaseChanged(phase)` (0 = Registration, 1 = Voting, 2 = Ended) —
   guards on those rows are where phase gating lives (the R0 fixes land here).
8. **Capabilities are injected, never probed here.** Take a `Capabilities`
   value in your machine/guards; core_domain has no platform code.
9. **Pure Dart.** No Flutter imports anywhere in this package. The router
   adapts `Stream<S> states` to a `Listenable` in R2f.

## Verifying your journey PR

```
cd codes/app
dart analyze --fatal-infos packages/core_domain
dart test                       # from packages/core_domain
dart run melos run analyze && dart run melos run test
```

Cover at minimum: every legal transition, one illegal transition per state
group (expect `JourneyViolation`), effect failure → error state → recovery,
and `NextAction` surfacing per state (see `journey_contract_test.dart`).
