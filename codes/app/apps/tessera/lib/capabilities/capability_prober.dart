/// Capabilities probing (Revolution spec §4.3, R2f deliverable 4).
///
/// [composeCapabilities] is the PURE composition — platform facts + config
/// facts + a relayer-reachability answer in, one honest [Capabilities] out,
/// with a reason key for everything that is unavailable. [CapabilityProber]
/// gathers the inputs (kIsWeb / defaultTargetPlatform, [AppConfig], the
/// core_crypto proof-service factory) and runs the injectable
/// [RelayerHealthCheck] — widget tests inject a fake check; nothing here
/// fires a live HTTP call unless the production default is used.
library;

import 'package:core_chain/config.dart';
import 'package:core_crypto/proof/proof_service_factory.dart' as core_crypto;
import 'package:core_domain/journeys/capabilities.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Answers "is the relayer at [relayerUrl] reachable right now?".
/// Injectable so tests never hit the network.
typedef RelayerHealthCheck = Future<bool> Function(String relayerUrl);

/// Reason keys for unavailable capabilities (localization keys; the
/// jargon-free copy pass maps them to user-facing strings).
abstract final class CapabilityReasons {
  static const proveUnsupported = 'reason.prove.platformUnsupported';
  static const signNoSigner = 'reason.sign.noSigner';
  static const scanQrNoCamera = 'reason.scanQr.noCamera';
  static const nfcUnsupported = 'reason.nfc.unsupported';
  static const bleUnsupported = 'reason.ble.unsupported';
  static const walletNotConfigured = 'reason.wallet.notConfigured';
  static const relayerProbing = 'reason.relayer.probing';
  static const relayerUnreachable = 'reason.relayer.unreachable';
}

/// Production [RelayerHealthCheck]: GET `<relayerUrl>/api/relay/info` (the
/// relayer's cheap no-chain discovery endpoint) with a hard timeout. Any
/// non-200 / network error / timeout means "not reachable" — never throws.
Future<bool> httpRelayerHealthCheck(
  String relayerUrl, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final base = Uri.tryParse(relayerUrl);
  if (base == null || base.host.isEmpty) return false;
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final resp = await c
        .get(base.replace(path: '${base.path}/api/relay/info'))
        .timeout(timeout);
    return resp.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    if (owned) c.close();
  }
}

/// Pure composition of the capability surface. No I/O, no platform imports
/// beyond the [TargetPlatform] enum — unit-testable for the full matrix.
///
/// [relayerReachable] is `null` while the (async) reachability probe is still
/// pending: the relayer is then reported unavailable with the honest
/// "probing" reason, and a later [CapabilityProber.probe] refines it.
Capabilities composeCapabilities({
  required bool proverAvailable,
  required bool hasDevSigner,
  required bool walletConfigured,
  required bool isWeb,
  required TargetPlatform platform,
  required bool? relayerReachable,
}) {
  final canProve = proverAvailable;
  final canSign = hasDevSigner;
  final isMobile =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  // Camera QR scanning ships on web (feat/web-camera-scan) and mobile.
  final canScanQr = isWeb || isMobile;
  final hasNfc = !isWeb && platform == TargetPlatform.android;
  // No BLE proximity probe exists yet — honestly unavailable everywhere.
  const hasBle = false;
  final canUseWallet = walletConfigured;
  final relayerAvailable = relayerReachable ?? false;

  return Capabilities(
    canProve: canProve,
    canSign: canSign,
    canScanQr: canScanQr,
    hasNfc: hasNfc,
    hasBle: hasBle,
    canUseWallet: canUseWallet,
    relayerAvailable: relayerAvailable,
    reasons: {
      if (!canProve) Capability.prove: CapabilityReasons.proveUnsupported,
      if (!canSign) Capability.sign: CapabilityReasons.signNoSigner,
      if (!canScanQr) Capability.scanQr: CapabilityReasons.scanQrNoCamera,
      if (!hasNfc) Capability.nfc: CapabilityReasons.nfcUnsupported,
      Capability.ble: CapabilityReasons.bleUnsupported,
      if (!canUseWallet)
        Capability.wallet: CapabilityReasons.walletNotConfigured,
      if (!relayerAvailable)
        Capability.relayer: relayerReachable == null
            ? CapabilityReasons.relayerProbing
            : CapabilityReasons.relayerUnreachable,
    },
  );
}

/// Gathers probe inputs and produces [Capabilities] snapshots.
///
/// Every input is injectable (tests override what they need); production
/// defaults read kIsWeb / [defaultTargetPlatform], [AppConfig], and the
/// core_crypto proof-service factory's availability logic. Config getters are
/// functions (not captured values) so a re-probe after a settings change sees
/// the new effective config.
class CapabilityProber {
  final RelayerHealthCheck checkRelayer;
  final bool Function() proverAvailable;
  final String Function() relayerUrl;
  final bool Function() hasDevSigner;
  final bool Function() walletConfigured;
  final bool isWeb;
  final TargetPlatform Function() platform;

  CapabilityProber({
    RelayerHealthCheck? checkRelayer,
    bool Function()? proverAvailable,
    String Function()? relayerUrl,
    bool Function()? hasDevSigner,
    bool Function()? walletConfigured,
    bool? isWeb,
    TargetPlatform Function()? platform,
  }) : checkRelayer = checkRelayer ?? httpRelayerHealthCheck,
       proverAvailable =
           proverAvailable ?? (() => core_crypto.proofServiceAvailable),
       relayerUrl = relayerUrl ?? (() => AppConfig.relayerUrl),
       hasDevSigner =
           hasDevSigner ?? (() => AppConfig.devPrivateKey.isNotEmpty),
       walletConfigured =
           walletConfigured ??
           (() => AppConfig.walletConnectProjectId.isNotEmpty),
       isWeb = isWeb ?? kIsWeb,
       platform = platform ?? (() => defaultTargetPlatform);

  /// Synchronous platform+config snapshot — correct for everything except
  /// relayer reachability (reported unavailable/probing until [probe]
  /// completes). Cheap enough to run before the first frame, so guards that
  /// depend on `canProve` are right from app start.
  Capabilities probePlatform() => _compose(relayerReachable: null);

  /// Full probe including the (injectable) relayer reachability check.
  /// Never throws; an unreachable/erroring relayer is a `false`, not a crash.
  Future<Capabilities> probe() async =>
      _compose(relayerReachable: await checkRelayer(relayerUrl()));

  Capabilities _compose({required bool? relayerReachable}) =>
      composeCapabilities(
        proverAvailable: proverAvailable(),
        hasDevSigner: hasDevSigner(),
        walletConfigured: walletConfigured(),
        isWeb: isWeb,
        platform: platform(),
        relayerReachable: relayerReachable,
      );
}
