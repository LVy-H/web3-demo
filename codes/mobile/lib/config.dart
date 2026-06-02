/// Runtime configuration. Defaults target a local Hardhat node + relayer;
/// override per build with --dart-define (e.g. for Sepolia). The registry
/// default matches codes/frontend/src/deployed-addresses.json (chainId 31337).
abstract class AppConfig {
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

  /// Reown/WalletConnect project ID (free, from cloud.reown.com). Without it the
  /// Connect-Wallet button shows a hint instead of initializing.
  /// Build with: --dart-define=WC_PROJECT_ID=YOUR_ID
  static const walletConnectProjectId =
      String.fromEnvironment('WC_PROJECT_ID', defaultValue: '');

  /// EVM chain id for write transactions (default Hardhat 31337).
  static const chainId = int.fromEnvironment('CHAIN_ID', defaultValue: 31337);

  /// LOCAL-DEV signer key. When set, the app can sign + broadcast transactions
  /// directly (no mobile wallet needed) — the only way to cast M2 commit-reveal
  /// votes against the host-local Hardhat node that a phone wallet can't reach.
  /// NEVER set this for a real deployment. Build with:
  ///   `--dart-define=DEV_PRIVATE_KEY=0x...` (a Hardhat account key)
  static const devPrivateKey =
      String.fromEnvironment('DEV_PRIVATE_KEY', defaultValue: '');

  // ── Desktop ZK prover (SP4) — opt-in Node sidecar ──────────────────────────
  // Lets the desktop app (Linux/Windows/macOS) cast Semaphore votes by spawning
  // Node on the SAME web/zkprover.js bundle the web build uses. OFF unless both
  // paths are set, so it never changes default web/mobile/desktop behavior. Set:
  //   --dart-define=DESKTOP_PROVER_SIDECAR=/abs/web_prover/desktop_prover.mjs
  //   --dart-define=DESKTOP_PROVER_BUNDLE=/abs/web/zkprover.js
  static const desktopProverNode =
      String.fromEnvironment('DESKTOP_PROVER_NODE', defaultValue: 'node');
  static const desktopProverSidecar =
      String.fromEnvironment('DESKTOP_PROVER_SIDECAR', defaultValue: '');
  static const desktopProverBundle =
      String.fromEnvironment('DESKTOP_PROVER_BUNDLE', defaultValue: '');

  /// Desktop proving is enabled only when the sidecar + bundle paths are set.
  static bool get desktopProverEnabled =>
      desktopProverSidecar.isNotEmpty && desktopProverBundle.isNotEmpty;
}
