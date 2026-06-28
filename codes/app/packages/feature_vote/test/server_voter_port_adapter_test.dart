import 'dart:convert';

import 'package:core_crypto/crypto/idempotency_key.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/policy.dart';
import 'package:core_domain/journeys/voter_journey.dart';
import 'package:core_domain/models/poll_snapshot.dart';
import 'package:core_relay/server_client.dart';
import 'package:core_storage/identity_store.dart';
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The server-backed voter adapter is the open-ballot VOTE path: it reads the
/// decision snapshot, maps the typed BallotSpec to the server payload union,
/// derives a stable per-(voter, decision) idempotency key, POSTs /ballots and
/// maps the server receipt to a VoterReceipt. Open ballots carry NO ZK proof.
const base = 'http://server.test';
const decId = 'dec1';
const seed = '0xseed';

ServerVoterPortAdapter _adapter(
  MockClient mock, {
  VoterModule module = VoterModule.anon,
  IdentityStore? store,
}) => ServerVoterPortAdapter(
  client: ServerClient(baseUrl: base, client: mock),
  identityStore: store ?? InMemoryIdentityStore(seed),
  decisionId: decId,
  module: module,
);

void main() {
  group('fetchSnapshot', () {
    test(
      'maps state strings to the phase int (draft→0, open→1, closed→2)',
      () async {
        Future<int> phaseFor(String state) async {
          final adapter = _adapter(
            MockClient(
              (r) async => http.Response(
                jsonEncode({
                  'id': decId,
                  'title': 'T',
                  'options': ['A', 'B'],
                  'method': 'single',
                  'state': state,
                  'turnout': 3,
                  'resultsPolicy': 'sealed',
                }),
                200,
              ),
            ),
          );
          final view = await adapter.fetchSnapshot();
          return view.phase;
        }

        expect(await phaseFor('draft'), 0);
        expect(await phaseFor('open'), 1);
        expect(await phaseFor('closed'), 2);
        expect(await phaseFor('published'), 2);
      },
    );

    test('resultsPolicy live → livePublic, else sealedUntilClose', () async {
      final adapter = _adapter(
        MockClient(
          (r) async => http.Response(
            jsonEncode({
              'id': decId,
              'options': ['A', 'B'],
              'method': 'single',
              'state': 'open',
              'resultsPolicy': 'live',
            }),
            200,
          ),
        ),
      );
      final view = await adapter.fetchSnapshot();
      expect(view.resultsPolicy, ResultsPolicy.livePublic);
      expect(view.optionCount, 2);
    });
  });

  group('open-mode gates', () {
    test('checkEligibility is always true (open mode)', () async {
      final adapter = _adapter(
        MockClient((r) async => http.Response('{}', 200)),
      );
      expect(await adapter.checkEligibility(_view()), isTrue);
    });

    test(
      'generateProof returns the placeholder without any network call',
      () async {
        var called = false;
        final adapter = _adapter(
          MockClient((r) async {
            called = true;
            return http.Response('{}', 200);
          }),
        );
        final proof = await adapter.generateProof(
          const SingleChoice(0),
          _view(),
          CancellationToken(),
        );
        expect(called, isFalse, reason: 'open ballots carry no proof');
        expect(proof, same(openBallotPlaceholderProof));
      },
    );
  });

  group('relayBallot payload mapping', () {
    Future<Map<String, dynamic>> castBodyFor(
      BallotSpec spec, {
      VoterModule module = VoterModule.anon,
    }) async {
      late http.Request req;
      final adapter = _adapter(
        MockClient((r) async {
          req = r;
          return http.Response(
            jsonEncode({
              'receipt': {'ballotHash': 'bh', 'runningRoot': 'rr'},
              'decisionId': decId,
            }),
            201,
          );
        }),
        module: module,
      );
      await adapter.relayBallot(
        spec,
        openBallotPlaceholderProof,
        _view(module: module),
        CancellationToken(),
      );
      return jsonDecode(req.body) as Map<String, dynamic>;
    }

    test('single → {kind:single, choice}', () async {
      final body = await castBodyFor(const SingleChoice(1));
      expect(body['decisionId'], decId);
      expect(body['payload'], {'kind': 'single', 'choice': 1});
    });

    test('approval bitmask → {kind:approval, choices:[indices]}', () async {
      // 0b101 → options 0 and 2 approved.
      final body = await castBodyFor(
        Approval(BigInt.from(5)),
        module: VoterModule.approval,
      );
      expect(body['payload'], {
        'kind': 'approval',
        'choices': [0, 2],
      });
    });

    test('ranked → {kind:ranked, ranking}', () async {
      final body = await castBodyFor(
        Ranked([2, 0, 1]),
        module: VoterModule.ranked,
      );
      expect(body['payload'], {
        'kind': 'ranked',
        'ranking': [2, 0, 1],
      });
    });

    test('quadratic → {kind:quadratic, votes}', () async {
      final body = await castBodyFor(
        Quadratic([3, 0, 4]),
        module: VoterModule.quadratic,
      );
      expect(body['payload'], {
        'kind': 'quadratic',
        'votes': [3, 0, 4],
      });
    });

    test(
      'survey answer words → {kind:survey, choices:[selected indices]}',
      () async {
        final body = await castBodyFor(
          Survey([BigInt.one, BigInt.zero, BigInt.from(2)]),
          module: VoterModule.survey,
        );
        expect(body['payload'], {
          'kind': 'survey',
          'choices': [0, 2],
        });
      },
    );

    test('idempotencyKey is the stable per-(voter, decision) hash', () async {
      late http.Request req;
      final adapter = _adapter(
        MockClient((r) async {
          req = r;
          return http.Response(
            jsonEncode({
              'receipt': {'ballotHash': 'bh', 'runningRoot': 'rr'},
            }),
            201,
          );
        }),
      );
      await adapter.relayBallot(
        const SingleChoice(0),
        openBallotPlaceholderProof,
        _view(),
        CancellationToken(),
      );
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(
        body['idempotencyKey'],
        ballotIdempotencyKey(identitySeed: seed, decisionId: decId),
      );
    });
  });

  group('relayBallot receipt + errors', () {
    test(
      'maps the server receipt → VoterReceipt (nullifier=hash, tx=root)',
      () async {
        final adapter = _adapter(
          MockClient(
            (r) async => http.Response(
              jsonEncode({
                'receipt': {
                  'ballotHash': 'BH',
                  'logPosition': 0,
                  'runningRoot': 'RR',
                  'serverSig': 'sig',
                },
                'decisionId': decId,
              }),
              201,
            ),
          ),
        );
        final receipt = await adapter.relayBallot(
          const SingleChoice(0),
          openBallotPlaceholderProof,
          _view(),
          CancellationToken(),
        );
        expect(receipt.nullifier, 'BH'); // ballotHash
        expect(receipt.txHash, 'RR'); // runningRoot
      },
    );

    test('a DECISION_CLOSED 409 throws a closed-voting error', () async {
      final adapter = _adapter(
        MockClient(
          (r) async => http.Response(
            jsonEncode({
              'error': 'decision-closed',
              'code': 'DECISION_CLOSED',
              'signature': 'sig',
            }),
            409,
          ),
        ),
      );
      await expectLater(
        adapter.relayBallot(
          const SingleChoice(0),
          openBallotPlaceholderProof,
          _view(),
          CancellationToken(),
        ),
        throwsA(predicate((e) => '$e'.contains('closed'))),
      );
    });
  });
}

/// A trivial view for the adapter's `view` argument (the adapter never reads
/// its fields when casting — the cast carries only the payload).
VoterPollView _view({VoterModule module = VoterModule.anon}) => VoterPollView(
  snapshot: PollSnapshot(
    address: decId,
    state: 1,
    options: const ['A', 'B'],
    results: const [],
    owner: '',
    participantCount: BigInt.zero,
  ),
  module: module,
);
