import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tessera/data/models/poll_info.dart';
import 'package:tessera/data/models/poll_snapshot.dart';
import 'package:tessera/data/models/poll_summary.dart';
import 'package:tessera/data/models/relay_proof.dart';
import 'package:tessera/data/repositories/approval_repository.dart';
import 'package:tessera/data/repositories/poll_repository.dart';
import 'package:tessera/data/repositories/quadratic_repository.dart';
import 'package:tessera/data/repositories/ranked_repository.dart';
import 'package:tessera/data/repositories/survey_repository.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:tessera/data/services/proof_service.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/router.dart';
import 'package:tessera/ui/widgets/results_bars.dart';

// ── Fakes for the subtree `buildPollDetail` touches ──────────────────────────

PollSnapshot _snap(String addr) => PollSnapshot(
  address: addr,
  state: 1, // Voting — so both screens render their results + ballot area
  options: const ['A', 'B', 'C'],
  results: [BigInt.from(2), BigInt.one, BigInt.zero],
  owner: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
  participantCount: BigInt.from(3),
);

class _FakePollRepo implements PollRepository {
  @override
  Future<PollSnapshot> fetchPoll(String address) async => _snap(address);
  @override
  Future<List<String>> fetchGroup(String address) async => const [];
  @override
  Future<List<PollInfo>> fetchPolls() => throw UnimplementedError();
  @override
  Future<PollSummary> fetchSummary(String address) =>
      throw UnimplementedError();
}

class _FakeApprovalRepo implements ApprovalRepository {
  @override
  Future<PollSnapshot> fetchPoll(String address) async => _snap(address);
  @override
  Future<List<String>> fetchGroup(String address) async => const [];
}

class _FakeRankedRepo implements RankedRepository {
  @override
  Future<PollSnapshot> fetchPoll(String address) async => _snap(address);
  @override
  Future<List<String>> fetchGroup(String address) async => const [];
}

class _FakeQuadraticRepo implements QuadraticRepository {
  @override
  Future<PollSnapshot> fetchPoll(String address) async => _snap(address);
  @override
  Future<List<String>> fetchGroup(String address) async => const [];
}

// A 2-question survey (Q0 single over 3, Q1 multi over 2) with a per-question
// tally, so the survey screen renders its results + (web-gated) answer form.
SurveyStructure _surveyStruct(String addr) => SurveyStructure(
      address: addr,
      state: 1, // Voting
      questions: const [
        SurveyQuestion(type: 0, options: ['A', 'B', 'C']),
        SurveyQuestion(type: 1, options: ['X', 'Y']),
      ],
      results: [
        [BigInt.from(2), BigInt.one, BigInt.zero],
        [BigInt.from(3), BigInt.from(1)],
      ],
      owner: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      participantCount: BigInt.from(3),
    );

class _FakeSurveyRepo implements SurveyRepository {
  @override
  Future<SurveyStructure> fetchSurvey(String address) async =>
      _surveyStruct(address);
  @override
  Future<List<String>> fetchGroup(String address) async => const [];
  @override
  Future<List<List<BigInt>>> getSurveyResults(String address) async =>
      _surveyStruct(address).results;
}

const _addr = '0x1111111111111111111111111111111111111111';

const _proof = RelayProof(
  merkleTreeDepth: 1,
  merkleTreeRoot: '1',
  nullifier: '2',
  message: '1',
  scope: '3',
  points: ['1', '2', '3', '4', '5', '6', '7', '8'],
);

/// A minimal router whose ONLY route is the REAL `buildPollDetail` builder, so
/// the test exercises the actual `?module=` dispatch (not a hand-pumped screen).
/// Wrapped in only the providers that the poll-detail subtree reads.
Widget _app(String initialLocation) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [GoRoute(path: '/poll/:address', builder: buildPollDetail)],
  );
  return MultiProvider(
    providers: [
      Provider<PollRepository>(create: (_) => _FakePollRepo()),
      Provider<ApprovalRepository>(create: (_) => _FakeApprovalRepo()),
      Provider<RankedRepository>(create: (_) => _FakeRankedRepo()),
      Provider<QuadraticRepository>(create: (_) => _FakeQuadraticRepo()),
      Provider<SurveyRepository>(create: (_) => _FakeSurveyRepo()),
      Provider<ProofService>(create: (_) => const FakeProofService(_proof)),
      Provider<RelayClient>(
        create: (_) => RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((r) async => http.Response('{}', 200)),
        ),
      ),
      // canSign=false → the anon screen hides its organize-live entry. (This
      // test only exercises the anon/approval branches, so BlindRepository is
      // intentionally not provided — a blind-vote route would need it.)
      Provider<ChainWriter>(
        create: (_) =>
            ChainWriter(rpcUrl: 'http://127.0.0.1:1', chainId: 31337),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets(
    '?module=approval-vote dispatches to the APPROVAL screen, not the anon one',
    (tester) async {
      await tester.pumpWidget(_app('/poll/$_addr?module=approval-vote'));
      await tester.pumpAndSettle();

      // Approval chrome present…
      expect(find.text('ZK · APPROVAL'), findsOneWidget);
      expect(find.text('APPROVALS'), findsOneWidget);
      // …and the anon screen's chrome is ABSENT (the bug this guards: falling
      // through to the anon screen would cast a single-index vote, not a bitmask).
      expect(find.text('ZK · ANON'), findsNothing);
      expect(find.text('LIVE RESULTS'), findsNothing);
    },
  );

  testWidgets(
    '?module=ranked-vote dispatches to the RANKED screen, not the anon one',
    (tester) async {
      await tester.pumpWidget(_app('/poll/$_addr?module=ranked-vote'));
      await tester.pumpAndSettle();

      // Ranked chrome present…
      expect(find.text('ZK · RANKED'), findsOneWidget);
      expect(find.text('FIRST CHOICES'), findsOneWidget);
      // …and the anon screen's chrome is ABSENT (the bug this guards: falling
      // through to the anon screen would cast a single-index vote, not a packed
      // ranking ballot).
      expect(find.text('ZK · ANON'), findsNothing);
      expect(find.text('LIVE RESULTS'), findsNothing);
    },
  );

  testWidgets(
    '?module=quadratic-vote dispatches to the QUADRATIC screen, not the anon one',
    (tester) async {
      await tester.pumpWidget(_app('/poll/$_addr?module=quadratic-vote'));
      await tester.pumpAndSettle();

      // Quadratic chrome present… (the results card title is always rendered;
      // the allocation FORM is web-only — gated on proofServiceAvailable, false
      // under `flutter test` — so this asserts the always-present chrome, like
      // the ranked dispatch guard above.)
      expect(find.text('ZK · QUADRATIC'), findsOneWidget);
      expect(find.text('VOTE TOTALS'), findsOneWidget);
      // QV results are AUTHORITATIVE: getResults() IS the outcome, so the screen
      // DOES crown the leader (`highlightLeader: true`). The snapshot is
      // results=[2,1,0] → option 0 is the strict leader → the trophy marker is
      // in the tree. (This is the OPPOSITE of ranked, which passes
      // `highlightLeader: false` and renders no marker.)
      expect(find.byKey(ResultsBars.winnerKey), findsOneWidget);
      // …and it deliberately does NOT carry over ranked's "not the final winner"
      // caption — that warning is wrong for the authoritative QV tally.
      expect(find.textContaining('not the final winner'), findsNothing);
      // …and the anon screen's chrome is ABSENT (the bug this guards: falling
      // through to the anon screen would cast a single-index vote, not a packed
      // allocation ballot).
      expect(find.text('ZK · ANON'), findsNothing);
      expect(find.text('LIVE RESULTS'), findsNothing);
    },
  );

  testWidgets(
    '?module=survey-vote dispatches to the SURVEY screen, not the anon one',
    (tester) async {
      await tester.pumpWidget(_app('/poll/$_addr?module=survey-vote'));
      await tester.pumpAndSettle();

      // Survey chrome present… (the results section is always rendered; the
      // answer FORM is web-only — gated on proofServiceAvailable, false under
      // `flutter test` — so this asserts the always-present chrome.)
      expect(find.text('ZK · SURVEY'), findsOneWidget);
      expect(find.text('SURVEY RESULTS'), findsOneWidget);
      // N ResultsBars — one per question — for an N-question survey (here N=2).
      expect(find.byType(ResultsBars), findsNWidgets(2));
      // A survey is a response DISTRIBUTION, not an election — so NO per-question
      // trophy (`highlightLeader: false`). This is the OPPOSITE of QV, which
      // crowns the leader. (Q0 tally [2,1,0] HAS a strict leader, so a missing
      // marker proves highlightLeader is off, not just an absent leader.)
      expect(find.byKey(ResultsBars.winnerKey), findsNothing);
      // …and the anon screen's chrome is ABSENT (the bug this guards: falling
      // through to the anon screen would cast a single-index vote, not the full
      // answer vector).
      expect(find.text('ZK · ANON'), findsNothing);
      expect(find.text('LIVE RESULTS'), findsNothing);
    },
  );

  testWidgets('?module=anon-vote still dispatches to the ANON screen', (
    tester,
  ) async {
    await tester.pumpWidget(_app('/poll/$_addr?module=anon-vote'));
    await tester.pumpAndSettle();

    expect(find.text('ZK · ANON'), findsOneWidget);
    expect(find.text('LIVE RESULTS'), findsOneWidget);
    expect(find.text('ZK · APPROVAL'), findsNothing);
    expect(find.text('APPROVALS'), findsNothing);
  });

  testWidgets('no module param falls back to the ANON screen', (tester) async {
    await tester.pumpWidget(_app('/poll/$_addr'));
    await tester.pumpAndSettle();

    expect(find.text('ZK · ANON'), findsOneWidget);
    expect(find.text('ZK · APPROVAL'), findsNothing);
  });
}
