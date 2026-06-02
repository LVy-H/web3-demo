import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tessera/data/services/chain_reader.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:tessera/data/services/proof_service_desktop.dart';
import 'package:wallet/wallet.dart' show EthereumAddress;
import 'package:web3dart/web3dart.dart';

/// END-TO-END M1 anonymous vote on Linux via the desktop sidecar — the path the
/// UI exercises and that was reported broken ("leaf at index -1"). Proves the
/// vote works ONCE the identity is a registered member: create poll → derive the
/// voter's commitment → registerVoter → startVoting → generate the Semaphore
/// proof (succeeds now that the commitment is in the group) → it verifies against
/// the real Groth16 vkey.
///
/// Opt-in: RUN_DESKTOP_PROVER=1 flutter test test/integration/anon_vote_test.dart
/// (needs Node + network for the CDN artifacts + the local stack).
void main() {
  const sidecar = 'web_prover/desktop_prover.mjs';
  const bundle = 'web/zkprover.js';
  // Hardhat account #4 (distinct nonce lane from the other write tests).
  const devKey =
      '0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a';

  final fixtureFile = File('test/fixtures/local_chain.json');
  final on = Platform.environment['RUN_DESKTOP_PROVER'] == '1';
  if (!on || !fixtureFile.existsSync() || !File(sidecar).existsSync()) {
    test('anon vote e2e (opt-in)', () {
      markTestSkipped('set RUN_DESKTOP_PROVER=1 + dev-stack up to run');
    }, skip: true);
    return;
  }
  final fixture = jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final rpc = fixture['rpcUrl'] as String;
  final registry = fixture['registry'] as String;
  final semaphore = (fixture['semaphore'] as String?) ??
      '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0';

  String abiArray(String p) =>
      jsonEncode(jsonDecode(File(p).readAsStringSync())['abi']);
  final registryAbi = abiArray('assets/abi/PollRegistry.json');
  final anonAbi = abiArray('assets/abi/ZkAnonVoting.json');

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

  test('registered identity → proof generates AND verifies (real vkey)',
      () async {
    if (!await nodeUp()) {
      markTestSkipped('local node not reachable');
      return;
    }
    final writer = ChainWriter(rpcUrl: rpc, chainId: 31337, privateKey: devKey);
    final reader = ChainReader(
      rpcUrl: rpc,
      izkPollAbiJson: abiArray('assets/abi/IZkPoll.json'),
      registryAbiJson: registryAbi,
      anonVotingAbiJson: anonAbi,
      registryAddress: registry,
    );
    final prover = ProofServiceDesktop(
        nodePath: 'node', sidecarPath: sidecar, bundlePath: bundle);
    addTearDown(writer.dispose);
    addTearDown(reader.dispose);
    addTearDown(prover.dispose);
    final owner = writer.signerAddress!;

    // 1) Create an anon poll owned by the dev-signer.
    final anon = DeployedContract(ContractAbi.fromJson(anonAbi, 'ZkAnonVoting'),
        EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'));
    final initData = anon.function('initialize').encodeCall([
      EthereumAddress.fromHex(semaphore),
      EthereumAddress.fromHex(owner),
      ['Yes', 'No'],
    ]);
    await writer.send(
        to: registry,
        abiJson: registryAbi,
        abiName: 'PollRegistry',
        function: 'createPoll',
        params: ['anon-vote', 'Anon Vote E2E', 'm1 vote path', initData]);
    final poll = (await reader.getAllPolls())
        .where((p) =>
            p.moduleType == 'anon-vote' &&
            p.creator.toLowerCase() == owner.toLowerCase())
        .last
        .pollAddress;

    // 2) Derive the voter's commitment and register it (the missing precondition).
    const seed = 'demo-voter-seed-e2e';
    final commitment = await prover.deriveCommitment(seed);
    await writer.send(
        to: poll,
        abiJson: anonAbi,
        abiName: 'ZkAnonVoting',
        function: 'registerVoter',
        params: [BigInt.parse(commitment)]);
    await writer.send(
        to: poll,
        abiJson: anonAbi,
        abiName: 'ZkAnonVoting',
        function: 'startVoting');

    // 3) The group now contains the voter; the proof must generate + verify.
    final group = await reader.getRegisteredCommitments(poll);
    expect(group, contains(commitment), reason: 'voter is a registered member');

    final proof = await prover.generateVoteProof(
        identitySeed: seed, memberCommitments: group, message: 1, scope: poll);
    expect(proof.points.length, 8);
    expect(await prover.verifyProof(proof), isTrue,
        reason: 'the anon vote proof verifies against the real Groth16 vkey');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
