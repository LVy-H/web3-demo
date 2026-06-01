import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkvote_mobile/data/models/poll_info.dart';
import 'package:zkvote_mobile/data/models/poll_snapshot.dart';
import 'package:zkvote_mobile/data/models/poll_summary.dart';
import 'package:zkvote_mobile/data/models/relay_proof.dart';
import 'package:zkvote_mobile/data/repositories/poll_repository.dart';
import 'package:zkvote_mobile/data/services/proof_service.dart';
import 'package:zkvote_mobile/data/services/relay_client.dart';
import 'package:zkvote_mobile/ui/features/poll_detail/vote_view_model.dart';

class FakeRepo implements PollRepository {
  final List<String> group;
  FakeRepo(this.group);
  @override
  Future<List<String>> fetchGroup(String address) async => group;
  @override
  Future<List<PollInfo>> fetchPolls() => throw UnimplementedError();
  @override
  Future<PollSnapshot> fetchPoll(String address) => throw UnimplementedError();
  @override
  Future<PollSummary> fetchSummary(String address) => throw UnimplementedError();
}

const _proof = RelayProof(
  merkleTreeDepth: 1,
  merkleTreeRoot: '1',
  nullifier: '2',
  message: '1',
  scope: '3',
  points: ['1', '2', '3', '4', '5', '6', '7', '8'],
);

const addr = '0x1111111111111111111111111111111111111111';

VoteViewModel _vm(http.Client relayClient) => VoteViewModel(
      repository: FakeRepo(const ['111', '222']),
      proofService: const FakeProofService(_proof),
      relayClient: RelayClient(baseUrl: 'http://relayer.test', client: relayClient),
      pollAddress: addr,
    );

void main() {
  test('castVote: group → proof → relay → success with txHash', () async {
    late http.Request captured;
    final vm = _vm(MockClient((r) async {
      captured = r;
      return http.Response(jsonEncode({'success': true, 'txHash': '0xdeadbeef'}), 200);
    }));

    await vm.castVote(identitySeed: 'seed', optionIndex: 2);

    expect(vm.status, VoteStatus.success);
    expect(vm.txHash, '0xdeadbeef');
    expect(vm.error, isNull);
    // it actually relayed the chosen option + a proof
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['pollAddress'], addr);
    expect(body['vote'], 2);
    expect((body['proof'] as Map)['points'], hasLength(8));
  });

  test('castVote: relayer error → error status, no txHash', () async {
    final vm = _vm(MockClient(
      (r) async => http.Response(jsonEncode({'error': 'Poll is not in voting phase'}), 500),
    ));

    await vm.castVote(identitySeed: 'seed', optionIndex: 0);

    expect(vm.status, VoteStatus.error);
    expect(vm.error, 'Poll is not in voting phase');
    expect(vm.txHash, isNull);
  });
}
