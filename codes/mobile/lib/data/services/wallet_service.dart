import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:reown_appkit/reown_appkit.dart';

import '../../config.dart';

/// Reown supports web / Android / iOS / macOS, not Linux/Windows desktop.
bool get walletSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// App-level wallet session (Reown AppKit / WalletConnect) shared by the drawer
/// Connect button and the Create screen, so both use ONE session. Also encodes
/// + sends `PollRegistry.createPoll` through the connected wallet.
///
/// Reality: needs WC_PROJECT_ID; the connect/sign path is only verifiable on a
/// real device with a wallet (not headlessly). A phone wallet must be able to
/// reach the target chain's RPC, so an actual on-chain create wants a PUBLIC
/// testnet — the host-local Hardhat node isn't reachable from a phone wallet.
class WalletService extends ChangeNotifier {
  final String registryAbiJson;
  final String anonAbiJson;
  WalletService({required this.registryAbiJson, required this.anonAbiJson});

  ReownAppKitModal? _modal;
  ReownAppKitModal? get modal => _modal;
  bool _initing = false;
  String? error;

  bool get supported => walletSupported;
  bool get ready => _modal != null;
  bool get configured => AppConfig.walletConnectProjectId.isNotEmpty;
  bool get isConnected => _modal?.isConnected ?? false;
  String? get address =>
      isConnected ? _modal?.session?.getAddress('eip155') : null;

  /// Create + init the modal once (idempotent). Needs a mounted [context].
  Future<void> ensureInit(BuildContext context) async {
    if (_modal != null || _initing || !supported || !configured) return;
    _initing = true;
    try {
      final m = ReownAppKitModal(
        context: context,
        projectId: AppConfig.walletConnectProjectId,
        metadata: const PairingMetadata(
          name: 'Tessera',
          description: 'Tessera — anonymous on-chain voting',
          // The real repo; Reown requires a non-empty url and we own no domain.
          url: 'https://github.com/LVy-H/web3-demo',
          icons: ['https://avatars.githubusercontent.com/u/37784886'],
        ),
      );
      await m.init();
      m.addListener(_onModalChanged);
      _modal = m;
    } catch (e) {
      error = e.toString();
    } finally {
      _initing = false;
      notifyListeners();
    }
  }

  void _onModalChanged() => notifyListeners();

  /// Deploy an anon-vote poll via the connected wallet. Returns the tx hash.
  /// Throws [StateError] if no wallet is connected.
  Future<String> createPoll({
    required String title,
    required String description,
    required List<String> options,
  }) async {
    final m = _modal;
    if (m == null || !m.isConnected) {
      throw StateError('Connect a wallet first.');
    }
    final owner = m.session?.getAddress('eip155');
    if (owner == null) throw StateError('No connected account.');

    // ZkAnonVoting.initialize(semaphore, owner, options) → the init blob the
    // registry forwards to the freshly-cloned poll (mirrors the web CreatePoll
    // + scripts/demo-poll.ts encoding).
    final anon = DeployedContract(
      ContractAbi.fromJson(anonAbiJson, 'ZkAnonVoting'),
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
    );
    final initData = anon.function('initialize').encodeCall([
      EthereumAddress.fromHex(AppConfig.semaphoreAddress),
      EthereumAddress.fromHex(owner),
      options,
    ]);

    final registry = DeployedContract(
      ContractAbi.fromJson(registryAbiJson, 'PollRegistry'),
      EthereumAddress.fromHex(AppConfig.registryAddress),
    );

    final res = await m.requestWriteContract(
      topic: m.session!.topic!,
      chainId: m.selectedChain!.chainId,
      deployedContract: registry,
      functionName: 'createPoll',
      transaction: Transaction(from: EthereumAddress.fromHex(owner)),
      parameters: <dynamic>['anon-vote', title, description, initData],
    );
    return res.toString();
  }

  @override
  void dispose() {
    _modal?.removeListener(_onModalChanged);
    super.dispose();
  }
}
