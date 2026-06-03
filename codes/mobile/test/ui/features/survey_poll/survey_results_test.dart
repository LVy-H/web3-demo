import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/repositories/survey_repository.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/ui/features/survey_poll/survey_poll_screen.dart';
import 'package:tessera/ui/features/survey_poll/survey_vote_view_model.dart';
import 'package:tessera/ui/widgets/results_bars.dart';

class _FakeSurveyRepo implements SurveyRepository {
  final SurveyStructure structure;
  _FakeSurveyRepo(this.structure);
  @override
  Future<SurveyStructure> fetchSurvey(String address) async => structure;
  @override
  Future<List<String>> fetchGroup(String address) async => const [];
  @override
  Future<List<List<BigInt>>> getSurveyResults(String address) async =>
      structure.results;
}

const _proof = RelayProof(
  merkleTreeDepth: 1,
  merkleTreeRoot: '1',
  nullifier: '2',
  message: '1',
  scope: '3',
  points: ['1', '2', '3', '4', '5', '6', '7', '8'],
);

const _addr = '0x1111111111111111111111111111111111111111';

/// An N-question survey snapshot. Q0 has a STRICT leader in its tally so the
/// "no trophy" assertion proves `highlightLeader: false` (not merely an absent
/// leader).
SurveyStructure _struct(int n, {int state = 2}) => SurveyStructure(
      address: _addr,
      state: state, // Ended: results only, no answer form — pure results view
      questions: [
        for (var q = 0; q < n; q++)
          SurveyQuestion(
            type: q.isEven ? 0 : 1,
            options: ['Q${q}a', 'Q${q}b', 'Q${q}c'],
          ),
      ],
      results: [
        for (var q = 0; q < n; q++)
          // A strict leader on every question (5 > 2 > 1).
          [BigInt.from(5), BigInt.from(2), BigInt.one],
      ],
      owner: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      participantCount: BigInt.from(8),
    );

Widget _app(SurveyStructure structure) {
  return MultiProvider(
    providers: [
      Provider<SurveyRepository>(create: (_) => _FakeSurveyRepo(structure)),
      Provider<ProofService>(create: (_) => const FakeProofService(_proof)),
      Provider<RelayClient>(
        create: (_) => RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200)),
        ),
      ),
    ],
    child: MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => SurveyVoteViewModel(
          repository: _FakeSurveyRepo(structure),
          proofService: const FakeProofService(_proof),
          relayClient: RelayClient(baseUrl: 'http://relayer.test'),
          pollAddress: _addr,
        ),
        child: const SurveyPollScreen(address: _addr),
      ),
    ),
  );
}

void main() {
  testWidgets('renders exactly N ResultsBars for an N-question survey',
      (tester) async {
    await tester.pumpWidget(_app(_struct(3)));
    await tester.pumpAndSettle();

    // One ResultsBars per question.
    expect(find.byType(ResultsBars), findsNWidgets(3));
    expect(find.text('SURVEY RESULTS'), findsOneWidget);
  });

  testWidgets('a 1-question survey renders exactly 1 ResultsBars',
      (tester) async {
    await tester.pumpWidget(_app(_struct(1)));
    await tester.pumpAndSettle();
    expect(find.byType(ResultsBars), findsOneWidget);
  });

  testWidgets(
    'NO per-question trophy — highlightLeader is false even with a strict '
    'leader',
    (tester) async {
      await tester.pumpWidget(_app(_struct(3)));
      await tester.pumpAndSettle();

      // Every question's tally [5,2,1] HAS a strict leader, so a trophy WOULD
      // render if highlightLeader were true. Its absence proves the survey
      // passes highlightLeader: false (a distribution, not an election).
      expect(find.byKey(ResultsBars.winnerKey), findsNothing);
    },
  );
}
