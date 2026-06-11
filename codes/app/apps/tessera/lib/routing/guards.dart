/// Route guards as PURE functions (R2f deliverable 3).
///
/// [evaluateLocationGuard] adapts core_domain's [GuardResult] vocabulary to
/// URL locations: (uri, capabilities) in, allow/redirect/block out. No
/// BuildContext, no I/O — the full capability matrix is unit-testable. The
/// router wiring ([redirectForLocation] → go_router `redirect`) stays thin.
library;

import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/guards.dart';

/// Fallback reason key when a capability is missing but no specific reason
/// was recorded in [Capabilities.reasons].
const String kCannotProveReason = 'reason.prove.unavailable';

/// Pure routing decision for [uri] given what this device can do.
///
/// Policy (spec §4.3 — honest capability surface):
/// - `/live/:address/vote` (a ballot you must PROVE to cast) is blocked when
///   `!capabilities.canProve`: a device that can't prove never shows a ballot
///   it can't cast. The block carries the capability's reason key.
/// - `/poll/:address` stays ALLOWED without `canProve`: the poll surface is
///   read-only there (browse, results, verify) with an honest banner — R3.
/// - `/organize/create` is a deliberate PASS-THROUGH even with no signer
///   path (no dev signer, relayer down): the create screen renders its
///   disabled state with the why-not copy instead of the router hiding it.
GuardResult evaluateLocationGuard({
  required Uri uri,
  required Capabilities capabilities,
}) {
  final segments = uri.pathSegments;

  final isLiveVote =
      segments.length == 3 && segments[0] == 'live' && segments[2] == 'vote';
  if (isLiveVote && !capabilities.canProve) {
    return GuardResult.block(
      capabilities.reasonFor(Capability.prove) ?? kCannotProveReason,
    );
  }

  return const GuardResult.allow();
}

/// The location of the honest "you can't do this here" screen for a blocked
/// route. Carries the reason key and the attempted location.
String blockedLocation({required String reasonKey, required Uri from}) => Uri(
  path: '/blocked',
  queryParameters: {'reason': reasonKey, 'from': from.toString()},
).toString();

/// Thin adapter from [GuardResult] to a go_router redirect target.
/// Returns `null` (no redirect) for allow; a `/blocked` location for block.
///
/// `/blocked` and `/error` are exits, never re-guarded — a block can never
/// loop.
String? redirectForLocation({
  required Uri uri,
  required Capabilities capabilities,
}) {
  if (uri.path == '/blocked' || uri.path == '/error') return null;
  return switch (evaluateLocationGuard(uri: uri, capabilities: capabilities)) {
    GuardAllow() => null,
    // No journey machines are mounted at app level yet (R3): a state-targeted
    // redirect falls back to the voter home until the R3 shell maps
    // JourneyState ids to locations.
    GuardRedirect() => '/vote',
    GuardBlock(:final reasonKey) => blockedLocation(
      reasonKey: reasonKey,
      from: uri,
    ),
  };
}
