import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:core_chain/chain_reader.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_relay/sponsored_poll_creator.dart';

/// LIVE proof of the R4 sponsored-create wire decision: the client sends
/// PRE-R4 initData + the top-level `visibility`/`resultsPolicy` JSON fields,
/// the relayer's shim appends the policy server-side, and the poll lands
/// on-chain with the requested policies (PR #108 + this migration's wire
/// decision in `sponsored_poll_creator.dart`).
///
/// Requires the local stack (./dev-stack.sh up): chain on :8545 with the R4
/// contracts + relayer on :3001. Skips when unreachable.
void main() {
  const relayerBase = 'http://localhost:3001';

  final fixtureFile = File('../core_chain/test/fixtures/local_chain.json');
  if (!fixtureFile.existsSync()) {
    test('sponsored create (no fixture)', () {
      markTestSkipped('run dev-stack.sh up to generate local_chain.json');
    }, skip: true);
    return;
  }
  final fixture =
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final rpc = fixture['rpcUrl'] as String;
  final registry = fixture['registry'] as String;

  String abiArray(String path) =>
      jsonEncode(jsonDecode(File(path).readAsStringSync())['abi']);
  String chainAbi(String name) =>
      abiArray('../core_chain/assets/abi/$name.json');

  Future<bool> stackUp() async {
    try {
      final r = await http
          .get(Uri.parse('$relayerBase/api/relay/status'))
          .timeout(const Duration(seconds: 3));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  test('sponsored create: pre-R4 initData + JSON policy fields → poll lands '
      'unlisted with resultsPolicy=1 (the shim appended it)', () async {
    if (!await stackUp()) {
      markTestSkipped('relayer not running on :3001');
      return;
    }
    final relay = RelayClient(baseUrl: relayerBase);
    addTearDown(relay.close);
    final creator = SponsoredPollCreator(
      relay: relay,
      flatModuleAbiJson: chainAbi('ZkAnonVoting'),
      surveyVotingAbiJson: chainAbi('ZkSurveyVoting'),
    );

    final result = await creator.createFlatPoll(
      moduleType: 'anon-vote',
      title: 'R4 wire test ${DateTime.now().millisecondsSinceEpoch}',
      description: 'sponsored pre-R4 initData + resultsPolicy field',
      options: const ['Yes', 'No'],
      // visibility stays 0 (default) — the directory must not gain noise;
      // resultsPolicy=1 proves the JSON field reaches the chain through the
      // relayer's initData shim.
      resultsPolicy: 1,
    );
    expect(result.ok, isTrue, reason: 'relayer error: ${result.error}');
    final pollAddress = result.pollAddress!;

    final reader = ChainReader(
      rpcUrl: rpc,
      izkPollAbiJson: chainAbi('IZkPoll'),
      registryAbiJson: chainAbi('PollRegistry'),
      anonVotingAbiJson: chainAbi('ZkAnonVoting'),
      registryAddress: registry,
    );
    addTearDown(reader.dispose);

    final info = await reader.getPollInfo(pollAddress);
    expect(info, isNotNull, reason: 'link access resolves the new poll');
    expect(
      info!.visibility,
      0,
      reason: 'no visibility opt-in ⇒ unlisted default',
    );
    expect(
      await reader.getResultsPolicy(pollAddress),
      1,
      reason:
          'the top-level resultsPolicy field was appended into '
          'initialize by the relayer shim',
    );
  });
}
