import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tessera/data/models/poll_info.dart';
import 'package:tessera/data/models/poll_snapshot.dart';
import 'package:tessera/data/models/poll_summary.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/repositories/poll_repository.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/ui/features/poll_detail/vote_view_model.dart';

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

/// A [PollRepository] whose [fetchGroup] throws, to exercise the failure path
/// of [VoteViewModel.checkRegistration].
class ThrowingRepo implements PollRepository {
  @override
  Future<List<String>> fetchGroup(String address) async =>
      throw Exception('boom');
  @override
  Future<List<PollInfo>> fetchPolls() => throw UnimplementedError();
  @override
  Future<PollSnapshot> fetchPoll(String address) => throw UnimplementedError();
  @override
  Future<PollSummary> fetchSummary(String address) => throw UnimplementedError();
}

/// A [ProofService] whose [deriveCommitment] resolves only when [completer]
/// completes — lets a test suspend a checkRegistration() mid-flight so a
/// superseding clearRegistration() can interleave deterministically.
class GatedProofService implements ProofService {
  final RelayProof proof;
  final Completer<String> completer;
  const GatedProofService(this.proof, this.completer);

  @override
  Future<String> deriveCommitment(String identitySeed) => completer.future;

  @override
  Future<RelayProof> generateVoteProof({
    required String identitySeed,
    required List<String> memberCommitments,
    required int message,
    required String scope,
  }) async =>
      proof;

  @override
  Future<RelayProof> generateVoteProofWide({
    required String identitySeed,
    required List<String> memberCommitments,
    required String message,
    required String scope,
  }) async =>
      proof;

  @override
  void dispose() {}
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

// The group includes FakeProofService.deriveCommitment()'s value ('1234567890')
// so the membership pre-check passes — i.e. this fake voter is registered.
VoteViewModel _vm(http.Client relayClient) => VoteViewModel(
      repository: FakeRepo(const ['111', '1234567890', '222']),
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

  test('castVote: identity not in the group → clear "not registered" error',
      () async {
    var relayed = false;
    final vm = VoteViewModel(
      repository: FakeRepo(const ['999']), // does NOT contain '1234567890'
      proofService: const FakeProofService(_proof),
      relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async {
            relayed = true;
            return http.Response('{}', 200);
          })),
      pollAddress: addr,
    );

    await vm.castVote(identitySeed: 'seed', optionIndex: 1);

    expect(vm.status, VoteStatus.error);
    expect(vm.error, contains("isn't registered"));
    expect(relayed, isFalse, reason: 'must not relay when not a member');
  });

  test('checkRegistration: identity in the group → isRegistered true', () async {
    // FakeProofService.deriveCommitment() returns '1234567890', which the
    // default _vm group contains.
    final vm = _vm(MockClient((r) async => http.Response('{}', 200)));
    await vm.checkRegistration('seed');
    expect(vm.myCommitment, '1234567890');
    expect(vm.isRegistered, isTrue);
    expect(vm.checkingRegistration, isFalse);
  });

  test('checkRegistration: identity not in the group → isRegistered false',
      () async {
    final vm = VoteViewModel(
      repository: FakeRepo(const ['999']), // no '1234567890'
      proofService: const FakeProofService(_proof),
      relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200))),
      pollAddress: addr,
    );
    await vm.checkRegistration('seed');
    expect(vm.myCommitment, '1234567890');
    expect(vm.isRegistered, isFalse);
    expect(vm.checkingRegistration, isFalse);
  });

  test(
      'checkRegistration: lookup throws → isRegistered null, checking false',
      () async {
    final vm = VoteViewModel(
      repository: ThrowingRepo(), // fetchGroup throws
      proofService: const FakeProofService(_proof),
      relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200))),
      pollAddress: addr,
    );

    await vm.checkRegistration('seed');

    expect(vm.isRegistered, isNull, reason: 'failure leaves status unknown');
    expect(vm.checkingRegistration, isFalse, reason: 'spinner must clear');
  });

  test(
      'checkRegistration: a stale result cannot resurrect a cleared panel',
      () async {
    // deriveCommitment is gated on this completer so the first check suspends
    // at its first await; we then clear (superseding it) and let the stale
    // result arrive — it must be dropped, not written.
    final gate = Completer<String>();
    final vm = VoteViewModel(
      repository: FakeRepo(const ['111', '1234567890', '222']),
      proofService: GatedProofService(_proof, gate),
      relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200))),
      pollAddress: addr,
    );

    final pending = vm.checkRegistration('seed'); // suspends at deriveCommitment
    expect(vm.checkingRegistration, isTrue);

    vm.clearRegistration(); // bumps token, nulls fields
    gate.complete('1234567890'); // stale result now arrives
    await pending; // resumes, hits the token guard, returns without writing

    expect(vm.myCommitment, isNull, reason: 'stale commitment must not return');
    expect(vm.isRegistered, isNull, reason: 'cleared panel stays cleared');
    expect(vm.checkingRegistration, isFalse);
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
