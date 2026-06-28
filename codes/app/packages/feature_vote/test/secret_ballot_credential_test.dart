import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/credentials/blind_rsa.dart' as blind_rsa;
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/voter_journey.dart';
import 'package:core_domain/models/relay_proof.dart';
import 'package:core_relay/server_client.dart';
import 'package:core_storage/identity_store.dart';
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Offline coverage of the SECRET-ballot client orchestration: the
/// [SecretBallotRegistrar] handshake and the [ServerVoterPortAdapter]
/// secret-mode branch, against a MockClient that plays a LOCAL blind-signing
/// issuer (RSASP1 with the fixture private exponent). Byte-exact interop with
/// the real server is proven separately by the live e2e
/// (`core_relay/test/server_client_secret_live_test.dart`).
const decId = 'dec_secret_1';

/// A fixed RSA-2048 issuer keypair (publicExponent 65537). The SPKI PEM is what
/// the mock serves from `/issuer`; `n`/`d` let the mock play RSASP1 blind-sign.
const issuerPem =
    '-----BEGIN PUBLIC KEY-----\n'
    'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3jaDJmYHL6Isl5i4YSfR\n'
    '56T0Xjs1E7QDZcGRW2F5TnpsSZL+WL6lwAVB7h2Alr7kxr9T9BRI7g4MFFNPDsq9\n'
    'GdGJjF+MbX0eiRYjO3e4CkGjPYfbGosVxsmcmpgj/aOn14dmaNCG7Wy+6+tjUOen\n'
    '1wAhxsfffmDwDOhdI5HfEjvQ/7lwdiRiVQHej8suLAAuubJN+TgUrCTxkkrTzyoR\n'
    'ul0z8lKCXNs1EX7h9er9s7QFajn0KF7uQth0kf4QUqgCtzDZeWO2k3grbPlmvxRY\n'
    'qJR5i2l1f27lmmr4OaOGvUUBYg+sqAIM0NPm0jFxhSy/w0pFv5CRLveyeVEMXJT5\n'
    'PQIDAQAB\n'
    '-----END PUBLIC KEY-----\n';

final _n = BigInt.parse(
  'de36832666072fa22c9798b86127d1e7a4f45e3b3513b40365c1915b61794e7a'
  '6c4992fe58bea5c00541ee1d8096bee4c6bf53f41448ee0e0c14534f0ecabd19'
  'd1898c5f8c6d7d1e8916233b77b80a41a33d87db1a8b15c6c99c9a9823fda3a7'
  'd7876668d086ed6cbeebeb6350e7a7d70021c6c7df7e60f00ce85d2391df123b'
  'd0ffb9707624625501de8fcb2e2c002eb9b24df93814ac24f1924ad3cf2a11ba'
  '5d33f252825cdb35117ee1f5eafdb3b4056a39f4285eee42d87491fe1052a802'
  'b730d97963b693782b6cf966bf1458a894798b69757f6ee59a6af839a386bd45'
  '01620faca8020cd0d3e6d23171852cbfc34a45bf90912ef7b279510c5c94f93d',
  radix: 16,
);
final _d = BigInt.parse(
  '0edcb0005f360f54462dbc77e67d9a8f26ebf62a79161085e2a623e1ebfec846'
  '2d5c6d61a80f563825d1df4a67598dba70e58688ae5ba35a5aa9f859730891c5'
  'ba8b3bd17f2baa80e293d1b6ee3ea7a6f4b34e9513ad263f75a80cf9ec7c5018'
  '0f74fd9f388531b7827c76719dcd649f1f61e2f0e6cc85d0c05841347a12e49d'
  'ee2682678aff370d4996f1e7e511f37f1829de35bed7db40aafbf3f13a609b45'
  '2c4cb1476e25209cca6888198ac660aa5ef44155d53f9a93d5b49ec34878eb80'
  'f4414c39942e8005c74c4e81e55bb448141eb937d5c46cc6ab7e78b1e2bd0b76'
  'e295485a7cad134e7027a8e7b69a9c7fc172277edf3b14f6e35ecb301ff198f9',
  radix: 16,
);

/// The issuer's RSASP1 blind-sign: `s = m^d mod n`, encoded to k=256 bytes.
String _localBlindSign(String blindedB64) {
  var m = BigInt.zero;
  for (final b in base64.decode(blindedB64)) {
    m = (m << 8) | BigInt.from(b & 0xff);
  }
  final s = m.modPow(_d, _n);
  final out = Uint8List(256);
  var x = s;
  final mask = BigInt.from(0xff);
  for (var i = 255; i >= 0; i--) {
    out[i] = (x & mask).toInt();
    x = x >> 8;
  }
  return base64.encode(out);
}

/// A MockClient that plays the secret-ballot server: serves the issuer key,
/// blind-signs registrations, and accepts a credentialed cast (recording the
/// last body + whether the presented credential verifies under the issuer).
MockClient _issuerMock({
  String? overrideIssuerHash,
  void Function(Map<String, dynamic> ballotBody, bool credentialOk)? onCast,
  Set<String>? usedSerials,
}) {
  return MockClient((r) async {
    final path = r.url.path;
    if (r.method == 'GET' && path == '/decisions/$decId') {
      // Public metadata view — secret mode so the adapter takes its secret
      // branch; carries the anchored issuerPubKeyHash.
      return http.Response(
        jsonEncode({
          'id': decId,
          'title': 'Secret decision',
          'options': ['Yes', 'No'],
          'method': 'single',
          'state': 'registration',
          'ballotMode': 'secret',
          'resultsPolicy': 'sealed',
          'issuerPubKeyHash':
              overrideIssuerHash ?? blind_rsa.issuerKeyHash(issuerPem),
          'turnout': 0,
        }),
        200,
      );
    }
    if (r.method == 'GET' && path == '/decisions/$decId/issuer') {
      return http.Response(
        jsonEncode({
          'issuerPublicKeyPem': issuerPem,
          'issuerPubKeyHash':
              overrideIssuerHash ?? blind_rsa.issuerKeyHash(issuerPem),
        }),
        200,
      );
    }
    if (r.method == 'POST' && path == '/register') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'decisionId': decId,
          'blindSignature': _localBlindSign(body['blindedMessage'] as String),
        }),
        200,
      );
    }
    if (r.method == 'POST' && path == '/ballots') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final serial = body['serial'] as String?;
      final cred = body['credentialSig'] as String?;
      final ok =
          serial != null &&
          cred != null &&
          blind_rsa.verifyCredentialLocally(issuerPem, '$decId|$serial', cred);
      if (serial != null && (usedSerials?.contains(serial) ?? false)) {
        return http.Response(
          jsonEncode({
            'error': 'serial-used',
            'code': 'SERIAL_USED',
            'signature': 's',
          }),
          409,
        );
      }
      usedSerials?.add(serial ?? '');
      onCast?.call(body, ok);
      return http.Response(
        jsonEncode({
          'receipt': {'ballotHash': 'bh-$serial', 'runningRoot': 'rr'},
          'decisionId': decId,
        }),
        201,
      );
    }
    return http.Response(jsonEncode({'code': 'NOT_FOUND'}), 404);
  });
}

void main() {
  group('SecretBallotRegistrar', () {
    test(
      'obtain() returns a credential that verifies under the issuer key',
      () async {
        final client = ServerClient(
          baseUrl: 'http://s.test',
          client: _issuerMock(),
        );
        final reg = SecretBallotRegistrar(client);
        final cred = await reg.obtain(decId);

        expect(cred.serial.length, 32, reason: '16 bytes hex');
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(cred.serial), isTrue);
        expect(
          blind_rsa.verifyCredentialLocally(
            issuerPem,
            '$decId|${cred.serial}',
            cred.credentialSig,
          ),
          isTrue,
          reason: 'the finalized credential must verify over the bound message',
        );
      },
    );

    test('rejects a tampered issuer key (served hash ≠ recomputed)', () async {
      final client = ServerClient(
        baseUrl: 'http://s.test',
        client: _issuerMock(overrideIssuerHash: 'deadbeef'),
      );
      final reg = SecretBallotRegistrar(client);
      await expectLater(
        reg.obtain(decId),
        throwsA(isA<SecretBallotCredentialError>()),
      );
    });

    test(
      'rejects an issuer hash that disagrees with the anchored hash',
      () async {
        final client = ServerClient(
          baseUrl: 'http://s.test',
          client: _issuerMock(),
        );
        final reg = SecretBallotRegistrar(client);
        await expectLater(
          reg.obtain(decId, expectedIssuerPubKeyHash: 'not-the-anchored-hash'),
          throwsA(isA<SecretBallotCredentialError>()),
        );
      },
    );
  });

  group('ServerVoterPortAdapter secret-mode', () {
    Future<ServerVoterPortAdapter> adapterForSecret(MockClient mock) async {
      final adapter = ServerVoterPortAdapter(
        client: ServerClient(baseUrl: 'http://s.test', client: mock),
        identityStore: InMemoryIdentityStore('seed'),
        decisionId: decId,
        module: VoterModule.anon,
        secretRegistrar: SecretBallotRegistrar(
          ServerClient(baseUrl: 'http://s.test', client: mock),
        ),
      );
      return adapter;
    }

    test(
      'register at join, then cast presents a valid (serial, credentialSig)',
      () async {
        Map<String, dynamic>? castBody;
        bool? credentialOk;
        final mock = _issuerMock(
          onCast: (b, ok) {
            castBody = b;
            credentialOk = ok;
          },
          usedSerials: <String>{},
        );
        final adapter = await adapterForSecret(mock);

        // Snapshot must surface ballotMode=secret so the secret branch engages.
        final view = await adapter.fetchSnapshot();
        await adapter.requestJoin(view);
        final receipt = await adapter.relayBallot(
          const SingleChoice(1),
          _placeholderProof,
          view,
          CancellationToken(),
        );

        expect(castBody, isNotNull);
        expect(castBody!['payload'], {'kind': 'single', 'choice': 1});
        expect(castBody!['serial'], isA<String>());
        expect(castBody!['credentialSig'], isA<String>());
        expect(castBody!['idempotencyKey'], 'cast-${castBody!['serial']}');
        expect(
          credentialOk,
          isTrue,
          reason: 'the server-side credential verify must pass',
        );
        expect(receipt.nullifier, 'bh-${castBody!['serial']}');
      },
    );

    test('a reused serial surfaces a no-double-vote error', () async {
      final used = <String>{};
      final mock = _issuerMock(usedSerials: used);
      final adapter = await adapterForSecret(mock);
      final view = await adapter.fetchSnapshot();
      await adapter.requestJoin(view);

      // First cast succeeds; a second cast reuses the cached credential serial.
      await adapter.relayBallot(
        const SingleChoice(0),
        _placeholderProof,
        view,
        CancellationToken(),
      );
      await expectLater(
        adapter.relayBallot(
          const SingleChoice(0),
          _placeholderProof,
          view,
          CancellationToken(),
        ),
        throwsA(predicate((e) => '$e'.contains('double-vote'))),
      );
    });
  });
}

const _placeholderProof = RelayProof(
  merkleTreeDepth: 0,
  merkleTreeRoot: '0',
  nullifier: '0',
  message: '0',
  scope: '0',
  points: <String>[],
);
