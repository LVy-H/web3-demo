import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:core_relay/server_client.dart';

/// Verifies the Phase-2 server client speaks the EXACT REST contract
/// (`codes/server` routes): method + path + JSON body, the Bearer header on
/// convener routes, response parsing, and the typed [ServerException] (with
/// the server `{code}` + `signature`) on non-2xx.
const base = 'http://server.test';
const id = 'dec_abc';

void main() {
  group('createDecision', () {
    test('POSTs the body to /decisions with the Bearer header', () async {
      late http.Request req;
      final c = ServerClient(
        baseUrl: base,
        token: 'admin-tok',
        client: MockClient((r) async {
          req = r;
          return http.Response(
            jsonEncode({'id': id, 'state': 'draft', 'setupCommitment': 'sc'}),
            201,
          );
        }),
      );
      final body = {
        'title': 'Lunch',
        'options': ['A', 'B'],
        'method': 'single',
      };
      final res = await c.createDecision(body);
      expect(req.method, 'POST');
      expect(req.url.toString(), '$base/decisions');
      expect(req.headers['authorization'], 'Bearer admin-tok');
      expect(req.headers['content-type'], contains('application/json'));
      expect(jsonDecode(req.body), body);
      expect(res['id'], id);
      expect(res['state'], 'draft');
    });

    test('omits the Authorization header when no token is set', () async {
      late http.Request req;
      final c = ServerClient(
        baseUrl: base,
        client: MockClient((r) async {
          req = r;
          return http.Response(jsonEncode({'id': id, 'state': 'draft'}), 201);
        }),
      );
      await c.createDecision(const {'title': 't'});
      expect(req.headers.containsKey('authorization'), isFalse);
    });

    test('throws ServerException carrying the code on a 400', () async {
      final c = ServerClient(
        baseUrl: base,
        token: 't',
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({'error': 'invalid', 'code': 'VALIDATION'}),
            400,
          ),
        ),
      );
      await expectLater(
        c.createDecision(const {}),
        throwsA(
          isA<ServerException>()
              .having((e) => e.code, 'code', 'VALIDATION')
              .having((e) => e.status, 'status', 400),
        ),
      );
    });
  });

  group('lifecycle transitions', () {
    test('open POSTs to /decisions/:id/open', () async {
      late http.Request req;
      final c = ServerClient(
        baseUrl: base,
        token: 't',
        client: MockClient((r) async {
          req = r;
          return http.Response(jsonEncode({'id': id, 'state': 'open'}), 200);
        }),
      );
      final res = await c.openDecision(id);
      expect(req.method, 'POST');
      expect(req.url.toString(), '$base/decisions/$id/open');
      expect(res['state'], 'open');
    });

    test('close / publish / cancel hit their paths', () async {
      final paths = <String>[];
      final c = ServerClient(
        baseUrl: base,
        token: 't',
        client: MockClient((r) async {
          paths.add(r.url.path);
          return http.Response(jsonEncode({'id': id, 'state': 'x'}), 200);
        }),
      );
      await c.closeDecision(id);
      await c.publishDecision(id);
      await c.cancelDecision(id);
      expect(paths, [
        '/decisions/$id/close',
        '/decisions/$id/publish',
        '/decisions/$id/cancel',
      ]);
    });

    test('extend POSTs {closesAt}', () async {
      late http.Request req;
      final c = ServerClient(
        baseUrl: base,
        token: 't',
        client: MockClient((r) async {
          req = r;
          return http.Response(
            jsonEncode({'id': id, 'state': 'open', 'closesAt': 999}),
            200,
          );
        }),
      );
      await c.extendDecision(id, 999);
      expect(req.url.path, '/decisions/$id/extend');
      expect(jsonDecode(req.body), {'closesAt': 999});
    });

    test('ILLEGAL_TRANSITION 409 surfaces as a typed exception', () async {
      final c = ServerClient(
        baseUrl: base,
        token: 't',
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({'error': 'illegal', 'code': 'ILLEGAL_TRANSITION'}),
            409,
          ),
        ),
      );
      await expectLater(
        c.openDecision(id),
        throwsA(
          isA<ServerException>().having(
            (e) => e.code,
            'code',
            'ILLEGAL_TRANSITION',
          ),
        ),
      );
    });
  });

  group('reads', () {
    test('getDecision GETs /decisions/:id (no token needed)', () async {
      late http.Request req;
      final c = ServerClient(
        baseUrl: base,
        client: MockClient((r) async {
          req = r;
          return http.Response(
            jsonEncode({'id': id, 'title': 'T', 'state': 'open'}),
            200,
          );
        }),
      );
      final res = await c.getDecision(id);
      expect(req.method, 'GET');
      expect(req.url.toString(), '$base/decisions/$id');
      expect(res['title'], 'T');
    });

    test('getTurnout GETs the convener turnout route', () async {
      late http.Request req;
      final c = ServerClient(
        baseUrl: base,
        token: 't',
        client: MockClient((r) async {
          req = r;
          return http.Response(jsonEncode({'count': 7}), 200);
        }),
      );
      final res = await c.getTurnout(id);
      expect(req.url.path, '/decisions/$id/turnout');
      expect(req.headers['authorization'], 'Bearer t');
      expect(res['count'], 7);
    });

    test('getBallots builds the query string', () async {
      late http.Request req;
      final c = ServerClient(
        baseUrl: base,
        client: MockClient((r) async {
          req = r;
          return http.Response(
            jsonEncode({'ballots': [], 'leafCount': 0, 'nextCursor': null}),
            200,
          );
        }),
      );
      await c.getBallots(id, after: 3, limit: 50);
      expect(req.url.path, '/ballots');
      expect(req.url.queryParameters['decisionId'], id);
      expect(req.url.queryParameters['after'], '3');
      expect(req.url.queryParameters['limit'], '50');
    });

    test('getResults / getRoot / getAnchor hit their routes', () async {
      final paths = <String>[];
      final c = ServerClient(
        baseUrl: base,
        client: MockClient((r) async {
          paths.add(r.url.path);
          return http.Response(jsonEncode({}), 200);
        }),
      );
      await c.getResults(id);
      await c.getRoot(id);
      await c.getAnchor(id);
      expect(paths, ['/results', '/root', '/anchor']);
    });
  });

  group('castBallot', () {
    test(
      'POSTs {decisionId, payload, idempotencyKey} and parses the receipt',
      () async {
        late http.Request req;
        final c = ServerClient(
          baseUrl: base,
          client: MockClient((r) async {
            req = r;
            return http.Response(
              jsonEncode({
                'receipt': {
                  'ballotHash': 'bh',
                  'logPosition': 0,
                  'runningRoot': 'rr',
                  'serverSig': 'sig',
                },
                'decisionId': id,
              }),
              201,
            );
          }),
        );
        final res = await c.castBallot(
          decisionId: id,
          payload: const {'kind': 'single', 'choice': 1},
          idempotencyKey: 'key123',
        );
        expect(req.method, 'POST');
        expect(req.url.path, '/ballots');
        expect(jsonDecode(req.body), {
          'decisionId': id,
          'payload': {'kind': 'single', 'choice': 1},
          'idempotencyKey': 'key123',
        });
        expect((res['receipt'] as Map)['ballotHash'], 'bh');
      },
    );

    test('DECISION_CLOSED 409 throws with the code + signature', () async {
      final c = ServerClient(
        baseUrl: base,
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'error': 'decision-closed',
              'code': 'DECISION_CLOSED',
              'decisionId': id,
              'signature': 'signed-refusal',
            }),
            409,
          ),
        ),
      );
      await expectLater(
        c.castBallot(
          decisionId: id,
          payload: const {'kind': 'abstain'},
          idempotencyKey: 'k',
        ),
        throwsA(
          isA<ServerException>()
              .having((e) => e.isDecisionClosed, 'isDecisionClosed', isTrue)
              .having((e) => e.signature, 'signature', 'signed-refusal'),
        ),
      );
    });

    test('MAX_PARTICIPANTS 409 sets the typed flag', () async {
      final c = ServerClient(
        baseUrl: base,
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({'error': 'full', 'code': 'MAX_PARTICIPANTS'}),
            409,
          ),
        ),
      );
      await expectLater(
        c.castBallot(
          decisionId: id,
          payload: const {'kind': 'abstain'},
          idempotencyKey: 'k',
        ),
        throwsA(
          isA<ServerException>().having(
            (e) => e.isMaxParticipants,
            'isMaxParticipants',
            isTrue,
          ),
        ),
      );
    });

    test('an identical-retry 200 replay returns the same receipt', () async {
      final c = ServerClient(
        baseUrl: base,
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'receipt': {'ballotHash': 'bh', 'runningRoot': 'rr'},
              'decisionId': id,
            }),
            200,
          ),
        ),
      );
      final res = await c.castBallot(
        decisionId: id,
        payload: const {'kind': 'single', 'choice': 0},
        idempotencyKey: 'k',
      );
      expect((res['receipt'] as Map)['ballotHash'], 'bh');
    });
  });
}
