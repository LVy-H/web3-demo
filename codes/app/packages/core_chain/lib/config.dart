/// Runtime configuration.
///
/// Two layers:
///   1. [AppDefaults] — compile-time defaults, baked per build via `--dart-define`
///      (e.g. for Sepolia). Target a local Hardhat node + relayer out of the box.
///   2. [AppConfig] — the *effective* network config the app actually uses. The
///      network fields are mutable statics: at startup `main()` overlays any
///      saved override (Settings → Network) on top of the defaults. This lets a
///      single hosted build (e.g. on Cloudflare Pages) be re-pointed at your own
///      backend WITHOUT a rebuild — the user edits the relayer/chain/registry
///      in-app and reloads.
///
/// Important: the override is applied in EXACTLY one place — `main()`, via
/// [AppConfig.apply]. Nothing else mutates these statics. The save handler only
/// persists the new config and asks the user to reload/restart; the fresh
/// `main()` then re-applies it. That keeps every consumer (the readers/writers
/// built in `main()` AND the poll creators that read the statics directly)
/// consistent — they all reflect the same config for the life of a run.
library;

/// Compile-time defaults. The registry/semaphore defaults match
/// codes/frontend/src/deployed-addresses.json (chainId 31337).
abstract class AppDefaults {
  static const rpcUrl = String.fromEnvironment(
    'RPC_URL',
    defaultValue: 'http://127.0.0.1:8545',
  );
  static const registryAddress = String.fromEnvironment(
    'REGISTRY_ADDRESS',
    defaultValue: '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
  );
  static const relayerUrl = String.fromEnvironment(
    'RELAYER_URL',
    defaultValue: 'http://localhost:3001',
  );

  /// Semaphore verifier address — needed to encode ZkAnonVoting.initialize when
  /// creating a poll. Matches deployed-addresses.json (chainId 31337).
  static const semaphoreAddress = String.fromEnvironment(
    'SEMAPHORE_ADDRESS',
    defaultValue: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
  );

  /// EVM chain id for write transactions (default Hardhat 31337).
  static const chainId = int.fromEnvironment('CHAIN_ID', defaultValue: 31337);
}

abstract class AppConfig {
  // ── Effective network config (mutable; overlaid once at startup) ───────────
  static String rpcUrl = AppDefaults.rpcUrl;
  static String registryAddress = AppDefaults.registryAddress;
  static String relayerUrl = AppDefaults.relayerUrl;
  static String semaphoreAddress = AppDefaults.semaphoreAddress;
  static int chainId = AppDefaults.chainId;

  /// Overlay a saved override onto the defaults. Pass `null` to reset to
  /// defaults. Call ONLY from `main()` — see the file header.
  static void apply(NetworkConfig? c) {
    rpcUrl = c?.rpcUrl ?? AppDefaults.rpcUrl;
    relayerUrl = c?.relayerUrl ?? AppDefaults.relayerUrl;
    registryAddress = c?.registryAddress ?? AppDefaults.registryAddress;
    semaphoreAddress = c?.semaphoreAddress ?? AppDefaults.semaphoreAddress;
    chainId = c?.chainId ?? AppDefaults.chainId;
  }

  /// The compile-time defaults as a [NetworkConfig].
  static NetworkConfig get defaults => const NetworkConfig(
    rpcUrl: AppDefaults.rpcUrl,
    relayerUrl: AppDefaults.relayerUrl,
    registryAddress: AppDefaults.registryAddress,
    semaphoreAddress: AppDefaults.semaphoreAddress,
    chainId: AppDefaults.chainId,
  );

  /// The currently-effective network config.
  static NetworkConfig get effective => NetworkConfig(
    rpcUrl: rpcUrl,
    relayerUrl: relayerUrl,
    registryAddress: registryAddress,
    semaphoreAddress: semaphoreAddress,
    chainId: chainId,
  );

  /// True when the effective config differs from the compile-time defaults
  /// (i.e. a custom backend is configured).
  static bool get isOverridden => effective != defaults;

  // ── Compile-time-only config (never overridden at runtime) ─────────────────

  /// Reown/WalletConnect project ID (free, from cloud.reown.com). Without it the
  /// Connect-Wallet button shows a hint instead of initializing.
  /// Build with: --dart-define=WC_PROJECT_ID=YOUR_ID
  static const walletConnectProjectId = String.fromEnvironment(
    'WC_PROJECT_ID',
    defaultValue: '',
  );

  /// LOCAL-DEV signer key. When set, the app can sign + broadcast transactions
  /// directly (no mobile wallet needed) — the only way to cast M2 commit-reveal
  /// votes against the host-local Hardhat node that a phone wallet can't reach.
  /// NEVER set this for a real deployment. Build with:
  ///   `--dart-define=DEV_PRIVATE_KEY=0x...` (a Hardhat account key)
  static const devPrivateKey = String.fromEnvironment(
    'DEV_PRIVATE_KEY',
    defaultValue: '',
  );

  // ── Desktop ZK prover (SP4) — opt-in Node sidecar ──────────────────────────
  // Lets the desktop app (Linux/Windows/macOS) cast Semaphore votes by spawning
  // Node on the SAME web/zkprover.js bundle the web build uses. OFF unless both
  // paths are set, so it never changes default web/mobile/desktop behavior. Set:
  //   --dart-define=DESKTOP_PROVER_SIDECAR=/abs/web_prover/desktop_prover.mjs
  //   --dart-define=DESKTOP_PROVER_BUNDLE=/abs/web/zkprover.js
  static const desktopProverNode = String.fromEnvironment(
    'DESKTOP_PROVER_NODE',
    defaultValue: 'node',
  );
  static const desktopProverSidecar = String.fromEnvironment(
    'DESKTOP_PROVER_SIDECAR',
    defaultValue: '',
  );
  static const desktopProverBundle = String.fromEnvironment(
    'DESKTOP_PROVER_BUNDLE',
    defaultValue: '',
  );

  /// Desktop proving is enabled only when the sidecar + bundle paths are set.
  static bool get desktopProverEnabled =>
      desktopProverSidecar.isNotEmpty && desktopProverBundle.isNotEmpty;
}

/// An overridable network configuration — the backend pointers a hosted build
/// can be re-targeted at without a rebuild. Persisted by `NetworkConfigStore`.
class NetworkConfig {
  final String rpcUrl;
  final String relayerUrl;
  final String registryAddress;
  final String semaphoreAddress;
  final int chainId;

  const NetworkConfig({
    required this.rpcUrl,
    required this.relayerUrl,
    required this.registryAddress,
    required this.semaphoreAddress,
    required this.chainId,
  });

  NetworkConfig copyWith({
    String? rpcUrl,
    String? relayerUrl,
    String? registryAddress,
    String? semaphoreAddress,
    int? chainId,
  }) => NetworkConfig(
    rpcUrl: rpcUrl ?? this.rpcUrl,
    relayerUrl: relayerUrl ?? this.relayerUrl,
    registryAddress: registryAddress ?? this.registryAddress,
    semaphoreAddress: semaphoreAddress ?? this.semaphoreAddress,
    chainId: chainId ?? this.chainId,
  );

  Map<String, dynamic> toJson() => {
    'rpcUrl': rpcUrl,
    'relayerUrl': relayerUrl,
    'registryAddress': registryAddress,
    'semaphoreAddress': semaphoreAddress,
    'chainId': chainId,
  };

  /// Tolerant decode — any missing/wrong-typed field falls back to the default,
  /// so an older or partial blob never throws here (it's validated separately
  /// via [isValidFormat] before being applied).
  factory NetworkConfig.fromJson(Map<String, dynamic> j) {
    final d = AppConfig.defaults;
    final chain = j['chainId'];
    return NetworkConfig(
      rpcUrl: j['rpcUrl'] is String ? j['rpcUrl'] as String : d.rpcUrl,
      relayerUrl: j['relayerUrl'] is String
          ? j['relayerUrl'] as String
          : d.relayerUrl,
      registryAddress: j['registryAddress'] is String
          ? j['registryAddress'] as String
          : d.registryAddress,
      semaphoreAddress: j['semaphoreAddress'] is String
          ? j['semaphoreAddress'] as String
          : d.semaphoreAddress,
      chainId: chain is int
          ? chain
          : (chain is String ? int.tryParse(chain) ?? d.chainId : d.chainId),
    );
  }

  /// A 0x-prefixed 40-hex-digit EVM address.
  static bool isAddress(String v) =>
      RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(v.trim());

  /// An http(s) URL with a host (the only schemes the reader/relayer client
  /// speak). Rejects empty, scheme-less, or host-less strings.
  static bool isHttpUrl(String v) {
    final u = Uri.tryParse(v.trim());
    return u != null &&
        (u.scheme == 'http' || u.scheme == 'https') &&
        u.host.isNotEmpty;
  }

  /// True only when every field is well-formed enough to be safe to apply —
  /// the load-time brick guard (`ChainReader` parses the registry address
  /// eagerly, so a malformed blob would otherwise throw in `main()`).
  bool get isValidFormat =>
      isHttpUrl(rpcUrl) &&
      isHttpUrl(relayerUrl) &&
      isAddress(registryAddress) &&
      isAddress(semaphoreAddress) &&
      chainId > 0;

  @override
  bool operator ==(Object other) =>
      other is NetworkConfig &&
      other.rpcUrl == rpcUrl &&
      other.relayerUrl == relayerUrl &&
      other.registryAddress == registryAddress &&
      other.semaphoreAddress == semaphoreAddress &&
      other.chainId == chainId;

  @override
  int get hashCode => Object.hash(
    rpcUrl,
    relayerUrl,
    registryAddress,
    semaphoreAddress,
    chainId,
  );
}
