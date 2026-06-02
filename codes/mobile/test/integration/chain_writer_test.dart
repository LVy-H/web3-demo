import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tessera/data/services/chain_reader.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

/// Integration test: proves the local dev-signer can SIGN + BROADCAST a real
/// transaction to the host Hardhat node — the foundation of M2 voting actually
/// landing on desktop. Creates a blind-vote poll via PollRegistry.createPoll and
/// reads it back from getAllPolls.
///
/// Requires the local stack (./dev-stack.sh up). Skips when unreachable.
void main() {
  // Hardhat account #1 (well-known dev key; NEVER a real key). Distinct from the
  // relayer's account #0 to avoid nonce contention.
  const devKey =
      '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';

  final fixtureFile = File('test/fixtures/local_chain.json');
  if (!fixtureFile.existsSync()) {
    test('chain writer (no fixture)', () {
      markTestSkipped('run dev-stack.sh up to generate local_chain.json');
    }, skip: true);
    return;
  }
  final fixture = jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final rpc = fixture['rpcUrl'] as String;
  final registry = fixture['registry'] as String;

  String abiArray(String path) =>
      jsonEncode(jsonDecode(File(path).readAsStringSync())['abi']);
  final registryAbi = abiArray('assets/abi/PollRegistry.json');
  final blindAbi = abiArray('assets/abi/ZkBlindVoting.json');

  Future<bool> nodeUp() async {
    try {
      final res = await http
          .post(Uri.parse(rpc),
              headers: {'content-type': 'application/json'},
              body: '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  test('dev-signer creates a blind-vote poll that lands on-chain', () async {
    if (!await nodeUp()) {
      markTestSkipped('local node not reachable at $rpc');
      return;
    }
    final writer = ChainWriter(rpcUrl: rpc, chainId: 31337, privateKey: devKey);
    addTearDown(writer.dispose);
    expect(writer.canSign, isTrue);

    // Encode ZkBlindVoting.initialize(owner, options, revealDuration) as the
    // module init calldata.
    final blind = DeployedContract(
      ContractAbi.fromJson(blindAbi, 'ZkBlindVoting'),
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
    );
    final initData = blind.function('initialize').encodeCall([
      EthereumAddress.fromHex(writer.signerAddress!),
      ['Yes', 'No', 'Abstain'],
      BigInt.from(3600),
    ]);

    final hash = await writer.send(
      to: registry,
      abiJson: registryAbi,
      abiName: 'PollRegistry',
      function: 'createPoll',
      params: ['blind-vote', 'Blind Demo Poll', 'commit-reveal test', initData],
    );
    expect(hash, startsWith('0x'));

    // Read it back: a blind-vote poll now exists in the registry.
    final reader = ChainReader(
      rpcUrl: rpc,
      izkPollAbiJson: abiArray('assets/abi/IZkPoll.json'),
      registryAbiJson: registryAbi,
      anonVotingAbiJson: abiArray('assets/abi/ZkAnonVoting.json'),
      registryAddress: registry,
    );
    addTearDown(reader.dispose);
    final polls = await reader.getAllPolls();
    expect(polls.any((p) => p.moduleType == 'blind-vote'), isTrue,
        reason: 'the blind poll we just created is listed');
  });
}
