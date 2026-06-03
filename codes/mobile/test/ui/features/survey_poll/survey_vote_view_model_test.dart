import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tessera/core/crypto/survey_commit.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/repositories/survey_repository.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/ui/features/survey_poll/survey_vote_view_model.dart';

class FakeSurveyRepo implements SurveyRepository {
  final List<String> group;
  final SurveyStructure? structure;
  final Object? error;
  FakeSurveyRepo({this.group = const [], this.structure, this.error});
  @override
  Future<List<String>> fetchGroup(String address) async => group;
  @override
  Future<SurveyStructure> fetchSurvey(String address) async {
    if (error != null) throw error!;
    return structure!;
  }

  @override
  Future<List<List<BigInt>>> getSurveyResults(String address) async =>
      structure!.results;
}

const _proof = RelayProof(
  merkleTreeDepth: 1,
  merkleTreeRoot: '1',
  nullifier: '2',
  // This message is DELIBERATELY a sentinel — FakeProofService.generateVoteProofWide
  // ECHOES the passed message into proof.message, so any test that casts asserts
  // the ECHOED commitment, never this literal.
  message: 'SENTINEL_SHOULD_BE_OVERWRITTEN',
  scope: '3',
  points: ['1', '2', '3', '4', '5', '6', '7', '8'],
);

const addr = '0x1111111111111111111111111111111111111111';

/// Build a survey structure: [types] is one QType per question (0 single, 1
/// multi); each question gets [optionCounts[q]] options.
SurveyStructure _struct({
  required List<int> types,
  required List<int> optionCounts,
  int state = 1,
}) =>
    SurveyStructure(
      address: addr,
      state: state,
      questions: [
        for (var q = 0; q < types.length; q++)
          SurveyQuestion(
            type: types[q],
            options: [
              for (var i = 0; i < optionCounts[q]; i++) 'Q${q}o$i',
            ],
          ),
      ],
      results: [
        for (var q = 0; q < types.length; q++)
          List<BigInt>.filled(optionCounts[q], BigInt.zero),
      ],
      owner: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      participantCount: BigInt.from(3),
    );

// The group includes FakeProofService.deriveCommitment()'s value ('1234567890')
// so the membership pre-check passes — i.e. this fake voter is registered.
SurveyVoteViewModel _vm(
  http.Client relayClient, {
  required SurveyStructure structure,
  List<String> group = const ['111', '1234567890', '222'],
}) =>
    SurveyVoteViewModel(
      repository: FakeSurveyRepo(group: group, structure: structure),
      proofService: const FakeProofService(_proof),
      relayClient:
          RelayClient(baseUrl: 'http://relayer.test', client: relayClient),
      pollAddress: addr,
    );

Future<SurveyVoteViewModel> _loaded(
  http.Client relayClient, {
  required SurveyStructure structure,
  List<String> group = const ['111', '1234567890', '222'],
}) async {
  final vm = _vm(relayClient, structure: structure, group: group);
  await vm.load();
  return vm;
}

http.Client _ok() => MockClient((r) async => http.Response('{}', 200));

void main() {
  group('load', () {
    test('fetchSurvey → loaded + answer state sized to the questions', () async {
      final vm = await _loaded(
        _ok(),
        structure: _struct(types: [0, 1], optionCounts: [3, 4]),
      );
      expect(vm.state.name, 'loaded');
      expect(vm.questionCount, 2);
      expect(vm.singleSelections, [-1, -1]);
      expect(vm.multiSelections, [<int>{}, <int>{}]);
    });

    test('read failure → error state', () async {
      final vm = SurveyVoteViewModel(
        repository: FakeSurveyRepo(error: Exception('rpc down')),
        proofService: const FakeProofService(_proof),
        relayClient: RelayClient(baseUrl: 'http://relayer.test', client: _ok()),
        pollAddress: addr,
      );
      await vm.load();
      expect(vm.error, contains('rpc down'));
    });
  });

  group('answer encoding — buildAnswers()', () {
    test('SingleChoice answers vector = the selected option indices', () async {
      final vm = await _loaded(
        _ok(),
        structure: _struct(types: [0, 0], optionCounts: [3, 4]),
      );
      vm.selectSingle(0, 2); // Q0 → option 2
      vm.selectSingle(1, 1); // Q1 → option 1
      expect(vm.buildAnswers(), [BigInt.from(2), BigInt.from(1)]);
    });

    test('MultiSelect answers vector = the correct BigInt bitmask', () async {
      final vm = await _loaded(
        _ok(),
        structure: _struct(types: [1], optionCounts: [4]),
      );
      vm.toggleMulti(0, 0); // option 0
      vm.toggleMulti(0, 2); // option 2  → bitmask 0b0101 = 5
      expect(vm.buildAnswers(), [BigInt.from(5)]);
    });

    test(
      'MultiSelect with a HIGH option index (31) locks the BigInt path '
      '(a 1<<31 regression would corrupt it)',
      () async {
        final vm = await _loaded(
          _ok(),
          structure: _struct(types: [1], optionCounts: [32]),
        );
        vm.toggleMulti(0, 0); // bit 0
        vm.toggleMulti(0, 31); // bit 31 — needs BigInt; `1 << 31` overflows
        // a dart2js 32-bit int (becomes negative). The correct mask is
        // 2^31 + 2^0 = 2147483648 + 1 = 2147483649.
        final expected = (BigInt.one << 31) | BigInt.one;
        expect(expected, BigInt.parse('2147483649'));
        expect(vm.buildAnswers(), [expected]);
      },
    );

    test('mixed survey: SingleChoice index + MultiSelect bitmask, in order',
        () async {
      final vm = await _loaded(
        _ok(),
        structure: _struct(types: [0, 1], optionCounts: [3, 4]),
      );
      vm.selectSingle(0, 2); // Q0 single → 2
      vm.toggleMulti(1, 0); // Q1 multi → {0,2}
      vm.toggleMulti(1, 2);
      // The worked spec vector: answers = [2, 5].
      expect(vm.buildAnswers(), [BigInt.from(2), BigInt.from(5)]);
    });
  });

  group('validation gates the cast', () {
    test('allAnswered: false until every question has an answer', () async {
      final vm = await _loaded(
        _ok(),
        structure: _struct(types: [0, 1], optionCounts: [3, 4]),
      );
      expect(vm.allAnswered, isFalse);
      vm.selectSingle(0, 1); // Q0 answered…
      expect(vm.allAnswered, isFalse, reason: 'Q1 still empty');
      vm.toggleMulti(1, 0); // …Q1 now has ≥1 box
      expect(vm.allAnswered, isTrue);
      expect(vm.canCast, isTrue);
    });

    test('an unanswered question blocks the cast — never relays', () async {
      var relayed = false;
      final vm = await _loaded(
        MockClient((r) async {
          relayed = true;
          return http.Response('{}', 200);
        }),
        structure: _struct(types: [0, 1], optionCounts: [3, 4]),
      );
      vm.selectSingle(0, 1); // only Q0 answered; Q1 left empty
      await vm.castSurvey(identitySeed: 'seed');
      expect(vm.status, SurveyVoteStatus.error);
      expect(vm.castError, contains('every question'));
      expect(relayed, isFalse, reason: 'a partial ballot must never relay');
    });

    test('a MultiSelect with zero boxes is unanswered', () async {
      final vm = await _loaded(
        _ok(),
        structure: _struct(types: [1], optionCounts: [4]),
      );
      expect(vm.isAnswered(0), isFalse);
      vm.toggleMulti(0, 1);
      expect(vm.isAnswered(0), isTrue);
      vm.toggleMulti(0, 1); // un-check → empty again
      expect(vm.isAnswered(0), isFalse);
    });
  });

  group('cast binds message == surveyCommitment(answers) AND relays the SAME '
      'vector (the load-bearing test)', () {
    test(
      'the relayed answers + the proof message both match the committed vector',
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
          structure: _struct(types: [0, 1], optionCounts: [3, 4]),
        );
        // Build the worked spec vector: Q0 single → 2, Q1 multi → {0,2} = 5.
        vm.selectSingle(0, 2);
        vm.toggleMulti(1, 0);
        vm.toggleMulti(1, 2);

        // Compute the EXPECTED vector + commitment INDEPENDENTLY in the test.
        final expectedAnswers = [BigInt.from(2), BigInt.from(5)];
        final expectedMessage = surveyCommitment(expectedAnswers);

        await vm.castSurvey(identitySeed: 'seed');

        expect(vm.status, SurveyVoteStatus.success);
        expect(vm.txHash, '0xdeadbeef');
        expect(vm.castError, isNull);

        // It hit the SURVEY endpoint (NOT /vote, /approval-vote, /ranked-vote,
        // or /quadratic-vote).
        expect(captured.url.path, '/api/relay/survey-vote');
        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        expect(body['pollAddress'], addr);

        // (c) The cast BINDS the proof message to surveyCommitment(answers):
        // FakeProofService.generateVoteProofWide echoes the passed message into
        // proof.message, which the relay then sends. So the message on the wire
        // == the commitment the screen computed == surveyCommitment(expected).
        final proof = body['proof'] as Map<String, dynamic>;
        expect(proof['message'], expectedMessage.toString());

        // (e) The relayed `answers` == the SAME committed vector, as the
        // decimal-string array the relayer's validateSurveyVoteRequest expects.
        expect(
          body['answers'],
          [for (final a in expectedAnswers) a.toString()],
          reason: 'the answers relayed must be the vector that was committed',
        );
        // And that vector, re-committed, reproduces the bound message — proving
        // the screen relays EXACTLY what it signed (no re-weight is possible).
        final relayedAnswers = (body['answers'] as List)
            .map((s) => BigInt.parse(s as String))
            .toList();
        expect(surveyCommitment(relayedAnswers).toString(), proof['message']);
      },
    );

    test(
      'the high-index multiselect commitment round-trips through the relay',
      () async {
        late http.Request captured;
        final vm = await _loaded(
          MockClient((r) async {
            captured = r;
            return http.Response(
              jsonEncode({'success': true, 'txHash': '0xabc'}),
              200,
            );
          }),
          structure: _struct(types: [1], optionCounts: [32]),
        );
        vm.toggleMulti(0, 0);
        vm.toggleMulti(0, 31);

        final expectedAnswers = [(BigInt.one << 31) | BigInt.one];
        final expectedMessage = surveyCommitment(expectedAnswers);

        await vm.castSurvey(identitySeed: 'seed');

        expect(vm.status, SurveyVoteStatus.success);
        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        expect(body['answers'], ['2147483649']);
        expect((body['proof'] as Map)['message'], expectedMessage.toString());
      },
    );
  });

  group('membership + relayer errors (mirrors the sibling modules)', () {
    test('identity not in the group → clear "not registered" error, no relay',
        () async {
      var relayed = false;
      final vm = await _loaded(
        MockClient((r) async {
          relayed = true;
          return http.Response('{}', 200);
        }),
        structure: _struct(types: [0], optionCounts: [3]),
        group: const ['999'], // no '1234567890'
      );
      vm.selectSingle(0, 1);
      await vm.castSurvey(identitySeed: 'seed');
      expect(vm.status, SurveyVoteStatus.error);
      expect(vm.castError, contains("isn't registered"));
      expect(relayed, isFalse, reason: 'must not relay when not a member');
    });

    test('relayer error → error status, no txHash', () async {
      final vm = await _loaded(
        MockClient(
          (r) async => http.Response(
            jsonEncode({'error': 'Survey is not in voting phase'}),
            500,
          ),
        ),
        structure: _struct(types: [0], optionCounts: [3]),
      );
      vm.selectSingle(0, 0);
      await vm.castSurvey(identitySeed: 'seed');
      expect(vm.status, SurveyVoteStatus.error);
      expect(vm.castError, 'Survey is not in voting phase');
      expect(vm.txHash, isNull);
    });
  });

  group('checkRegistration (token pattern — mirrors the sibling modules)', () {
    test('identity in the group → isRegistered true', () async {
      final vm =
          await _loaded(_ok(), structure: _struct(types: [0], optionCounts: [3]));
      await vm.checkRegistration('seed');
      expect(vm.myCommitment, '1234567890');
      expect(vm.isRegistered, isTrue);
      expect(vm.checkingRegistration, isFalse);
    });

    test('identity not in the group → isRegistered false', () async {
      final vm = await _loaded(
        _ok(),
        structure: _struct(types: [0], optionCounts: [3]),
        group: const ['999'],
      );
      await vm.checkRegistration('seed');
      expect(vm.myCommitment, '1234567890');
      expect(vm.isRegistered, isFalse);
    });
  });
}
