// RelayLiveVoterPort — the live-voter effect boundary over the relayer +
// chain reads. Pure Dart (runs under `dart test` with the grammar suite):
// the relayer is an http MockClient, chain reads are closures, the proof
// service is core_crypto's FakeProofService.
import 'dart:convert';

import 'package:core_crypto/crypto/confirmation_code.dart';
import 'package:core_crypto/crypto/ticket.dart';
import 'package:core_crypto/proof/proof_service.dart';
import 'package:core_domain/journeys/live_journeys.dart';
import 'package:core_domain/models/relay_proof.dart';
import 'package:core_relay/relay_client.dart';
import 'package:feature_join/live.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const poll = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const otherPoll = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// 32-byte ed25519 org seed (any fixed bytes work for a self-signed ticket).
final orgSeed = List<int>.generate(32, (i) => i + 1);

const fakeProof = RelayProof(
  merkleTreeDepth: 1,
  merkleTreeRoot: '1',
  nullifier: '2',
  message: '0',
  scope: poll,
  points: ['0', '0', '0', '0', '0', '0', '0', '0'],
);

String mintWire({String pollId = poll}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return signTicket(createTicketPayload(pollId, now), orgSeed);
}

/// A controllable relayer: scripts responses per path.
RelayClient relayWith(
  Future<http.Response> Function(http.Request request) handler,
) => RelayClient(baseUrl: 'http://relay.test', client: MockClient(handler));

RelayLiveVoterPort portWith({
  RelayClient? relay,
  List<String> group = const [],
  List<String> options = const ['Yes', 'No'],
  int phase = 0,
}) => RelayLiveVoterPort(
  pollAddress: poll,
  relay:
      relay ??
      relayWith((req) async {
        if (req.url.path == '/api/relay/tickets/pending') {
          return http.Response('{}', 200);
        }
        return http.Response('{"voters":[]}', 200);
      }),
  proofService: const FakeProofService(fakeProof),
  fetchGroup: (_) async => group,
  fetchOptions: (_) async => options,
  fetchPhase: (_) async => phase,
  mintSeed: () => '0xseed',
);

void main() {
  group('parseTicket', () {
    test('extracts the wire from a scanned deep link (?t=)', () async {
      final wire = mintWire();
      final ticket = await portWith().parseTicket(
        'tessera://live/$poll/vote?t=$wire',
      );
      expect(ticket.wire, wire);
    });

    test('accepts the bare wire string', () async {
      final wire = mintWire();
      expect((await portWith().parseTicket(wire)).wire, wire);
    });

    test('throws on structurally malformed input', () {
      expect(portWith().parseTicket('not-a-ticket'), throwsA(anything));
    });

    test('rejects a ticket minted for a DIFFERENT session', () {
      expect(
        portWith().parseTicket(mintWire(pollId: otherPoll)),
        throwsA(isA<TicketSessionMismatch>()),
      );
    });
  });

  group('announce', () {
    test('posts the derived commitment + confirmation code and keeps the seed '
        'behind the boundary', () async {
      late Map<String, dynamic> posted;
      final relay = relayWith((req) async {
        posted = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });
      final port = portWith(relay: relay);
      final wire = mintWire();

      final announcement = await port.announce(LiveTicket(wire));

      // FakeProofService derives '1234567890' for any seed.
      expect(announcement.commitment, '1234567890');
      final expectedCode = confirmationCode(
        decodeTicket(wire).n,
        announcement.commitment,
      );
      expect(announcement.confirmationCode, expectedCode);
      expect(posted, {
        'pollId': poll,
        'ticket': wire,
        'ephemeralIdentityCommitment': '1234567890',
        'confirmationCode': expectedCode,
      });
      // The 4-digit code is what the pending screen blows up full-size.
      expect(announcement.confirmationCode, matches(RegExp(r'^\d{4}$')));
    });

    test('throws when the relayer rejects the ticket', () {
      final relay = relayWith(
        (req) async => http.Response('{"error":"expired"}', 400),
      );
      expect(
        portWith(relay: relay).announce(LiveTicket(mintWire())),
        throwsA(isA<RelayException>()),
      );
    });
  });

  group('pollAdmission', () {
    test('null while the commitment is not in the on-chain group', () async {
      final port = portWith(group: ['111', '222']);
      expect(
        await port.pollAdmission(
          const LiveAnnouncement(
            commitment: '1234567890',
            confirmationCode: '0000',
          ),
        ),
        isNull,
      );
    });

    test('admission carries options + phase once registered', () async {
      final port = portWith(
        group: ['1234567890'],
        options: ['A', 'B', 'C'],
        phase: 1,
      );
      final admission = await port.pollAdmission(
        const LiveAnnouncement(
          commitment: '1234567890',
          confirmationCode: '0000',
        ),
      );
      expect(admission, isNotNull);
      expect(admission!.options, ['A', 'B', 'C']);
      expect(admission.phase, 1);
    });
  });

  group(
    'hostAlive (documented approximation: our queue entry is the signal)',
    () {
      Future<bool> aliveWithQueue(String votersJson) async {
        final relay = relayWith((req) async {
          if (req.url.path == '/api/relay/tickets/pending') {
            return http.Response('{}', 200);
          }
          return http.Response('{"voters":$votersJson}', 200);
        });
        final port = portWith(relay: relay);
        await port.announce(LiveTicket(mintWire())); // sets the commitment
        return port.hostAlive();
      }

      String entry(String status) =>
          '{"ticketNonce":"n","ticket":"t",'
          '"ephemeralIdentityCommitment":"1234567890",'
          '"confirmationCode":"0000","status":"$status","createdAt":1}';

      test('true while our entry is pending', () async {
        expect(await aliveWithQueue('[${entry('pending')}]'), isTrue);
      });

      test('false when the host rejected us', () async {
        expect(await aliveWithQueue('[${entry('rejected')}]'), isFalse);
      });

      test('false when our entry vanished (session dropped)', () async {
        expect(await aliveWithQueue('[]'), isFalse);
      });

      test('transient probe failure THROWS (machine keeps waiting)', () async {
        final relay = relayWith((req) async {
          if (req.url.path == '/api/relay/tickets/pending') {
            return http.Response('{}', 200);
          }
          return http.Response('down', 503);
        });
        final port = portWith(relay: relay);
        await port.announce(LiveTicket(mintWire()));
        expect(port.hostAlive(), throwsA(isA<RelayException>()));
      });

      test('true before anything was announced (nothing to lose)', () async {
        expect(await portWith().hostAlive(), isTrue);
      });
    },
  );

  group('cast path', () {
    test('generateProof uses the announce-time ephemeral identity', () async {
      final port = portWith(group: ['1234567890']);
      final announcement = await port.announce(LiveTicket(mintWire()));
      final proof = await port.generateProof(announcement, 1);
      expect(proof, isA<RelayProof>());
    });

    test('generateProof refuses an announcement this port never made', () {
      expect(
        portWith().generateProof(
          const LiveAnnouncement(commitment: '999', confirmationCode: '0000'),
          0,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('relayBallot returns the txHash on success', () async {
      final relay = relayWith((req) async {
        if (req.url.path == '/api/relay/vote') {
          expect(jsonDecode(req.body)['vote'], 1);
          return http.Response('{"txHash":"0xfeed"}', 200);
        }
        return http.Response('{}', 200);
      });
      expect(await portWith(relay: relay).relayBallot(1, fakeProof), '0xfeed');
    });

    test('relayBallot throws on relayer failure (→ castFailed, retryable)', () {
      final relay = relayWith(
        (req) async => http.Response('{"error":"no gas"}', 500),
      );
      expect(
        portWith(relay: relay).relayBallot(0, fakeProof),
        throwsA(isA<RelayException>()),
      );
    });
  });
}
