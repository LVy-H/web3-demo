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

/// M2 blind-vote FINALIZE — the tail of the commit-reveal lifecycle that the
/// blind_flow test stops short of. After the reveal window closes the owner
/// finalizes; unrevealed votes are excluded. Uses a short reveal window + a real
/// wait (Hardhat auto-mine stamps blocks with wall-clock time) instead of global
/// evm_increaseTime, so it can't perturb concurrent tests' ticket expiries.
///
/// Requires ./dev-stack.sh up. Skips when unreachable.
void main() {
  // Hardhat account #6 — its own nonce lane.
  const devKey =
      '0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e';

  final fixtureFile = File('test/fixtures/local_chain.json');
  if (!fixtureFile.existsSync()) {
    test('blind finalize (no fixture)', () {
      markTestSkipped('run dev-stack.sh up');
    }, skip: true);
    return;
  }
  final fx = jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final rpc = fx['rpcUrl'] as String;
  final registry = fx['registry'] as String;
  String abi(String p) => jsonEncode(jsonDecode(File(p).readAsStringSync())['abi']);
  final registryAbi = abi('assets/abi/PollRegistry.json');
  final blindAbi = abi('assets/abi/ZkBlindVoting.json');

  Future<bool> nodeUp() async {
    try {
      final r = await http
          .post(Uri.parse(rpc),
              headers: {'content-type': 'application/json'},
              body: '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')
          .timeout(const Duration(seconds: 3));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  test('create → register → commit → reveal → finalize closes results',
      () async {
    if (!await nodeUp()) {
      markTestSkipped('node unreachable');
      return;
    }
    final writer = ChainWriter(rpcUrl: rpc, chainId: 31337, privateKey: devKey);
    final reader = ChainReader(
      rpcUrl: rpc,
      izkPollAbiJson: abi('assets/abi/IZkPoll.json'),
      registryAbiJson: registryAbi,
      anonVotingAbiJson: abi('assets/abi/ZkAnonVoting.json'),
      blindVotingAbiJson: blindAbi,
      registryAddress: registry,
    );
    addTearDown(writer.dispose);
    addTearDown(reader.dispose);
    final repo = BlindRepository(
        reader: reader,
        writer: writer,
        commits: InMemoryBlindCommitStore(),
        blindAbiJson: blindAbi);
    final owner = writer.signerAddress!;

    // Create a blind poll with a SHORT reveal window (3s).
    final blind = DeployedContract(ContractAbi.fromJson(blindAbi, 'ZkBlindVoting'),
        EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'));
    final initData = blind.function('initialize').encodeCall([
      EthereumAddress.fromHex(owner),
      ['Yes', 'No'],
      BigInt.from(3), // revealDuration = 3s
    ]);
    await writer.send(
        to: registry,
        abiJson: registryAbi,
        abiName: 'PollRegistry',
        function: 'createPoll',
        params: ['blind-vote', 'Blind Finalize', 'finalize path', initData]);
    final poll = (await reader.getAllPolls())
        .where((p) =>
            p.moduleType == 'blind-vote' &&
            p.creator.toLowerCase() == owner.toLowerCase())
        .last
        .pollAddress;

    const chosen = 0;
    await repo.register(poll);
    await repo.startVoting(poll);
    await repo.commit(poll, chosen);
    await repo.endVoting(poll); // sets revealDeadline = now + 3s
    await repo.reveal(poll); // promptly, before the 3s window closes

    var snap = await repo.fetch(poll);
    expect(snap.results[chosen], BigInt.one, reason: 'revealed before finalize');
    expect(snap.finalized, isFalse);

    // Wait past the reveal deadline (wall-clock; Hardhat stamps the next block).
    await Future<void>.delayed(const Duration(seconds: 5));
    await repo.finalize(poll);

    snap = await repo.fetch(poll);
    expect(snap.finalized, isTrue, reason: 'results finalized after the window');
    expect(snap.results[chosen], BigInt.one, reason: 'final tally preserved');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
