// Guard unit tests: allow / redirect / block per capability matrix
// (R2f deliverable 3 — guards are pure functions, tested without a router).
import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/guards.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tessera/capabilities/capability_prober.dart';
import 'package:tessera/routing/guards.dart';

Capabilities caps({
  bool canProve = false,
  bool canSign = false,
  bool relayerAvailable = false,
  Map<Capability, String> reasons = const {},
}) => Capabilities(
  canProve: canProve,
  canSign: canSign,
  canScanQr: false,
  hasNfc: false,
  hasBle: false,
  canUseWallet: false,
  relayerAvailable: relayerAvailable,
  reasons: reasons,
);

void main() {
  group('evaluateLocationGuard', () {
    test('live-vote is blocked without canProve, with the recorded reason', () {
      final result = evaluateLocationGuard(
        uri: Uri.parse('/live/0xAbC/vote?t=ticket'),
        capabilities: caps(
          reasons: {Capability.prove: CapabilityReasons.proveUnsupported},
        ),
      );
      expect(
        result,
        const GuardResult.block(CapabilityReasons.proveUnsupported),
      );
    });

    test(
      'live-vote without a recorded reason falls back to the default key',
      () {
        final result = evaluateLocationGuard(
          uri: Uri.parse('/live/0xAbC/vote'),
          capabilities: caps(),
        );
        expect(result, const GuardResult.block(kCannotProveReason));
      },
    );

    test('live-vote is allowed when the device can prove', () {
      final result = evaluateLocationGuard(
        uri: Uri.parse('/live/0xAbC/vote'),
        capabilities: caps(canProve: true),
      );
      expect(result, const GuardResult.allow());
    });

    test('live HOST route never requires proving', () {
      final result = evaluateLocationGuard(
        uri: Uri.parse('/live/0xAbC/host'),
        capabilities: caps(),
      );
      expect(result, const GuardResult.allow());
    });

    test('poll route stays allowed without canProve (read-only surface)', () {
      final result = evaluateLocationGuard(
        uri: Uri.parse('/poll/0x1111111111111111111111111111111111111111'),
        capabilities: caps(),
      );
      expect(result, const GuardResult.allow());
    });

    test('organize-create is a pass-through even with NO signer path '
        '(disabled state is the screen\'s job, not the router\'s)', () {
      final result = evaluateLocationGuard(
        uri: Uri.parse('/organize/create'),
        capabilities: caps(canSign: false, relayerAvailable: false),
      );
      expect(result, const GuardResult.allow());
    });

    test('the three spaces are always allowed', () {
      for (final path in ['/vote', '/organize', '/you', '/join']) {
        expect(
          evaluateLocationGuard(uri: Uri.parse(path), capabilities: caps()),
          const GuardResult.allow(),
          reason: '$path must be reachable on every device',
        );
      }
    });
  });

  group('redirectForLocation (router adapter)', () {
    test('allow maps to null (no redirect)', () {
      expect(
        redirectForLocation(uri: Uri.parse('/vote'), capabilities: caps()),
        isNull,
      );
    });

    test('block maps to /blocked with reason + attempted location', () {
      final redirect = redirectForLocation(
        uri: Uri.parse('/live/0xAbC/vote?t=tick'),
        capabilities: caps(
          reasons: {Capability.prove: CapabilityReasons.proveUnsupported},
        ),
      );
      final uri = Uri.parse(redirect!);
      expect(uri.path, '/blocked');
      expect(uri.queryParameters['reason'], CapabilityReasons.proveUnsupported);
      expect(uri.queryParameters['from'], '/live/0xAbC/vote?t=tick');
    });

    test('/blocked and /error are never re-guarded (no redirect loop)', () {
      for (final path in ['/blocked', '/error']) {
        expect(
          redirectForLocation(
            uri: Uri.parse('$path?reason=x'),
            capabilities: caps(),
          ),
          isNull,
        );
      }
    });

    test('capability gain lifts the redirect (re-evaluation contract)', () {
      final uri = Uri.parse('/live/0xAbC/vote');
      expect(redirectForLocation(uri: uri, capabilities: caps()), isNotNull);
      expect(
        redirectForLocation(uri: uri, capabilities: caps(canProve: true)),
        isNull,
      );
    });
  });
}
