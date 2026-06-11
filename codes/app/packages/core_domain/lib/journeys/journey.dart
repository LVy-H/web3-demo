/// Tessera journey contract (Revolution spec §3 principle 3, §4.2).
///
/// Every user journey (voter, blind, live-voter/host, organizer) is an
/// explicit typed state machine. The UI renders the *current state's* one
/// next action; illegal transitions throw [JourneyViolation] — they are
/// impossible to express silently.
///
/// Conventions for implementers (see lib/journeys/README.md):
/// - Each journey declares its own `sealed` state root extending
///   [JourneyState] in its own `<journey>_journey.dart` file, so switches
///   over that journey's states are exhaustive. (The shared base cannot be
///   `sealed` itself: sealed restricts subtypes to one library, and each
///   journey lives in its own file by the file-ownership rule.)
/// - States that run async effects (proving, relaying, fetching) mix in
///   [EffectInProgress] and carry a [CancellationToken]. Effect failure
///   transitions to a state mixing in [JourneyErrorState] with a recovery
///   event — never a stuck busy flag.
library;

import 'dart:async';

// ---------------------------------------------------------------------------
// Next action
// ---------------------------------------------------------------------------

/// How the UI should render a state's primary action.
enum NextActionType {
  /// A button that calls [JourneyMachine.advance] with a journey event.
  submit,

  /// A button that re-dispatches a recovery event (typically [Retry]).
  retry,

  /// Navigation to another route/state (router resolves the target).
  navigate,

  /// No user action is possible right now; the UI shows passive progress
  /// or a countdown (e.g. proving, waiting-for-open).
  wait,
}

/// The ONE primary action the UI renders for a [JourneyState].
///
/// `labelKey` and `disabledReasonKey` are localization keys, never raw
/// user-facing strings (jargon-free copy is centralized in the app layer).
final class NextAction {
  /// Localization key for the action label (e.g. `action.castVote`).
  final String labelKey;

  final NextActionType type;

  /// Localization key explaining why the action is disabled, or `null` if
  /// the action is enabled. Honest capability surface: a disabled action
  /// always says why.
  final String? disabledReasonKey;

  const NextAction({
    required this.labelKey,
    required this.type,
    this.disabledReasonKey,
  });

  bool get enabled => disabledReasonKey == null;

  @override
  bool operator ==(Object other) =>
      other is NextAction &&
      other.labelKey == labelKey &&
      other.type == type &&
      other.disabledReasonKey == disabledReasonKey;

  @override
  int get hashCode => Object.hash(labelKey, type, disabledReasonKey);

  @override
  String toString() =>
      'NextAction($labelKey, $type'
      '${disabledReasonKey == null ? '' : ', disabled: $disabledReasonKey'})';
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

/// Base type for all journey states.
///
/// Subclassing convention: each journey defines one `sealed` root
/// (`sealed class VoterState extends JourneyState`) and `final` leaf states
/// in a single file it owns.
abstract base class JourneyState {
  const JourneyState();

  /// Stable identifier for telemetry, persistence and router guards.
  /// Convention: `<journey>.<state>` in lowerCamelCase, e.g. `voter.ballot`.
  /// Never rename a shipped id.
  String get id;

  /// Terminal states accept no further events; [JourneyMachine.advance]
  /// throws [JourneyViolation] from a terminal state.
  bool get isTerminal => false;

  /// The one primary action the UI renders for this state, or `null` when
  /// the journey offers nothing (e.g. terminal receipt states). Deliberately
  /// abstract: every state author must decide what the user can do now.
  NextAction? get nextAction;

  @override
  String toString() => id;
}

/// Cooperative cancellation for async effects.
///
/// The machine cancels the token automatically when an [EffectInProgress]
/// state is left, so an abandoned effect can never write back into the
/// journey (codifies the historical "stuck busy flag / save hang" bug class).
final class CancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// Completes when [cancel] is called; never completes with an error.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Mixin for states that run an async effect (proving, relaying, fetching).
///
/// Convention: name these states `*InProgress`, start the effect in
/// [JourneyMachine.onEnter], and have the effect check
/// [CancellationToken.isCancelled] before dispatching its completion event.
base mixin EffectInProgress on JourneyState {
  CancellationToken get cancellation;
}

/// Mixin for typed error states reached when an effect fails.
///
/// Every error state names its recovery event, so the UI can always render
/// a way out — a failed effect is a state with an exit, never a dead end.
base mixin JourneyErrorState on JourneyState {
  /// Localization key describing what went wrong (jargon-free).
  String get messageKey;

  /// The underlying failure, for logging/telemetry only (never shown raw).
  Object? get cause;

  /// The event that re-attempts or exits this error (typically [Retry]).
  JourneyEvent get recoveryEvent;

  @override
  NextAction? get nextAction =>
      const NextAction(labelKey: 'action.retry', type: NextActionType.retry);
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Base type for journey events. Concrete events must be `final` classes:
/// the transition table matches on exact runtime type.
abstract base class JourneyEvent {
  const JourneyEvent();

  @override
  String toString() => runtimeType.toString();
}

/// User- or system-requested re-read of external truth (pull-to-refresh,
/// foreground resume).
final class Refresh extends JourneyEvent {
  const Refresh();
}

/// Recovery event dispatched from a [JourneyErrorState].
final class Retry extends JourneyEvent {
  const Retry();
}

/// A bounded wait expired (live-voter pending heartbeat, reveal deadline).
final class Timeout extends JourneyEvent {
  const Timeout();
}

/// The on-chain poll phase changed underneath the journey.
/// [phase] uses the chain encoding: 0 = Registration, 1 = Voting, 2 = Ended.
final class ExternalPhaseChanged extends JourneyEvent {
  final int phase;

  const ExternalPhaseChanged(this.phase);

  @override
  String toString() => 'ExternalPhaseChanged($phase)';
}

// ---------------------------------------------------------------------------
// Machine
// ---------------------------------------------------------------------------

/// One row of a journey's transition table: in state of exact type [from],
/// on event of exact type [on], produce the next state via [to] — provided
/// [guard] (if any) passes.
final class JourneyTransition<S extends JourneyState> {
  /// Exact runtime type of the current state this row applies to.
  final Type from;

  /// Exact runtime type of the event this row consumes.
  final Type on;

  /// Builds the next state. Receives the current state and the event;
  /// implementations downcast to the concrete types named by [from]/[on].
  final S Function(S state, JourneyEvent event) to;

  /// Optional predicate; when it returns false this row does not match.
  /// If every type-matching row is guard-rejected, advance() throws
  /// [JourneyViolation] — a rejected guard is never a silent no-op.
  final bool Function(S state, JourneyEvent event)? guard;

  const JourneyTransition({
    required this.from,
    required this.on,
    required this.to,
    this.guard,
  });
}

/// Thrown when a journey receives an event its transition table does not
/// allow from the current state. This is a programming error (the UI must
/// only offer the current state's [NextAction]); it is an [Error] so it can
/// never be swallowed as a routine exception.
final class JourneyViolation extends Error {
  final JourneyState state;
  final JourneyEvent event;

  /// True when one or more rows matched by type but every guard rejected.
  final bool guardRejected;

  JourneyViolation({
    required this.state,
    required this.event,
    this.guardRejected = false,
  });

  @override
  String toString() =>
      'JourneyViolation: event $event is not legal in state ${state.id}'
      '${guardRejected ? ' (guard rejected)' : ''}';
}

/// Base class for journey state machines.
///
/// Subclasses provide the [transitions] table and (optionally) start async
/// effects in [onEnter]. All state changes flow through [advance]; there is
/// no other way to mutate [state].
abstract class JourneyMachine<S extends JourneyState> {
  S _state;
  final StreamController<S> _states = StreamController<S>.broadcast();
  bool _disposed = false;

  JourneyMachine(S initial) : _state = initial;

  /// The current state. Synchronously consistent with the last event
  /// processed by [advance].
  S get state => _state;

  /// Broadcast stream of states, emitting after each successful transition.
  /// (The router layer adapts this to a `Listenable` for `refreshListenable`;
  /// core_domain stays pure Dart.)
  Stream<S> get states => _states.stream;

  /// The explicit transition table (state type × event type → next state).
  /// This is the single source of truth for what is legal; anything not in
  /// the table throws [JourneyViolation].
  List<JourneyTransition<S>> get transitions;

  /// Applies [event] to the current state via the transition table.
  ///
  /// Completes after the new state is set and listeners are notified; it
  /// does NOT await effects started in [onEnter] (effects report back by
  /// dispatching their own completion/failure events).
  ///
  /// Throws [JourneyViolation] if the table has no row for
  /// (current state, event), if all matching rows are guard-rejected, or if
  /// the current state is terminal. Throws [StateError] after [dispose].
  Future<void> advance(JourneyEvent event) async {
    if (_disposed) {
      throw StateError('advance($event) after dispose() on $runtimeType');
    }
    if (_state.isTerminal) {
      throw JourneyViolation(state: _state, event: event);
    }
    var guardRejected = false;
    for (final row in transitions) {
      if (row.from != _state.runtimeType || row.on != event.runtimeType) {
        continue;
      }
      if (!(row.guard?.call(_state, event) ?? true)) {
        guardRejected = true;
        continue;
      }
      final previous = _state;
      final next = row.to(_state, event);
      _state = next;
      // Leaving an in-progress state always cancels its effect: an abandoned
      // effect can never complete into the journey later.
      if (previous is EffectInProgress && !identical(previous, next)) {
        previous.cancellation.cancel();
      }
      _states.add(next);
      onEnter(previous, next);
      return;
    }
    throw JourneyViolation(
      state: _state,
      event: event,
      guardRejected: guardRejected,
    );
  }

  /// Hook called after every successful transition, with listeners already
  /// notified. Override to start async effects when entering an
  /// [EffectInProgress] state. Must not throw; effect failures are reported
  /// by dispatching the journey's failure event.
  void onEnter(S previous, S next) {}

  /// Cancels any in-flight effect and closes [states]. The machine accepts
  /// no further events.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final current = _state;
    if (current is EffectInProgress) {
      current.cancellation.cancel();
    }
    _states.close();
  }
}
