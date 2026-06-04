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
/// Anti-remote-voting — a remote attacker holding a valid ticket still can't be
/// near the organizer.
///
/// Capability-gated: [supported] is false on every platform that lacks the radio
/// (web, desktop, iOS WebKit), and the live-vote flow falls back to the
/// face-to-face code there — exactly the design's baseline. The Android BLE scan
/// lives in `proximity_service_native.dart` behind this seam; the radio + the
/// organizer's beacon advertising are **device-fenced** (no emulator/CI has BLE).
/// See docs/design/live-meeting-vote.md Phase E.
abstract class ProximityService {
  /// Whether a proximity radio could be usable on this platform. `attest` does
  /// the real adapter check and returns [ProximityResult.none] if it's off.
  bool get supported;

  /// Attempt to attest proximity to [orgBeacon] (a 128-bit UUID, e.g. from
  /// [bleBeaconUuid]). Returns [ProximityResult.none] when unsupported or not
  /// found — never throws.
  Future<ProximityResult> attest(String orgBeacon);
}

/// Default everywhere until the Android radio impl runs on a device: not
/// supported, no-op. Keeps the face-to-face code as the sole baseline and never
/// blocks voting.
class UnsupportedProximityService implements ProximityService {
  const UnsupportedProximityService();

  @override
  bool get supported => false;

  @override
  Future<ProximityResult> attest(String orgBeacon) async =>
      ProximityResult.none;
}

/// Derive the shared BLE beacon UUID for a poll from its address — both the
/// organizer (advertiser) and the voter (scanner) compute the same id from the
/// public poll address, so no extra handshake is needed. Pure → unit-tested.
/// Takes the first 128 bits of the 160-bit address and formats them 8-4-4-4-12.
String bleBeaconUuid(String pollAddress) {
  var hex = pollAddress.toLowerCase();
  if (hex.startsWith('0x')) hex = hex.substring(2);
  hex = hex.padRight(32, '0').substring(0, 32);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}
