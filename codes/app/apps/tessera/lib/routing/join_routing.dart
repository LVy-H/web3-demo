/// JoinTarget → route mapping (R2f deliverable 5).
///
/// THE single function that turns feature_join's typed [JoinTarget] into a
/// router location. Pure, total, unit-tested for every target type — the
/// JOIN surface (R3) navigates with `context.go(locationForJoinTarget(t))`
/// and never string-builds a route itself.
library;

import 'package:feature_join/feature_join.dart';

/// Message key shown by the error route for unrecognized JOIN input.
const String kJoinUnrecognizedKey = 'error.join.unrecognized';

String locationForJoinTarget(JoinTarget target) => switch (target) {
  // Single poll route — the on-chain resolver re-derives the module, so the
  // legacy `?module=` hint is deliberately dropped (spec §4.2: no guessing).
  PollTarget(:final address) => '/poll/$address',
  LiveVoteTarget(:final address, :final ticket) => Uri(
    path: '/live/$address/vote',
    queryParameters: ticket == null ? null : {'t': ticket},
  ).toString(),
  LiveHostTarget(:final address) => '/live/$address/host',
  VerifyTarget(:final poll, :final nullifier) =>
    (poll == null && nullifier == null)
        ? '/you/verify'
        : Uri(
            path: '/you/verify',
            queryParameters: {'poll': ?poll, 'nullifier': ?nullifier},
          ).toString(),
  // Code → poll-address resolution is server-side (spec §8 open question 2);
  // /join/resolve is the R3 placeholder that will perform it.
  CodeTarget() => Uri(
    path: '/join/resolve',
    queryParameters: {'code': target.canonical},
  ).toString(),
  UnknownTarget(:final reason) => Uri(
    path: '/error',
    queryParameters: {'messageKey': kJoinUnrecognizedKey, 'detail': reason},
  ).toString(),
};
