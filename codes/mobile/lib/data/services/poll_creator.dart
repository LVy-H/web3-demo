import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

import '../../config.dart';
import 'chain_writer.dart';

/// Creates polls through the local dev-signer ([ChainWriter]) — the wallet-free
/// path for local development. When [canSign] is true (DEV_PRIVATE_KEY set), the
/// Create screen can deploy without connecting a wallet, signing directly to the
/// host Hardhat node a phone wallet can't reach.
class PollCreator {
  final ChainWriter writer;
  final String registryAbiJson;
  final String anonAbiJson;

  PollCreator({
    required this.writer,
    required this.registryAbiJson,
    required this.anonAbiJson,
  });

  bool get canSign => writer.canSign;
  String? get signer => writer.signerAddress;

  /// Deploy an anon-vote poll, signed by the dev key. Mirrors the wallet path's
  /// encoding: `ZkAnonVoting.initialize(semaphore, owner, options)` forwarded by
  /// `PollRegistry.createPoll('anon-vote', …)`.
  Future<String> createAnonPoll({
    required String title,
    required String description,
    required List<String> options,
  }) {
    final owner = writer.signerAddress!;
    final anon = DeployedContract(
      ContractAbi.fromJson(anonAbiJson, 'ZkAnonVoting'),
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
    );
    final initData = anon.function('initialize').encodeCall([
      EthereumAddress.fromHex(AppConfig.semaphoreAddress),
      EthereumAddress.fromHex(owner),
      options,
    ]);
    return writer.send(
      to: AppConfig.registryAddress,
      abiJson: registryAbiJson,
      abiName: 'PollRegistry',
      function: 'createPoll',
      params: ['anon-vote', title, description, initData],
    );
  }
}
