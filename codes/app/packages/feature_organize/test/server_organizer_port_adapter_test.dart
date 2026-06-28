import 'dart:convert';

import 'package:core_domain/journeys/organizer_journey.dart';
import 'package:core_domain/journeys/policy.dart';
import 'package:core_relay/server_client.dart';
import 'package:core_storage/created_polls_store.dart';
import 'package:feature_organize/feature_organize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The server-backed organizer adapter is the open-ballot ORGANIZE path: it
/// maps the journey's deploy/start/end/results/turnout/loadCreatedPolls onto
/// the Phase-2 REST routes. These tests drive it at the HTTP boundary with a
/// MockClient, asserting the method + path + body and the response mapping.
const base = 'http://server.test';

ServerClient _client(MockClient mock, {String? token}) =>
    ServerClient(baseUrl: base, token: token, client: mock);

void main() {
  group('deployPoll', () {
    test(
      'POSTs the open-ballot create body, then opens, and records the id',
      () async {
        final requests = <http.Request>[];
        final created = InMemoryCreatedPollsStore();
        final adapter = ServerOrganizerPortAdapter(
          client: _client(
            MockClient((r) async {
              requests.add(r);
              if (r.url.path == '/decisions') {
                return http.Response(
                  jsonEncode({'id': 'dec1', 'state': 'draft'}),
                  201,
                );
              }
              // /decisions/dec1/open
              return http.Response(
                jsonEncode({'id': 'dec1', 'state': 'open'}),
                200,
              );
            }),
            token: 'admin',
          ),
          createdPolls: created,
        );

        final id = await adapter.deployPoll(
          const OrganizerPollSpec(
            module: OrganizerModule.anonVote,
            title: 'Lunch?',
            options: ['Pizza', 'Sushi'],
          ),
        );

        expect(id, 'dec1');
        // First request: create with the mapped open-ballot body.
        final createReq = requests.first;
        expect(createReq.method, 'POST');
        expect(createReq.url.path, '/decisions');
        expect(createReq.headers['authorization'], 'Bearer admin');
        final body = jsonDecode(createReq.body) as Map<String, dynamic>;
        expect(body['title'], 'Lunch?');
        expect(body['options'], ['Pizza', 'Sushi']);
        expect(body['method'], 'single'); // anonVote → 'single'
        expect(body['ballotMode'], 'open');
        expect(body['resultsPolicy'], 'sealed'); // default sealedUntilClose
        expect(body['eligibility'], {'method': 'open'});
        expect(body['visibility'], 'link-only'); // default unlisted
        expect(body['anchorMode'], 'casual');
        // Second request: auto-open so the create flow lands on a live poll.
        expect(requests[1].url.path, '/decisions/dec1/open');
        // The id is recorded for the dashboard.
        expect(await created.all(), contains('dec1'));
      },
    );

    test('maps every open-ballot module to its server method', () async {
      for (final (module, method) in const [
        (OrganizerModule.anonVote, 'single'),
        (OrganizerModule.approvalVote, 'approval'),
        (OrganizerModule.rankedVote, 'ranked'),
        (OrganizerModule.quadraticVote, 'quadratic'),
        (OrganizerModule.surveyVote, 'survey'),
      ]) {
        expect(serverMethodFor(module), method);
      }
      expect(serverMethodFor(OrganizerModule.blindVote), isNull);
    });

    test('live-public + listed map to live + listed', () async {
      late http.Request createReq;
      final adapter = ServerOrganizerPortAdapter(
        client: _client(
          MockClient((r) async {
            if (r.url.path == '/decisions') createReq = r;
            return http.Response(
              jsonEncode({
                'id': 'd',
                'state': r.url.path.endsWith('open') ? 'open' : 'draft',
              }),
              r.url.path == '/decisions' ? 201 : 200,
            );
          }),
          token: 'admin',
        ),
        createdPolls: InMemoryCreatedPollsStore(),
      );
      await adapter.deployPoll(
        const OrganizerPollSpec(
          title: 'T',
          options: ['A', 'B'],
          visibility: PollVisibility.listed,
          resultsPolicy: ResultsPolicy.livePublic,
        ),
      );
      final body = jsonDecode(createReq.body) as Map<String, dynamic>;
      expect(body['resultsPolicy'], 'live');
      expect(body['visibility'], 'listed');
    });

    test('blind module is rejected as a Phase-3 capability', () async {
      final adapter = ServerOrganizerPortAdapter(
        client: _client(MockClient((r) async => http.Response('{}', 200))),
        createdPolls: InMemoryCreatedPollsStore(),
      );
      await expectLater(
        adapter.deployPoll(
          const OrganizerPollSpec(
            module: OrganizerModule.blindVote,
            title: 'T',
            options: ['A', 'B'],
          ),
        ),
        throwsA(anything),
      );
    });

    test('a 403 create surfaces "paste the admin token" copy', () async {
      final adapter = ServerOrganizerPortAdapter(
        client: _client(
          MockClient(
            (r) async => http.Response(
              jsonEncode({'error': 'forbidden', 'code': 'FORBIDDEN'}),
              403,
            ),
          ),
        ),
        createdPolls: InMemoryCreatedPollsStore(),
      );
      await expectLater(
        adapter.deployPoll(
          const OrganizerPollSpec(title: 'T', options: ['A', 'B']),
        ),
        throwsA(predicate((e) => '$e'.contains('admin token'))),
      );
    });
  });

  group('phase actions', () {
    test('startVoting POSTs /open', () async {
      late http.Request req;
      final adapter = ServerOrganizerPortAdapter(
        client: _client(
          MockClient((r) async {
            req = r;
            return http.Response(jsonEncode({'state': 'open'}), 200);
          }),
          token: 't',
        ),
        createdPolls: InMemoryCreatedPollsStore(),
      );
      await adapter.startVoting('dec1');
      expect(req.url.path, '/decisions/dec1/open');
    });

    test('endVoting POSTs /close', () async {
      late http.Request req;
      final adapter = ServerOrganizerPortAdapter(
        client: _client(
          MockClient((r) async {
            req = r;
            return http.Response(jsonEncode({'state': 'closed'}), 200);
          }),
          token: 't',
        ),
        createdPolls: InMemoryCreatedPollsStore(),
      );
      await adapter.endVoting('dec1');
      expect(req.url.path, '/decisions/dec1/close');
    });

    test('startVoting swallows an ILLEGAL_TRANSITION (already open)', () async {
      final adapter = ServerOrganizerPortAdapter(
        client: _client(
          MockClient(
            (r) async => http.Response(
              jsonEncode({'error': 'illegal', 'code': 'ILLEGAL_TRANSITION'}),
              409,
            ),
          ),
          token: 't',
        ),
        createdPolls: InMemoryCreatedPollsStore(),
      );
      // Does not throw.
      await adapter.startVoting('dec1');
    });

    test('finalize throws a Phase-3 error', () async {
      final adapter = ServerOrganizerPortAdapter(
        client: _client(MockClient((r) async => http.Response('{}', 200))),
        createdPolls: InMemoryCreatedPollsStore(),
      );
      await expectLater(adapter.finalize('dec1'), throwsA(anything));
    });
  });

  group('reads', () {
    test('fetchTurnout reads the convener turnout count', () async {
      final adapter = ServerOrganizerPortAdapter(
        client: _client(
          MockClient((r) async {
            expect(r.url.path, '/decisions/dec1/turnout');
            return http.Response(jsonEncode({'count': 12}), 200);
          }),
          token: 't',
        ),
        createdPolls: InMemoryCreatedPollsStore(),
      );
      expect(await adapter.fetchTurnout('dec1'), 12);
    });

    test(
      'fetchTurnout falls back to the public view turnout on a 403',
      () async {
        final adapter = ServerOrganizerPortAdapter(
          client: _client(
            MockClient((r) async {
              if (r.url.path.endsWith('/turnout')) {
                return http.Response(
                  jsonEncode({'error': 'forbidden', 'code': 'FORBIDDEN'}),
                  403,
                );
              }
              return http.Response(jsonEncode({'turnout': 4}), 200);
            }),
          ),
          createdPolls: InMemoryCreatedPollsStore(),
        );
        expect(await adapter.fetchTurnout('dec1'), 4);
      },
    );

    test(
      'fetchResults maps optionScores to labelled OrganizerResults',
      () async {
        final adapter = ServerOrganizerPortAdapter(
          client: _client(
            MockClient((r) async {
              if (r.url.path == '/results') {
                return http.Response(
                  jsonEncode({
                    'tally': {
                      'optionScores': [3, 1],
                      'abstain': 2,
                      'totalCast': 6,
                    },
                    'verdict': {'outcome': 'carried', 'winner': 0},
                    'authoritative': false,
                  }),
                  200,
                );
              }
              // /decisions/dec1 — supplies option labels.
              return http.Response(
                jsonEncode({
                  'id': 'dec1',
                  'title': 'T',
                  'options': ['Pizza', 'Sushi'],
                  'method': 'single',
                  'state': 'closed',
                }),
                200,
              );
            }),
          ),
          createdPolls: InMemoryCreatedPollsStore(),
        );
        final results = await adapter.fetchResults('dec1');
        expect(results.tallies['Pizza'], 3);
        expect(results.tallies['Sushi'], 1);
        expect(results.tallies['Abstain'], 2);
      },
    );

    test(
      'loadCreatedPolls maps each id to a RunPollSnapshot, skipping 404s',
      () async {
        final created = InMemoryCreatedPollsStore(['live1', 'gone2']);
        final adapter = ServerOrganizerPortAdapter(
          client: _client(
            MockClient((r) async {
              if (r.url.path == '/decisions/live1') {
                return http.Response(
                  jsonEncode({
                    'id': 'live1',
                    'title': 'Live one',
                    'options': ['A', 'B'],
                    'method': 'approval',
                    'state': 'open',
                    'turnout': 5,
                  }),
                  200,
                );
              }
              // gone2 → 404, must be skipped not thrown.
              return http.Response(
                jsonEncode({'error': 'not-found', 'code': 'NOT_FOUND'}),
                404,
              );
            }),
          ),
          createdPolls: created,
        );
        final snapshots = await adapter.loadCreatedPolls();
        expect(snapshots.length, 1);
        final s = snapshots.single;
        expect(s.pollAddress, 'live1');
        expect(s.title, 'Live one');
        expect(s.module, OrganizerModule.approvalVote);
        expect(s.phase, 1); // open → 1
        expect(s.turnout, 5);
      },
    );

    test('loadPoll returns null for an unknown decision', () async {
      final adapter = ServerOrganizerPortAdapter(
        client: _client(
          MockClient(
            (r) async => http.Response(
              jsonEncode({'error': 'not-found', 'code': 'NOT_FOUND'}),
              404,
            ),
          ),
        ),
        createdPolls: InMemoryCreatedPollsStore(),
      );
      expect(await adapter.loadPoll('nope'), isNull);
    });
  });
}
