import 'dart:io' show Platform;

/// Result of a physical-proximity attestation (live-meeting Phase E). `verified`
/// means the voter's device confirmed it is near the organizer; `method` records
/// how (ble / nfc / none).
class ProximityResult {
  final bool verified;
  final String method; // 'ble' | 'nfc' | 'none'
  const ProximityResult({required this.verified, required this.method});

  static const none = ProximityResult(verified: false, method: 'none');
}

/// Optional augment to the face-to-face confirmation code: prove the voter is
/// physically in the room via a short-range radio (BLE beacon scan / NFC tap).
///
/// Capability-gated: [supported] is false on every platform that lacks the
/// radio (web, desktop, iOS WebKit), and the live-vote flow falls back to the
/// face-to-face code there — exactly the design's baseline. The Android BLE/NFC
/// implementation is **device-pending** (can't be exercised on a headless CI box;
/// needs `flutter_blue_plus` / `nfc_manager` + an organizer beacon and a phone).
/// See docs/design/live-meeting-vote.md Phase E.
abstract class ProximityService {
  /// Whether a proximity radio is usable on this platform right now.
  bool get supported;

  /// Attempt to attest proximity to [orgBeacon] (a UUID / tag id). Returns
  /// [ProximityResult.none] when unsupported — never throws.
  Future<ProximityResult> attest(String orgBeacon);
}

/// Default everywhere until the Android radio impl lands: not supported, no-op.
/// Keeps the face-to-face code as the sole baseline and never blocks voting.
class UnsupportedProximityService implements ProximityService {
  const UnsupportedProximityService();

  @override
  bool get supported => false;

  @override
  Future<ProximityResult> attest(String orgBeacon) async => ProximityResult.none;
}

/// Selects the right [ProximityService] for the platform. Only Android could
/// ever carry a real radio impl; everything else is the no-op. (Android impl is
/// device-pending, so this returns the no-op until that lands behind its own
/// capability check — keeping unverified radio code off every shipping path.)
ProximityService createProximityService() {
  // ignore: dead_code — Android branch reserved for the device-pending impl.
  if (Platform.isAndroid) {
    return const UnsupportedProximityService();
  }
  return const UnsupportedProximityService();
}
