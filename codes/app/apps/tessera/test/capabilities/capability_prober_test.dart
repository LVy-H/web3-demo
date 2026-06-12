// Capabilities probing: pure composition matrix + injectable relayer probe
// (R2f deliverable 4 — no live HTTP anywhere in here).
import 'package:core_domain/journeys/capabilities.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tessera/capabilities/capability_prober.dart';

void main() {
  group('composeCapabilities', () {
    Capabilities compose({
      bool proverAvailable = false,
      bool hasDevSigner = false,
      bool walletConfigured = false,
      bool isWeb = false,
      TargetPlatform platform = TargetPlatform.linux,
      bool? relayerReachable,
    }) => composeCapabilities(
      proverAvailable: proverAvailable,
      hasDevSigner: hasDevSigner,
      walletConfigured: walletConfigured,
      isWeb: isWeb,
      platform: platform,
      relayerReachable: relayerReachable,
    );

    test('a bare desktop can do nothing — and says why for everything', () {
      final caps = compose(relayerReachable: false);
      for (final capability in Capability.values) {
        expect(caps.has(capability), isFalse, reason: '$capability');
        expect(
          caps.reasonFor(capability),
          isNotNull,
          reason: '$capability must carry a why-not key',
        );
      }
    });

    test('prover availability drives canProve and clears its reason', () {
      final caps = compose(proverAvailable: true);
      expect(caps.canProve, isTrue);
      expect(caps.reasonFor(Capability.prove), isNull);
    });

    test('dev signer drives canSign', () {
      expect(compose(hasDevSigner: true).canSign, isTrue);
      expect(
        compose().reasonFor(Capability.sign),
        CapabilityReasons.signNoSigner,
      );
    });

    test('QR scanning: web and mobile yes, bare desktop no', () {
      expect(compose(isWeb: true).canScanQr, isTrue);
      expect(compose(platform: TargetPlatform.android).canScanQr, isTrue);
      expect(compose(platform: TargetPlatform.iOS).canScanQr, isTrue);
      expect(compose(platform: TargetPlatform.linux).canScanQr, isFalse);
    });

    test('NFC: android-native only', () {
      expect(compose(platform: TargetPlatform.android).hasNfc, isTrue);
      expect(
        compose(platform: TargetPlatform.android, isWeb: true).hasNfc,
        isFalse,
      );
      expect(compose(platform: TargetPlatform.iOS).hasNfc, isFalse);
    });

    test('relayer pending vs unreachable carry distinct reasons', () {
      expect(
        compose(relayerReachable: null).reasonFor(Capability.relayer),
        CapabilityReasons.relayerProbing,
      );
      expect(
        compose(relayerReachable: false).reasonFor(Capability.relayer),
        CapabilityReasons.relayerUnreachable,
      );
      final reachable = compose(relayerReachable: true);
      expect(reachable.relayerAvailable, isTrue);
      expect(reachable.reasonFor(Capability.relayer), isNull);
    });

    test('wallet configuration drives canUseWallet', () {
      expect(compose(walletConfigured: true).canUseWallet, isTrue);
      expect(
        compose().reasonFor(Capability.wallet),
        CapabilityReasons.walletNotConfigured,
      );
    });
  });

  group('CapabilityProber', () {
    CapabilityProber prober({
      required Future<bool> Function(String) check,
      bool proverAvailable = true,
    }) => CapabilityProber(
      checkRelayer: check,
      proverAvailable: () => proverAvailable,
      relayerUrl: () => 'http://relayer.test',
      hasDevSigner: () => false,
      walletConfigured: () => false,
      isWeb: false,
      platform: () => TargetPlatform.android,
    );

    test('probePlatform is sync-correct except the pending relayer', () {
      final caps = prober(check: (_) async => true).probePlatform();
      expect(caps.canProve, isTrue);
      expect(caps.relayerAvailable, isFalse);
      expect(
        caps.reasonFor(Capability.relayer),
        CapabilityReasons.relayerProbing,
      );
    });

    test('probe() folds the injected health check in (reachable)', () async {
      final urls = <String>[];
      final caps = await prober(
        check: (url) async {
          urls.add(url);
          return true;
        },
      ).probe();
      expect(urls, ['http://relayer.test']);
      expect(caps.relayerAvailable, isTrue);
    });

    test('probe() never throws on a failing check result', () async {
      final caps = await prober(check: (_) async => false).probe();
      expect(caps.relayerAvailable, isFalse);
      expect(
        caps.reasonFor(Capability.relayer),
        CapabilityReasons.relayerUnreachable,
      );
    });
  });

  group('httpRelayerHealthCheck input guard', () {
    test(
      'malformed URL is false, not a throw (no network attempted)',
      () async {
        expect(await httpRelayerHealthCheck('not a url'), isFalse);
      },
    );
  });
}
