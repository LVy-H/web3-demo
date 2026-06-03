import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tessera/data/models/poll_snapshot.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/repositories/ranked_repository.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/ui/features/ranked_poll/ranked_vote_view_model.dart';

class FakeRankedRepo implements RankedRepository {
  final List<String> group;
  final PollSnapshot? snap;
  final Object? error;
  FakeRankedRepo({this.group = const [], this.snap, this.error});
  @override
  Future<List<String>> fetchGroup(String address) async => group;
  @override
  Future<PollSnapshot> fetchPoll(String address) async {
    if (error != null) throw error!;
    return snap!;
  }
}

/// A [RankedRepository] whose [fetchGroup] throws, to exercise the failure path
/// of [RankedVoteViewModel.checkRegistration].
class ThrowingRepo implements RankedRepository {
  @override
  Future<List<String>> fetchGroup(String address) async =>
      throw Exception('boom');
  @override
  Future<PollSnapshot> fetchPoll(String address) => throw UnimplementedError();
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
  }) async => proof;
  @override
  void dispose() {}
}

const _proof = RelayProof(
  merkleTreeDepth: 1,
  merkleTreeRoot: '1',
  nullifier: '2',
  message: '531',
  scope: '3',
  points: ['1', '2', '3', '4', '5', '6', '7', '8'],
);

const addr = '0x1111111111111111111111111111111111111111';

// The group includes FakeProofService.deriveCommitment()'s value ('1234567890')
// so the membership pre-check passes — i.e. this fake voter is registered.
RankedVoteViewModel _vm(http.Client relayClient) => RankedVoteViewModel(
  repository: FakeRankedRepo(group: const ['111', '1234567890', '222']),
  proofService: const FakeProofService(_proof),
  relayClient: RelayClient(baseUrl: 'http://relayer.test', client: relayClient),
  pollAddress: addr,
);

void main() {
  group('packFor', () {
    test('packs an ordered ranking into the packed-uint32 ballot (spec table)',
        () {
      expect(RankedVoteViewModel.packFor([0]), 1); // A         → 0x001
      expect(RankedVoteViewModel.packFor([1]), 2); // B         → 0x002
      expect(RankedVoteViewModel.packFor([1, 0]), 18); // B > A     → 0x012
      expect(RankedVoteViewModel.packFor([2, 0, 1]), 531); // C>A>B → 0x213
    });

    test('empty ranking → 0 (the contract EmptyBallot value)', () {
      expect(RankedVoteViewModel.packFor(const <int>[]), 0);
    });
  });

  group('castRanked', () {
    test(
      'ranking [C,A,B] → relays packedRanking 531 + proof → success with txHash',
      () async {
        late http.Request captured;
        final vm = _vm(
          MockClient((r) async {
            captured = r;
            return http.Response(
              jsonEncode({'success': true, 'txHash': '0xdeadbeef'}),
              200,
            );
          }),
        );

        await vm.castRanked(identitySeed: 'seed', ranking: [2, 0, 1]);

        expect(vm.status, RankedVoteStatus.success);
        expect(vm.txHash, '0xdeadbeef');
        expect(vm.castError, isNull);
        // It hit the ranked endpoint with the packed ranking (NOT the single
        // /vote path, NOT the approval bitmask path) and a proof.
        expect(captured.url.path, '/api/relay/ranked-vote');
        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        expect(body['pollAddress'], addr);
        expect(body['packedRanking'], 531); // [C,A,B] → 0x213
        expect((body['proof'] as Map)['points'], hasLength(8));
      },
    );

    test('a single top choice relays its packed value', () async {
      late http.Request captured;
      final vm = RankedVoteViewModel(
        repository: FakeRankedRepo(group: const ['111', '1234567890', '222']),
        proofService: const FakeProofService(_proof),
        relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async {
            captured = r;
            return http.Response(
              jsonEncode({'success': true, 'txHash': '0x1'}),
              200,
            );
          }),
        ),
        pollAddress: addr,
      );

      await vm.castRanked(identitySeed: 'seed', ranking: [1]); // B only

      expect(vm.status, RankedVoteStatus.success);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['packedRanking'], 2); // [B] → 0x002
    });

    test('empty ranking (empty ballot) → error, never relays', () async {
      var relayed = false;
      final vm = RankedVoteViewModel(
        repository: FakeRankedRepo(group: const ['111', '1234567890', '222']),
        proofService: const FakeProofService(_proof),
        relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async {
            relayed = true;
            return http.Response('{}', 200);
          }),
        ),
        pollAddress: addr,
      );

      await vm.castRanked(identitySeed: 'seed', ranking: const []);

      expect(vm.status, RankedVoteStatus.error);
      expect(vm.castError, contains('at least one'));
      expect(
        relayed,
        isFalse,
        reason: 'an empty ballot (EmptyBallot) must never relay',
      );
    });

    test(
      'identity not in the group → clear "not registered" error, no relay',
      () async {
        var relayed = false;
        final vm = RankedVoteViewModel(
          repository: FakeRankedRepo(group: const ['999']), // no '1234567890'
          proofService: const FakeProofService(_proof),
          relayClient: RelayClient(
            baseUrl: 'http://relayer.test',
            client: MockClient((r) async {
              relayed = true;
              return http.Response('{}', 200);
            }),
          ),
          pollAddress: addr,
        );

        await vm.castRanked(identitySeed: 'seed', ranking: [0]);

        expect(vm.status, RankedVoteStatus.error);
        expect(vm.castError, contains("isn't registered"));
        expect(relayed, isFalse, reason: 'must not relay when not a member');
      },
    );

    test('relayer error → error status, no txHash', () async {
      final vm = _vm(
        MockClient(
          (r) async => http.Response(
            jsonEncode({'error': 'Poll is not in voting phase'}),
            500,
          ),
        ),
      );

      await vm.castRanked(identitySeed: 'seed', ranking: [0]);

      expect(vm.status, RankedVoteStatus.error);
      expect(vm.castError, 'Poll is not in voting phase');
      expect(vm.txHash, isNull);
    });
  });

  group('checkRegistration (token pattern — must not regress)', () {
    test('identity in the group → isRegistered true', () async {
      final vm = _vm(MockClient((r) async => http.Response('{}', 200)));
      await vm.checkRegistration('seed');
      expect(vm.myCommitment, '1234567890');
      expect(vm.isRegistered, isTrue);
      expect(vm.checkingRegistration, isFalse);
    });

    test('identity not in the group → isRegistered false', () async {
      final vm = RankedVoteViewModel(
        repository: FakeRankedRepo(group: const ['999']),
        proofService: const FakeProofService(_proof),
        relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200)),
        ),
        pollAddress: addr,
      );
      await vm.checkRegistration('seed');
      expect(vm.myCommitment, '1234567890');
      expect(vm.isRegistered, isFalse);
      expect(vm.checkingRegistration, isFalse);
    });

    test('lookup throws → isRegistered null, checking false', () async {
      final vm = RankedVoteViewModel(
        repository: ThrowingRepo(),
        proofService: const FakeProofService(_proof),
        relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200)),
        ),
        pollAddress: addr,
      );
      await vm.checkRegistration('seed');
      expect(vm.isRegistered, isNull, reason: 'failure leaves status unknown');
      expect(vm.checkingRegistration, isFalse, reason: 'spinner must clear');
    });

    test('a stale result cannot resurrect a cleared panel', () async {
      final gate = Completer<String>();
      final vm = RankedVoteViewModel(
        repository: FakeRankedRepo(group: const ['111', '1234567890', '222']),
        proofService: GatedProofService(_proof, gate),
        relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200)),
        ),
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
  });

  group('load', () {
    test('fetchPoll → loaded with the snapshot', () async {
      final snap = PollSnapshot(
        address: addr,
        state: 1,
        options: const ['A', 'B', 'C'],
        results: [BigInt.from(2), BigInt.from(3), BigInt.one],
        owner: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
        participantCount: BigInt.from(4),
      );
      final vm = RankedVoteViewModel(
        repository: FakeRankedRepo(snap: snap),
        proofService: const FakeProofService(_proof),
        relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200)),
        ),
        pollAddress: addr,
      );
      await vm.load();
      expect(vm.snapshot, isNotNull);
      expect(vm.snapshot!.options, ['A', 'B', 'C']);
    });

    test('read failure → error state', () async {
      final vm = RankedVoteViewModel(
        repository: FakeRankedRepo(error: Exception('rpc down')),
        proofService: const FakeProofService(_proof),
        relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200)),
        ),
        pollAddress: addr,
      );
      await vm.load();
      expect(vm.error, contains('rpc down'));
    });
  });
}
