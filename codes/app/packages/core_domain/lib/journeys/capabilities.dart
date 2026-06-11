/// Honest capability surface (Revolution spec §4.3).
///
/// One immutable [Capabilities] value drives the whole UI: what this
/// device/configuration can actually do, with a human-readable reason key
/// for everything it cannot. Probing (platform checks, hardware queries,
/// relayer health) happens in upper layers; core_domain only defines the
/// shape and receives the result by injection.
library;

/// The individual capabilities a journey or guard may require.
enum Capability { prove, sign, scanQr, nfc, ble, wallet, relayer }

/// Immutable snapshot of what the current device + configuration can do.
///
/// Pure data: no probing, no platform imports. Construct it once in the app
/// layer and inject it into journey machines and route guards.
final class Capabilities {
  /// Can generate zero-knowledge proofs on this device (prover available).
  final bool canProve;

  /// Can sign transactions directly (a usable signer is configured).
  final bool canSign;

  /// Has a camera usable for QR scanning.
  final bool canScanQr;

  final bool hasNfc;
  final bool hasBle;

  /// A wallet flow is actually usable on this platform/build.
  final bool canUseWallet;

  /// The relayer is configured and reachable (sponsored path available).
  final bool relayerAvailable;

  /// For each capability that is unavailable, a localization key explaining
  /// why — the UI never shows a bare disabled surface (spec §3 principle 4).
  final Map<Capability, String> reasons;

  const Capabilities({
    required this.canProve,
    required this.canSign,
    required this.canScanQr,
    required this.hasNfc,
    required this.hasBle,
    required this.canUseWallet,
    required this.relayerAvailable,
    this.reasons = const {},
  });

  /// A device that can do nothing but browse — the conservative default
  /// before probing completes.
  static const Capabilities none = Capabilities(
    canProve: false,
    canSign: false,
    canScanQr: false,
    hasNfc: false,
    hasBle: false,
    canUseWallet: false,
    relayerAvailable: false,
  );

  bool has(Capability capability) => switch (capability) {
    Capability.prove => canProve,
    Capability.sign => canSign,
    Capability.scanQr => canScanQr,
    Capability.nfc => hasNfc,
    Capability.ble => hasBle,
    Capability.wallet => canUseWallet,
    Capability.relayer => relayerAvailable,
  };

  /// The why-not key for [capability], or `null` when it is available or no
  /// reason was recorded.
  String? reasonFor(Capability capability) => reasons[capability];

  Capabilities copyWith({
    bool? canProve,
    bool? canSign,
    bool? canScanQr,
    bool? hasNfc,
    bool? hasBle,
    bool? canUseWallet,
    bool? relayerAvailable,
    Map<Capability, String>? reasons,
  }) {
    return Capabilities(
      canProve: canProve ?? this.canProve,
      canSign: canSign ?? this.canSign,
      canScanQr: canScanQr ?? this.canScanQr,
      hasNfc: hasNfc ?? this.hasNfc,
      hasBle: hasBle ?? this.hasBle,
      canUseWallet: canUseWallet ?? this.canUseWallet,
      relayerAvailable: relayerAvailable ?? this.relayerAvailable,
      reasons: reasons ?? this.reasons,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Capabilities &&
      other.canProve == canProve &&
      other.canSign == canSign &&
      other.canScanQr == canScanQr &&
      other.hasNfc == hasNfc &&
      other.hasBle == hasBle &&
      other.canUseWallet == canUseWallet &&
      other.relayerAvailable == relayerAvailable &&
      _mapEquals(other.reasons, reasons);

  @override
  int get hashCode => Object.hash(
    canProve,
    canSign,
    canScanQr,
    hasNfc,
    hasBle,
    canUseWallet,
    relayerAvailable,
    Object.hashAllUnordered(
      reasons.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() {
    final available = Capability.values.where(has).map((c) => c.name);
    return 'Capabilities(${available.isEmpty ? 'none' : available.join(', ')})';
  }

  static bool _mapEquals(Map<Capability, String> a, Map<Capability, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
