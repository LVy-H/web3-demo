/// Result of writing a poll link to an NFC tag.
class NfcWriteResult {
  final bool ok;
  final String? error;
  const NfcWriteResult({required this.ok, this.error});

  static const unsupported = NfcWriteResult(
    ok: false,
    error: 'NFC is not available on this device',
  );
}

/// Tap-to-open a poll over NFC. A poll's `tessera://poll/<addr>?module=<m>` link
/// — the SAME payload the QR encodes (`shareLinkForPoll`) — is written to an NFC
/// tag, so reading the tag routes through the existing `routeForScannedValue`.
/// NFC is just a faster transport for a venue/booth: tap a sticker instead of
/// aiming a camera.
///
/// Capability-gated like `ProximityService`: [isAvailable] is false wherever the
/// radio is absent (web, desktop, iOS without entitlement, any phone without NFC)
/// and the share sheet shows only the QR — exactly the existing baseline. The
/// Android radio write is **device-fenced** (needs a real NFC phone + a writable
/// tag); the seam, the web-safe factory, the capability-gated UI, and the link
/// payload are the verified, shipping parts.
abstract class NfcService {
  /// Whether an NFC radio is present and enabled right now. Async because the
  /// platform check (e.g. `NfcManager.isAvailable`) is async. Never throws.
  Future<bool> isAvailable();

  /// Write [url] (a `tessera://` poll link) to the next tag held to the phone.
  /// Returns [NfcWriteResult.unsupported] when there's no radio — never throws.
  Future<NfcWriteResult> writeUrl(String url);

  /// Cancel any in-flight write session (e.g. the user dismissed the prompt).
  Future<void> cancel();
}

/// Default everywhere until the Android radio impl is verified on a device: not
/// available, no-op. Keeps the QR as the sole baseline and never blocks sharing.
class UnsupportedNfcService implements NfcService {
  const UnsupportedNfcService();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<NfcWriteResult> writeUrl(String url) async =>
      NfcWriteResult.unsupported;

  @override
  Future<void> cancel() async {}
}
