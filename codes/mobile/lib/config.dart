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
}
