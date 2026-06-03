import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tessera/data/models/poll_snapshot.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/repositories/approval_repository.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/ui/features/approval_poll/approval_vote_view_model.dart';

class FakeApprovalRepo implements ApprovalRepository {
  final List<String> group;
  final PollSnapshot? snap;
  final Object? error;
  FakeApprovalRepo({this.group = const [], this.snap, this.error});
  @override
  Future<List<String>> fetchGroup(String address) async => group;
  @override
  Future<PollSnapshot> fetchPoll(String address) async {
    if (error != null) throw error!;
    return snap!;
  }
}

/// An [ApprovalRepository] whose [fetchGroup] throws, to exercise the failure
/// path of [ApprovalVoteViewModel.checkRegistration].
class ThrowingRepo implements ApprovalRepository {
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
  message: '5',
  scope: '3',
  points: ['1', '2', '3', '4', '5', '6', '7', '8'],
);

const addr = '0x1111111111111111111111111111111111111111';

// The group includes FakeProofService.deriveCommitment()'s value ('1234567890')
// so the membership pre-check passes — i.e. this fake voter is registered.
ApprovalVoteViewModel _vm(http.Client relayClient) => ApprovalVoteViewModel(
  repository: FakeApprovalRepo(group: const ['111', '1234567890', '222']),
  proofService: const FakeProofService(_proof),
  relayClient: RelayClient(baseUrl: 'http://relayer.test', client: relayClient),
  pollAddress: addr,
);

void main() {
  group('bitmaskFor', () {
    test('packs approved indices into a bitmask (LSB = option 0)', () {
      expect(ApprovalVoteViewModel.bitmaskFor({0}), 1); // 001
      expect(ApprovalVoteViewModel.bitmaskFor({1}), 2); // 010
      expect(ApprovalVoteViewModel.bitmaskFor({0, 2}), 5); // 101
      expect(ApprovalVoteViewModel.bitmaskFor({0, 1, 2}), 7); // 111
    });

    test('empty set → 0 (the contract EmptyBallot value)', () {
      expect(ApprovalVoteViewModel.bitmaskFor(const <int>{}), 0);
    });

    test('select-all over N options → all-ones mask', () {
      // 5 options approved → 0b11111 = 31.
      expect(ApprovalVoteViewModel.bitmaskFor({0, 1, 2, 3, 4}), 31);
      // 32-option cap → all-ones is 2^32 - 1. Asserted as a plain decimal
      // literal, never `1 << 32`, so the expectation itself can't truncate.
      expect(
        ApprovalVoteViewModel.bitmaskFor({for (var i = 0; i < 32; i++) i}),
        4294967295,
      );
    });

    // High-index value-locks. The contract allows option index 31, so the mask
    // must reach bit 31 / bit 32. The OLD `mask |= 1 << i` body computed these
    // correctly on the 64-bit Dart VM but WRONG on Flutter web (dart2js), where
    // `int` `<<` truncates to 32-bit signed, so `1 << 31` overflows to negative
    // and breaks the proof binding.
    //
    // HONEST CAVEAT: `flutter test` runs on the 64-bit VM, so these assertions
    // would ALSO pass against the old code here — they do NOT reproduce the web
    // bug. They lock the contract value on every platform; correctness on web is
    // secured by the BigInt construction being platform-independent, not by this
    // VM test. Each expected value is a typed-out decimal literal (no shifts) so
    // the expectation can never itself truncate.
    test('high option indices keep full precision (web dart2js regression)', () {
      // 2^31 — the bit the old `1 << 31` corrupted on web.
      expect(ApprovalVoteViewModel.bitmaskFor({31}), 2147483648);
      // 2^0 + 2^31.
      expect(ApprovalVoteViewModel.bitmaskFor({0, 31}), 2147483649);
    });
  });

  group('castApproval', () {
    test(
      'approved {0,2} → relays bitmask 5 + proof → success with txHash',
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

        await vm.castApproval(identitySeed: 'seed', approvedIndices: {0, 2});

        expect(vm.status, ApprovalVoteStatus.success);
        expect(vm.txHash, '0xdeadbeef');
        expect(vm.castError, isNull);
        // It hit the approval endpoint with the bitmask (NOT the single-option
        // /vote path) and a proof.
        expect(captured.url.path, '/api/relay/approval-vote');
        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        expect(body['pollAddress'], addr);
        expect(body['bitmask'], 5); // {0,2} → 101
        expect((body['proof'] as Map)['points'], hasLength(8));
      },
    );

    test('select-all relays the all-ones mask', () async {
      late http.Request captured;
      final vm = ApprovalVoteViewModel(
        // 3-option group; voter is registered.
        repository: FakeApprovalRepo(group: const ['111', '1234567890', '222']),
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

      await vm.castApproval(identitySeed: 'seed', approvedIndices: {0, 1, 2});

      expect(vm.status, ApprovalVoteStatus.success);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['bitmask'], 7); // {0,1,2} → 111
    });

    test('select-none (empty ballot) → error, never relays', () async {
      var relayed = false;
      final vm = ApprovalVoteViewModel(
        repository: FakeApprovalRepo(group: const ['111', '1234567890', '222']),
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

      await vm.castApproval(identitySeed: 'seed', approvedIndices: const {});

      expect(vm.status, ApprovalVoteStatus.error);
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
        final vm = ApprovalVoteViewModel(
          repository: FakeApprovalRepo(group: const ['999']), // no '1234567890'
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

        await vm.castApproval(identitySeed: 'seed', approvedIndices: {0});

        expect(vm.status, ApprovalVoteStatus.error);
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

      await vm.castApproval(identitySeed: 'seed', approvedIndices: {0});

      expect(vm.status, ApprovalVoteStatus.error);
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
      final vm = ApprovalVoteViewModel(
        repository: FakeApprovalRepo(group: const ['999']),
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
      final vm = ApprovalVoteViewModel(
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
      // deriveCommitment is gated so the first check suspends at its first
      // await; we then clear (superseding it) and let the stale result arrive —
      // it must be dropped, not written.
      final gate = Completer<String>();
      final vm = ApprovalVoteViewModel(
        repository: FakeApprovalRepo(group: const ['111', '1234567890', '222']),
        proofService: GatedProofService(_proof, gate),
        relayClient: RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200)),
        ),
        pollAddress: addr,
      );

      final pending = vm.checkRegistration(
        'seed',
      ); // suspends at deriveCommitment
      expect(vm.checkingRegistration, isTrue);

      vm.clearRegistration(); // bumps token, nulls fields
      gate.complete('1234567890'); // stale result now arrives
      await pending; // resumes, hits the token guard, returns without writing

      expect(
        vm.myCommitment,
        isNull,
        reason: 'stale commitment must not return',
      );
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
      final vm = ApprovalVoteViewModel(
        repository: FakeApprovalRepo(snap: snap),
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
      final vm = ApprovalVoteViewModel(
        repository: FakeApprovalRepo(error: Exception('rpc down')),
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
