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
}
