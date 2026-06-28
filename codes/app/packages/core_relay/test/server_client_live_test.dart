@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:core_relay/server_client.dart';

/// LIVE working-example proof: the ACTUAL [ServerClient] (the client code the
/// Flutter app's server adapters use) drives a REAL running `codes/server`
/// instance end-to-end — no mocks, no `MockClient`.
///
/// This is the honest counterpart to `server_client_test.dart` (which pins the
/// wire contract against a MockClient): here every method is a real HTTP round
/// trip to the Phase-2 bulletin-board server.
///
/// GUARDED so CI never needs a server: the test only runs when the
/// `TESSERA_LIVE_SERVER` env var points at a running server. Start one with:
///
///   cd codes/server && npm install && npm run build
///   DATA_DIR=$(mktemp -d) PORT=3071 node dist/index.js   # prints ADMIN TOKEN
///
/// then run this suite with the server URL + admin token in the environment:
///
///   TESSERA_LIVE_SERVER=http://127.0.0.1:3071 \
///   TESSERA_ADMIN_TOKEN=`<token>` \
///   flutter test --tags live \
///     packages/core_relay/test/server_client_live_test.dart
///
/// The full convener lifecycle is exercised against the live server:
///   createDecision (Bearer admin) → openDecision → castBallot ×3 (2× option 0,
///   1× option 1, distinct idempotency keys; one retry replays the same
///   receipt) → closeDecision → publishDecision → getResults — asserting the
///   tally optionScores are [2, 1], the verdict carried with winner option 0,
///   and getRoot reflects exactly 3 ballots.
void main() {
  final base = Platform.environment['TESSERA_LIVE_SERVER'];
  final adminToken = Platform.environment['TESSERA_ADMIN_TOKEN'];

  if (base == null || base.isEmpty) {
    test('live ServerClient e2e (no live server)', () {
      markTestSkipped(
        'set TESSERA_LIVE_SERVER (and TESSERA_ADMIN_TOKEN) to run against a '
        'real codes/server instance',
      );
    }, skip: true);
    return;
  }

  test(
    'ServerClient drives a real server: create → open → cast×3 → close → '
    'publish → results == optionScores[2,1], carried/winner 0, root 3 ballots',
    () async {
      expect(
        adminToken != null && adminToken.isNotEmpty,
        isTrue,
        reason:
            'TESSERA_ADMIN_TOKEN must be set to the admin token the '
            'server printed on startup',
      );

      final client = ServerClient(baseUrl: base, token: adminToken);
      addTearDown(client.close);

      // ── create (convener, Bearer admin token): single-choice, 2 options ───
      final created = await client.createDecision(<String, dynamic>{
        'title': 'Working-example: lunch venue',
        'options': <String>['Trattoria', 'Sushi bar'],
        'method': 'single',
        'ballotMode': 'open',
        'resultsPolicy': 'live',
        'eligibility': <String, dynamic>{'method': 'open'},
        'rule': <String, dynamic>{
          'threshold': <String, dynamic>{'kind': 'plurality'},
          'tieBreak': 'declare',
        },
        'schedule': <String, dynamic>{},
        'visibility': 'link-only',
        'anchorMode': 'casual',
      });
      final decisionId = created['id'] as String;
      expect(decisionId, isNotEmpty);
      expect(created['state'], 'draft');
      expect(created['setupCommitment'], isA<String>());

      // ── open ──────────────────────────────────────────────────────────────
      final opened = await client.openDecision(decisionId);
      expect(opened['state'], 'open');

      // ── cast ×3 (2× option 0, 1× option 1), distinct idempotency keys ─────
      Future<Map<String, dynamic>> cast(int choice, String key) =>
          client.castBallot(
            decisionId: decisionId,
            payload: <String, dynamic>{'kind': 'single', 'choice': choice},
            idempotencyKey: key,
          );

      final r1 = await cast(0, 'we-key-1');
      final r2 = await cast(0, 'we-key-2');
      final r3 = await cast(1, 'we-key-3');
      for (final r in <Map<String, dynamic>>[r1, r2, r3]) {
        expect(r['decisionId'], decisionId);
        final receipt = r['receipt'] as Map<String, dynamic>;
        expect(receipt['ballotHash'], isA<String>());
        expect(receipt['runningRoot'], isA<String>());
        expect(receipt['serverSig'], isA<String>());
      }
      // Log positions advance 0,1,2 — three distinct appended ballots.
      expect((r1['receipt'] as Map)['logPosition'], 0);
      expect((r2['receipt'] as Map)['logPosition'], 1);
      expect((r3['receipt'] as Map)['logPosition'], 2);

      // ── idempotent retry: same key (we-key-1) + same payload → same receipt
      final retry = await cast(0, 'we-key-1');
      expect(
        (retry['receipt'] as Map)['ballotHash'],
        (r1['receipt'] as Map)['ballotHash'],
        reason: 'identical-retry replays the original receipt (exactly-once)',
      );
      expect(
        (retry['receipt'] as Map)['runningRoot'],
        (r1['receipt'] as Map)['runningRoot'],
      );

      // ── root reflects exactly 3 ballots (retry did NOT add a 4th) ─────────
      final root = await client.getRoot(decisionId);
      expect(root['leafCount'], 3, reason: 'three distinct ballots appended');
      expect(root['head'], isA<String>());
      expect((root['head'] as String).isNotEmpty, isTrue);

      // ── close → publish ───────────────────────────────────────────────────
      expect((await client.closeDecision(decisionId))['state'], 'closed');
      expect((await client.publishDecision(decisionId))['state'], 'published');

      // ── results: optionScores [2, 1], verdict carried, winner option 0 ────
      final results = await client.getResults(decisionId);
      final tally = results['tally'] as Map<String, dynamic>;
      final verdict = results['verdict'] as Map<String, dynamic>;
      final scores = (tally['optionScores'] as List).cast<int>();

      // The asserted working-example line.
      // ignore: avoid_print
      print(
        'LIVE RESULT: optionScores=$scores totalCast=${tally['totalCast']} '
        'abstain=${tally['abstain']} verdict=${verdict['outcome']} '
        'winner=${verdict['winner']} root.leafCount=${root['leafCount']}',
      );

      expect(scores, <int>[2, 1], reason: '2 ballots for option 0, 1 for 1');
      expect(tally['totalCast'], 3);
      expect(tally['abstain'], 0);
      expect(verdict['outcome'], 'carried');
      expect(verdict['winner'], 0, reason: 'option 0 is the plurality winner');
    },
  );
}
