/// Reference journey implementation — TEST-ONLY.
///
/// Proves the journey contract is implementable and shows the conventions
/// the four real journeys (voter, blind, live, organizer) must follow:
/// a sealed state root, an explicit transition table, an `*InProgress`
/// effect state with cancellation, and a typed error state with a recovery
/// event. Real journeys live in `lib/journeys/<journey>_journey.dart`.
library;

import 'dart:async' show unawaited;

import 'package:core_domain/journeys/journey.dart';

// --- States ----------------------------------------------------------------

/// Sealed root: switches over [DemoState] are exhaustive.
sealed class DemoState extends JourneyState {
  const DemoState();
}

final class DemoIdle extends DemoState {
  const DemoIdle();

  @override
  String get id => 'demo.idle';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.start', type: NextActionType.submit);
}

final class DemoWorkingInProgress extends DemoState with EffectInProgress {
  @override
  final CancellationToken cancellation;

  DemoWorkingInProgress(this.cancellation);

  @override
  String get id => 'demo.workingInProgress';

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.working', type: NextActionType.wait);
}

final class DemoFailed extends DemoState with JourneyErrorState {
  @override
  final Object? cause;

  const DemoFailed(this.cause);

  @override
  String get id => 'demo.failed';

  @override
  String get messageKey => 'error.demoFailed';

  @override
  JourneyEvent get recoveryEvent => const Retry();
}

final class DemoDone extends DemoState {
  const DemoDone();

  @override
  String get id => 'demo.done';

  @override
  bool get isTerminal => true;

  @override
  NextAction? get nextAction => null;
}

// --- Events ----------------------------------------------------------------

final class DemoStart extends JourneyEvent {
  /// Exercises guard evaluation: the Idle→Working row rejects `allowed:
  /// false` starts.
  final bool allowed;

  const DemoStart({this.allowed = true});
}

final class DemoSucceeded extends JourneyEvent {
  const DemoSucceeded();
}

final class DemoEffectFailed extends JourneyEvent {
  final Object cause;

  const DemoEffectFailed(this.cause);
}

// --- Machine ---------------------------------------------------------------

typedef DemoEffect = Future<void> Function(CancellationToken token);

/// Idle → WorkingInProgress → Done, with Failed ↔ Retry recovery.
final class DemoMachine extends JourneyMachine<DemoState> {
  /// The async effect run while in [DemoWorkingInProgress] (injected so
  /// tests control success/failure/hang).
  final DemoEffect effect;

  DemoMachine({required this.effect}) : super(const DemoIdle());

  @override
  late final List<JourneyTransition<DemoState>> transitions = [
    JourneyTransition(
      from: DemoIdle,
      on: DemoStart,
      guard: (state, event) => (event as DemoStart).allowed,
      to: (state, event) => DemoWorkingInProgress(CancellationToken()),
    ),
    JourneyTransition(
      from: DemoWorkingInProgress,
      on: DemoSucceeded,
      to: (state, event) => const DemoDone(),
    ),
    JourneyTransition(
      from: DemoWorkingInProgress,
      on: DemoEffectFailed,
      to: (state, event) => DemoFailed((event as DemoEffectFailed).cause),
    ),
    JourneyTransition(
      from: DemoFailed,
      on: Retry,
      to: (state, event) => DemoWorkingInProgress(CancellationToken()),
    ),
  ];

  @override
  void onEnter(DemoState previous, DemoState next) {
    if (next is DemoWorkingInProgress) {
      // Fire-and-forget by convention: the effect reports back via events
      // and checks its token, so an abandoned run can never touch state.
      unawaited(_runEffect(next));
    }
  }

  Future<void> _runEffect(DemoWorkingInProgress working) async {
    try {
      await effect(working.cancellation);
      if (working.cancellation.isCancelled) return;
      await advance(const DemoSucceeded());
    } on Object catch (error) {
      if (working.cancellation.isCancelled) return;
      await advance(DemoEffectFailed(error));
    }
  }
}
