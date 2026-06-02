import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tessera/data/repositories/blind_repository.dart';
import 'package:tessera/data/services/blind_commit_store.dart';
import 'package:tessera/data/services/chain_reader.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

/// End-to-end proof that the full M2 commit-reveal lifecycle LANDS on the host
/// Hardhat node via the local dev-signer: create -> register -> startVoting ->
/// commit -> endVoting -> reveal -> the revealed tally updates on-chain. This is
/// "desktop can actually cast a vote", no prover involved.
///
/// Requires ./dev-stack.sh up. Skips when unreachable.
void main() {
  const devKey =
      '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';

  final fixtureFile = File('test/fixtures/local_chain.json');
  if (!fixtureFile.existsSync()) {
    test('blind flow (no fixture)', () {
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

  test('create → register → vote → reveal lands the tally on-chain', () async {
    if (!await nodeUp()) {
      markTestSkipped('local node not reachable at $rpc');
      return;
    }
    final writer = ChainWriter(rpcUrl: rpc, chainId: 31337, privateKey: devKey);
    final reader = ChainReader(
      rpcUrl: rpc,
      izkPollAbiJson: abiArray('assets/abi/IZkPoll.json'),
      registryAbiJson: registryAbi,
      anonVotingAbiJson: abiArray('assets/abi/ZkAnonVoting.json'),
      blindVotingAbiJson: blindAbi,
      registryAddress: registry,
    );
    addTearDown(writer.dispose);
    addTearDown(reader.dispose);
    final repo = BlindRepository(
      reader: reader,
      writer: writer,
      commits: InMemoryBlindCommitStore(),
      blindAbiJson: blindAbi,
    );
    final signer = writer.signerAddress!;

    // Create a fresh blind poll owned by the dev-signer (so it can drive admin).
    final blind = DeployedContract(
      ContractAbi.fromJson(blindAbi, 'ZkBlindVoting'),
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
    );
    final initData = blind.function('initialize').encodeCall([
      EthereumAddress.fromHex(signer),
      ['Yes', 'No', 'Abstain'],
      BigInt.from(3600), // 1h reveal window
    ]);
    await writer.send(
      to: registry,
      abiJson: registryAbi,
      abiName: 'PollRegistry',
      function: 'createPoll',
      params: ['blind-vote', 'Flow Test', 'commit-reveal e2e', initData],
    );

    // Newest blind poll created by us.
    final mine = (await reader.getAllPolls())
        .where((p) =>
            p.moduleType == 'blind-vote' &&
            p.creator.toLowerCase() == signer.toLowerCase())
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final poll = mine.last.pollAddress;

    // Drive the lifecycle.
    await repo.register(poll);
    await repo.startVoting(poll);
    const chosen = 1; // "No"
    await repo.commit(poll, chosen);
    await repo.endVoting(poll);
    await repo.reveal(poll);

    final snap = await repo.fetch(poll);
    expect(snap.state, 2, reason: 'Ended');
    expect(snap.registered, isTrue);
    expect(snap.committed, isTrue);
    expect(snap.revealed, isTrue);
    expect(snap.results[chosen], BigInt.one,
        reason: 'the revealed "No" vote is tallied on-chain');
    expect(snap.totalRevealed, BigInt.one);
  });
}
