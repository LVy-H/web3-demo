/// Route guards (Revolution spec §3 principle 3: invalid states are
/// unreachable via router guards, not error-handled after the fact).
///
/// A guard is a pure function of (journey state, capabilities) — no I/O, no
/// probing. The router layer (R2f) adapts [RouteGuard] results to go_router
/// `redirect` decisions; core_domain stays pure Dart.
library;

import 'capabilities.dart';
import 'journey.dart';

/// Decision returned by a [RouteGuard].
sealed class GuardResult {
  const GuardResult();

  const factory GuardResult.allow() = GuardAllow;

  const factory GuardResult.redirect(String targetStateId) = GuardRedirect;

  const factory GuardResult.block(String reasonKey) = GuardBlock;
}

/// Entry is permitted.
final class GuardAllow extends GuardResult {
  const GuardAllow();

  @override
  String toString() => 'GuardResult.allow';
}

/// Entry is not permitted here; send the user to the route for
/// [targetStateId] (a [JourneyState.id], e.g. `voter.receipt`).
final class GuardRedirect extends GuardResult {
  final String targetStateId;

  const GuardRedirect(this.targetStateId);

  @override
  bool operator ==(Object other) =>
      other is GuardRedirect && other.targetStateId == targetStateId;

  @override
  int get hashCode => targetStateId.hashCode;

  @override
  String toString() => 'GuardResult.redirect($targetStateId)';
}

/// Entry is impossible on this device/configuration; show the honest
/// explanation for [reasonKey] (a localization key) instead of the screen.
final class GuardBlock extends GuardResult {
  final String reasonKey;

  const GuardBlock(this.reasonKey);

  @override
  bool operator ==(Object other) =>
      other is GuardBlock && other.reasonKey == reasonKey;

  @override
  int get hashCode => reasonKey.hashCode;

  @override
  String toString() => 'GuardResult.block($reasonKey)';
}

/// A pure routing decision: may the user be at the screen for [state],
/// given what this device can do?
///
/// Implementations must be side-effect free and synchronous — the router
/// calls them on every refresh.
abstract interface class RouteGuard {
  GuardResult evaluate(JourneyState state, Capabilities capabilities);

  /// Wraps a plain function as a [RouteGuard].
  const factory RouteGuard.from(
    GuardResult Function(JourneyState state, Capabilities capabilities)
    evaluate,
  ) = _FunctionRouteGuard;
}

final class _FunctionRouteGuard implements RouteGuard {
  final GuardResult Function(JourneyState state, Capabilities capabilities)
  _evaluate;

  const _FunctionRouteGuard(this._evaluate);

  @override
  GuardResult evaluate(JourneyState state, Capabilities capabilities) =>
      _evaluate(state, capabilities);
}
