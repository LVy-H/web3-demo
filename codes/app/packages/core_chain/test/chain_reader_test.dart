import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:core_chain/chain_reader.dart';

/// Integration test: decodes REAL values from a local Hardhat node, proving the
/// web3dart eth_call + ABI codec works for uint, string[], uint[], address, and
/// the registry struct array (the dynamic-return foot-gun). Unlike the proof
/// verifier, on-chain reads are not mock-tainted.
///
/// Requires a running node + demo poll fixture:
///   cd codes/contracts && npm run deploy:local \
///     && npx hardhat run scripts/demo-poll.ts --network localhost
/// Skips (does not fail) when the node is unreachable.
void main() {
  final chainFixturePath = File('test/fixtures/local_chain.json');
  if (!chainFixturePath.existsSync()) {
    test('on-chain reads (no local_chain.json fixture)', () {
      markTestSkipped('run codes/contracts demo-poll.ts to generate the fixture');
    }, skip: true);
    return;
  }

  final fixture = jsonDecode(chainFixturePath.readAsStringSync()) as Map<String, dynamic>;
  final rpc = fixture['rpcUrl'] as String;
  final poll = fixture['demoPoll'] as Map<String, dynamic>;
  final pollAddr = poll['address'] as String;

  String abiArray(String path) =>
      jsonEncode(jsonDecode(File(path).readAsStringSync())['abi']);

  late ChainReader reader;
  setUpAll(() {
    reader = ChainReader(
      rpcUrl: rpc,
      izkPollAbiJson: abiArray('assets/abi/IZkPoll.json'),
      registryAbiJson: abiArray('assets/abi/PollRegistry.json'),
      anonVotingAbiJson: abiArray('assets/abi/ZkAnonVoting.json'),
      registryAddress: fixture['registry'] as String,
    );
  });
  tearDownAll(() => reader.dispose());

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

  test('IZkPoll reads decode (getState/getOptions/getResults/owner)', () async {
    if (!await nodeUp()) {
      markTestSkipped('local node not reachable at $rpc');
      return;
    }
    expect(await reader.getState(pollAddr), poll['expectedState']);
    expect(await reader.getOptions(pollAddr), (poll['options'] as List).cast<String>());
    expect(
      await reader.getResults(pollAddr),
      (poll['expectedResults'] as List).map((e) => BigInt.from(e as int)).toList(),
    );
    expect(
      (await reader.getOwner(pollAddr)).toLowerCase(),
      (fixture['owner'] as String).toLowerCase(),
    );
    expect(
      await reader.getParticipantCount(pollAddr),
      BigInt.from(poll['expectedParticipantCount'] as int),
    );
  });

  test('getRegisteredCommitments reconstructs the group from event logs',
      () async {
    if (!await nodeUp()) {
      markTestSkipped('local node not reachable at $rpc');
      return;
    }
    final commitments = await reader.getRegisteredCommitments(pollAddr);
    expect(commitments, (poll['registeredCommitments'] as List).cast<String>());
  });

  test('getAllPolls decodes the registry struct array', () async {
    if (!await nodeUp()) {
      markTestSkipped('local node not reachable at $rpc');
      return;
    }
    final polls = await reader.getAllPolls();
    expect(polls, isNotEmpty);
    final demo = polls.firstWhere(
      (p) => p.pollAddress.toLowerCase() == pollAddr.toLowerCase(),
    );
    expect(demo.moduleType, 'anon-vote');
    expect(demo.title, poll['title']);
    expect(demo.description, poll['description']);
  });
}
