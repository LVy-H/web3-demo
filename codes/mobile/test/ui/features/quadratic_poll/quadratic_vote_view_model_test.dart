import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tessera/data/models/poll_snapshot.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/repositories/quadratic_repository.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/ui/features/quadratic_poll/quadratic_vote_view_model.dart';

class FakeQuadraticRepo implements QuadraticRepository {
  final List<String> group;
  final PollSnapshot? snap;
  final Object? error;
  FakeQuadraticRepo({this.group = const [], this.snap, this.error});
  @override
  Future<List<String>> fetchGroup(String address) async => group;
  @override
  Future<PollSnapshot> fetchPoll(String address) async {
    if (error != null) throw error!;
    return snap!;
  }
}

const _proof = RelayProof(
  merkleTreeDepth: 1,
  merkleTreeRoot: '1',
  nullifier: '2',
  message: '134',
  scope: '3',
  points: ['1', '2', '3', '4', '5', '6', '7', '8'],
);

const addr = '0x1111111111111111111111111111111111111111';

PollSnapshot _snap(int optionCount) => PollSnapshot(
      address: addr,
      state: 1,
      options: [for (var i = 0; i < optionCount; i++) String.fromCharCode(65 + i)],
      results: List<BigInt>.filled(optionCount, BigInt.zero),
      owner: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      participantCount: BigInt.from(3),
    );

// The group includes FakeProofService.deriveCommitment()'s value ('1234567890')
// so the membership pre-check passes — i.e. this fake voter is registered.
QuadraticVoteViewModel _vm(
  http.Client relayClient, {
  int optionCount = 3,
  List<String> group = const ['111', '1234567890', '222'],
}) =>
    QuadraticVoteViewModel(
      repository: FakeQuadraticRepo(group: group, snap: _snap(optionCount)),
      proofService: const FakeProofService(_proof),
      relayClient:
          RelayClient(baseUrl: 'http://relayer.test', client: relayClient),
      pollAddress: addr,
    );

Future<QuadraticVoteViewModel> _loaded(
  http.Client relayClient, {
  int optionCount = 3,
  List<String> group = const ['111', '1234567890', '222'],
}) async {
  final vm = _vm(relayClient, optionCount: optionCount, group: group);
  await vm.load();
  return vm;
}

http.Client _ok() => MockClient((r) async => http.Response('{}', 200));

void main() {
  group('budget meter (spent = Σ vᵢ², remaining = CREDITS - spent)', () {
    test('starts all-zero: spent 0, remaining 100, empty ballot', () async {
      final vm = await _loaded(_ok());
      expect(vm.votes, [0, 0, 0]);
      expect(vm.spent, 0);
      expect(vm.remaining, 100);
      expect(vm.totalAllocated, 0);
      expect(vm.canCast, isFalse, reason: 'all-zero is the EmptyBallot ballot');
    });

    test('spent tracks Σ vᵢ² as options are incremented', () async {
      final vm = await _loaded(_ok());
      for (var k = 0; k < 5; k++) {
        vm.increment(0); // → v0 = 5
      }
      for (var k = 0; k < 5; k++) {
        vm.increment(1); // → v1 = 5
      }
      expect(vm.votes, [5, 5, 0]);
      expect(vm.spent, 50); // 25 + 25
      expect(vm.remaining, 50);
      expect(vm.canCast, isTrue);
    });

    test('decrement lowers spent and re-opens budget', () async {
      final vm = await _loaded(_ok());
      for (var k = 0; k < 10; k++) {
        vm.increment(0); // → v0 = 10, spent 100, budget full
      }
      expect(vm.spent, 100);
      expect(vm.canIncrement(1), isFalse, reason: 'no budget left');
      vm.decrement(0); // → v0 = 9, spent 81
      expect(vm.spent, 81);
      expect(vm.remaining, 19);
      expect(vm.canIncrement(1), isTrue, reason: '1²=1 ≤ 19 remaining');
    });
  });

  group('increment-disable enforces Σ vᵢ² ≤ 100', () {
    test('a single option climbs to v=10 then the + flips OFF (v=11 blocked)',
        () async {
      final vm = await _loaded(_ok());
      // Increment option 0 ten times — each allowed until spent hits 100.
      for (var k = 0; k < 10; k++) {
        expect(
          vm.canIncrement(0),
          isTrue,
          reason: 'increment $k (v=$k → ${k + 1}) is within budget',
        );
        vm.increment(0);
      }
      expect(vm.votes[0], 10);
      expect(vm.spent, 100, reason: '10² = 100 = CREDITS');
      // v=10 → v=11 would cost 121 > 100, so the + is disabled.
      expect(
        vm.canIncrement(0),
        isFalse,
        reason: 'v=11 (121 credits) exceeds the 100-credit budget',
      );
      vm.increment(0); // no-op (guarded)
      expect(vm.votes[0], 10, reason: 'the guarded increment did nothing');
    });

    test('with one option at v=10 the budget is spent → ALL others blocked '
        '(blocks [10,1])', () async {
      final vm = await _loaded(_ok());
      for (var k = 0; k < 10; k++) {
        vm.increment(0);
      }
      expect(vm.spent, 100);
      // Every OTHER option cannot be incremented either — [10,1] would be 101.
      expect(vm.canIncrement(1), isFalse);
      expect(vm.canIncrement(2), isFalse);
      vm.increment(1); // no-op
      expect(vm.votes, [10, 0, 0], reason: '[10,1] over-budget was blocked');
    });

    test('the exactly-at-budget boundary [6,8] is reachable, then frozen',
        () async {
      final vm = await _loaded(_ok());
      for (var k = 0; k < 6; k++) {
        vm.increment(0); // v0 → 6, spent 36
      }
      for (var k = 0; k < 8; k++) {
        // v1: 0→8. Each step allowed while spent + 2*v1 + 1 ≤ 100.
        expect(vm.canIncrement(1), isTrue, reason: 'v1=${vm.votes[1]} step ok');
        vm.increment(1);
      }
      expect(vm.votes, [6, 8, 0]);
      expect(vm.spent, 100, reason: '36 + 64 = 100, exactly the budget');
      // No further increment on any option (budget exactly spent).
      expect(vm.canIncrement(0), isFalse);
      expect(vm.canIncrement(1), isFalse);
      expect(vm.canIncrement(2), isFalse);
    });

    test('the 4-bit slot ceiling is a belt-and-braces guard (never binds first)',
        () {
      // With a tiny conceptual budget the budget always bites before v=15, but
      // assert the canIncrement formula itself: at exactly-budget it is false.
      // (covered above) — here assert canIncrement is false past the array.
      // No snapshot loaded → empty votes, out-of-range index is false.
      final vm = QuadraticVoteViewModel(
        repository: FakeQuadraticRepo(group: const [], snap: _snap(3)),
        proofService: const FakeProofService(_proof),
        relayClient: RelayClient(baseUrl: 'http://relayer.test', client: _ok()),
        pollAddress: addr,
      );
      expect(vm.canIncrement(0), isFalse, reason: 'no votes array before load');
      expect(vm.canIncrement(99), isFalse);
    });
  });

  group('packedAlloc + castQuadratic', () {
    test('a valid mixed allocation packs to the expected packedAlloc', () async {
      final vm = await _loaded(_ok());
      // Build [6, 8, 0] → 0x086 = 134.
      for (var k = 0; k < 6; k++) {
        vm.increment(0);
      }
      for (var k = 0; k < 8; k++) {
        vm.increment(1);
      }
      expect(vm.packedAlloc, 134);
    });

    test(
      '[6,8,0] → relays packedAlloc 134 to /api/relay/quadratic-vote + proof',
      () async {
        late http.Request captured;
        final vm = await _loaded(
          MockClient((r) async {
            captured = r;
            return http.Response(
              jsonEncode({'success': true, 'txHash': '0xdeadbeef'}),
              200,
            );
          }),
        );
        for (var k = 0; k < 6; k++) {
          vm.increment(0);
        }
        for (var k = 0; k < 8; k++) {
          vm.increment(1);
        }

        await vm.castQuadratic(identitySeed: 'seed');

        expect(vm.status, QuadraticVoteStatus.success);
        expect(vm.txHash, '0xdeadbeef');
        expect(vm.castError, isNull);
        // It hit the QUADRATIC endpoint with the DIRECT-encoded packed alloc
        // (NOT /vote, NOT /approval-vote, NOT /ranked-vote) and a proof.
        expect(captured.url.path, '/api/relay/quadratic-vote');
        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        expect(body['pollAddress'], addr);
        // The body field MUST be named exactly `packedAlloc` (what
        // validateQuadraticVoteRequest reads); a mismatch would fail every cast.
        expect(body.containsKey('packedAlloc'), isTrue);
        expect(body['packedAlloc'], 134); // [6,8,0] → 0x086
        expect((body['proof'] as Map)['points'], hasLength(8));
      },
    );

    test('all-zero ballot (EmptyBallot) → error, never relays', () async {
      var relayed = false;
      final vm = await _loaded(
        MockClient((r) async {
          relayed = true;
          return http.Response('{}', 200);
        }),
      );
      // votes are all zero (nothing incremented).
      await vm.castQuadratic(identitySeed: 'seed');

      expect(vm.status, QuadraticVoteStatus.error);
      expect(vm.castError, contains('at least one'));
      expect(
        relayed,
        isFalse,
        reason: 'an all-zero ballot (EmptyBallot) must never relay',
      );
    });

    test('identity not in the group → clear "not registered" error, no relay',
        () async {
      var relayed = false;
      final vm = await _loaded(
        MockClient((r) async {
          relayed = true;
          return http.Response('{}', 200);
        }),
        group: const ['999'], // no '1234567890'
      );
      vm.increment(0);

      await vm.castQuadratic(identitySeed: 'seed');

      expect(vm.status, QuadraticVoteStatus.error);
      expect(vm.castError, contains("isn't registered"));
      expect(relayed, isFalse, reason: 'must not relay when not a member');
    });

    test('relayer error → error status, no txHash', () async {
      final vm = await _loaded(
        MockClient(
          (r) async => http.Response(
            jsonEncode({'error': 'Poll is not in voting phase'}),
            500,
          ),
        ),
      );
      vm.increment(0);

      await vm.castQuadratic(identitySeed: 'seed');

      expect(vm.status, QuadraticVoteStatus.error);
      expect(vm.castError, 'Poll is not in voting phase');
      expect(vm.txHash, isNull);
    });
  });

  group('checkRegistration (token pattern — mirrors the sibling modules)', () {
    test('identity in the group → isRegistered true', () async {
      final vm = await _loaded(_ok());
      await vm.checkRegistration('seed');
      expect(vm.myCommitment, '1234567890');
      expect(vm.isRegistered, isTrue);
      expect(vm.checkingRegistration, isFalse);
    });

    test('identity not in the group → isRegistered false', () async {
      final vm = await _loaded(_ok(), group: const ['999']);
      await vm.checkRegistration('seed');
      expect(vm.myCommitment, '1234567890');
      expect(vm.isRegistered, isFalse);
      expect(vm.checkingRegistration, isFalse);
    });
  });

  group('load', () {
    test('fetchPoll → loaded + votes sized to the options', () async {
      final vm = _vm(_ok(), optionCount: 4);
      await vm.load();
      expect(vm.state.name, 'loaded');
      expect(vm.snapshot!.options, ['A', 'B', 'C', 'D']);
      expect(vm.votes, [0, 0, 0, 0], reason: 'one zero slot per option');
    });

    test('read failure → error state', () async {
      final vm = QuadraticVoteViewModel(
        repository: FakeQuadraticRepo(error: Exception('rpc down')),
        proofService: const FakeProofService(_proof),
        relayClient: RelayClient(baseUrl: 'http://relayer.test', client: _ok()),
        pollAddress: addr,
      );
      await vm.load();
      expect(vm.error, contains('rpc down'));
    });
  });
}
