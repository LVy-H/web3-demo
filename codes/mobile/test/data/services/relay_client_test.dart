import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkvote_mobile/data/models/relay_proof.dart';
import 'package:zkvote_mobile/data/services/relay_client.dart';

/// Verifies the Dart relayer client speaks the EXACT cross-client HTTP contract
/// (spec §2.5) the relayer (codes/relayer/src) and web client (liveRelay.ts /
/// useRelay.ts) use: paths, JSON body keys, and response parsing.
const base = 'http://relayer.test';
const pollId = '0x1111111111111111111111111111111111111111';

const _proof = RelayProof(
  merkleTreeDepth: 10,
  merkleTreeRoot: '111',
  nullifier: '222',
  message: '1',
  scope: '333',
  points: ['1', '2', '3', '4', '5', '6', '7', '8'],
);

void main() {
  group('issueOrgKey', () {
    test('POSTs {pollId, orgPubKey} to /api/relay/tickets/issue', () async {
      late http.Request req;
      final c = RelayClient(
        baseUrl: base,
        client: MockClient((r) async {
          req = r;
          return http.Response(jsonEncode({'success': true}), 200);
        }),
      );
      await c.issueOrgKey(pollId, 'ab' * 32);
      expect(req.method, 'POST');
      expect(req.url.toString(), '$base/api/relay/tickets/issue');
      expect(req.headers['content-type'], contains('application/json'));
      expect(jsonDecode(req.body), {'pollId': pollId, 'orgPubKey': 'ab' * 32});
    });

    test('throws the server error message on non-2xx', () async {
      final c = RelayClient(
        baseUrl: base,
        client: MockClient(
          (r) async => http.Response(jsonEncode({'error': 'Invalid pollId'}), 400),
        ),
      );
      expect(
        () => c.issueOrgKey(pollId, 'x'),
        throwsA(predicate((e) => '$e'.contains('Invalid pollId'))),
      );
    });
  });

  group('postPending', () {
    test('POSTs the 4-key body and returns ok/status', () async {
      late http.Request req;
      final c = RelayClient(
        baseUrl: base,
        client: MockClient((r) async {
          req = r;
          return http.Response(
            jsonEncode({'success': true, 'status': 'pending', 'confirmationCode': '4861'}),
            200,
          );
        }),
      );
      final res = await c.postPending(pollId, 'wire', '12345', '4861');
      expect(req.url.path, '/api/relay/tickets/pending');
      expect(jsonDecode(req.body), {
        'pollId': pollId,
        'ticket': 'wire',
        'ephemeralIdentityCommitment': '12345',
        'confirmationCode': '4861',
      });
      expect(res.ok, isTrue);
      expect(res.status, 200);
    });

    test('surfaces error + status on 409 without throwing', () async {
      final c = RelayClient(
        baseUrl: base,
        client: MockClient(
          (r) async => http.Response(jsonEncode({'error': 'Ticket already redeemed'}), 409),
        ),
      );
      final res = await c.postPending(pollId, 'wire', '1', '0001');
      expect(res.ok, isFalse);
      expect(res.status, 409);
      expect(res.error, 'Ticket already redeemed');
    });
  });

  group('fetchQueue', () {
    test('GETs /queue?pollId=… and parses voters', () async {
      late http.Request req;
      final c = RelayClient(
        baseUrl: base,
        client: MockClient((r) async {
          req = r;
          return http.Response(
            jsonEncode({
              'pollId': pollId,
              'voters': [
                {
                  'ticketNonce': 'aabbccddeeff0011',
                  'ticket': 'wire',
                  'ephemeralIdentityCommitment': '12345',
                  'confirmationCode': '4861',
                  'status': 'pending',
                  'createdAt': 1700000000,
                }
              ],
            }),
            200,
          );
        }),
      );
      final voters = await c.fetchQueue(pollId);
      expect(req.method, 'GET');
      expect(req.url.path, '/api/relay/tickets/queue');
      expect(req.url.queryParameters['pollId'], pollId);
      expect(voters, hasLength(1));
      expect(voters.first.confirmationCode, '4861');
      expect(voters.first.status, 'pending');
      expect(voters.first.createdAt, 1700000000);
    });

    test('throws on non-2xx', () async {
      final c = RelayClient(
        baseUrl: base,
        client: MockClient((r) async => http.Response('nope', 500)),
      );
      expect(() => c.fetchQueue(pollId), throwsA(isA<RelayException>()));
    });
  });

  group('relayVote', () {
    test('POSTs {pollAddress, vote, proof} with the snarkjs field shape', () async {
      late http.Request req;
      final c = RelayClient(
        baseUrl: base,
        client: MockClient((r) async {
          req = r;
          return http.Response(jsonEncode({'success': true, 'txHash': '0xabc'}), 200);
        }),
      );
      final res = await c.relayVote(pollId, 2, _proof);
      expect(req.url.path, '/api/relay/vote');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['pollAddress'], pollId);
      expect(body['vote'], 2);
      final p = body['proof'] as Map<String, dynamic>;
      expect(p['merkleTreeDepth'], 10); // number, not string
      expect(p['merkleTreeRoot'], '111'); // decimal string
      expect(p['points'], ['1', '2', '3', '4', '5', '6', '7', '8']);
      expect(res.success, isTrue);
      expect(res.txHash, '0xabc');
    });

    test('returns success:false + error on non-2xx (no throw)', () async {
      final c = RelayClient(
        baseUrl: base,
        client: MockClient(
          (r) async => http.Response(jsonEncode({'error': 'Poll is not in voting phase'}), 500),
        ),
      );
      final res = await c.relayVote(pollId, 0, _proof);
      expect(res.success, isFalse);
      expect(res.error, 'Poll is not in voting phase');
    });
  });

  group('fetchStatus', () {
    test('parses {relayer, balance}', () async {
      final c = RelayClient(
        baseUrl: base,
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({'relayer': '0xdead', 'balance': '1.5', 'rateLimitPerMinute': 60}),
            200,
          ),
        ),
      );
      final s = await c.fetchStatus();
      expect(s, isNotNull);
      expect(s!.relayer, '0xdead');
      expect(s.balance, '1.5');
    });

    test('returns null on error', () async {
      final c = RelayClient(
        baseUrl: base,
        client: MockClient((r) async => http.Response('err', 500)),
      );
      expect(await c.fetchStatus(), isNull);
    });
  });
}
