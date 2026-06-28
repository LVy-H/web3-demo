@Tags(['live'])
library;

import 'dart:io';
import 'dart:math';

import 'package:core_crypto/credentials/blind_rsa.dart' as blind_rsa;
import 'package:core_relay/server_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// LIVE byte-exact-interop proof for the SECRET-ballot path: the real Flutter
/// crypto ([blind_rsa]) + the real [ServerClient] drive a REAL running
/// `codes/server` through the full RFC 9474 RSABSSA credential protocol — no
/// mocks, no `MockClient`. If the Dart blinding / PSS encoding diverges from the
/// server's `@cloudflare/blindrsa-ts` by a single byte, the server rejects the
/// cast (403 INELIGIBLE) and this test goes red. GREEN ⇒ correct.
///
/// GUARDED so CI never needs a server: it only runs when `TESSERA_LIVE_SERVER`
/// points at a running server. Start one with:
///
///   cd codes/server && npm install && npm run build
///   DATA_DIR=$(mktemp -d) PORT=3091 node dist/index.js   # prints ADMIN TOKEN
///
/// then:
///
///   TESSERA_LIVE_SERVER=http://127.0.0.1:3091 \
///   TESSERA_ADMIN_TOKEN=`<token>` \
///   flutter test --tags live \
///     packages/core_relay/test/server_client_secret_live_test.dart
///
/// The loop: createDecision(secret) → getIssuer (recomputed hash == anchored
/// issuerPubKeyHash) → register×3 (blind locally, server blind-signs, finalize)
/// → open → castBallot(serial, credentialSig)×3 → a reused serial ⇒ 409
/// SERIAL_USED → close → publish → GET /verify ⇒ ok:true (all §11 checks).
void main() {
  final base = Platform.environment['TESSERA_LIVE_SERVER'];
  final adminToken = Platform.environment['TESSERA_ADMIN_TOKEN'];

  if (base == null || base.isEmpty) {
    test('live secret-ballot e2e (no live server)', () {
      markTestSkipped(
        'set TESSERA_LIVE_SERVER (and TESSERA_ADMIN_TOKEN) to run the '
        'secret-ballot interop loop against a real codes/server instance',
      );
    }, skip: true);
    return;
  }

  test('secret-ballot interop: create(secret) → getIssuer(hash ok) → register×3 '
      '(blind locally) → open → cast×3 → reused-serial 409 → close → publish → '
      'verify ok:true', () async {
    expect(
      adminToken != null && adminToken.isNotEmpty,
      isTrue,
      reason: 'TESSERA_ADMIN_TOKEN must be the admin token the server printed',
    );

    final client = ServerClient(baseUrl: base, token: adminToken);
    addTearDown(client.close);
    final rng = Random.secure();

    String randomSerial() {
      final sb = StringBuffer();
      for (var i = 0; i < 16; i++) {
        sb.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
      }
      return sb.toString();
    }

    // ── create (secret) — lands in 'registration', mints a per-decision
    //    RSABSSA issuer; the response advertises its pubkey + anchored hash. ─
    final created = await client.createDecision(<String, dynamic>{
      'title': 'Working-example: secret proposal',
      'options': <String>['Yes', 'No'],
      'method': 'single',
      'ballotMode': 'secret',
      'resultsPolicy': 'sealed',
      'eligibility': <String, dynamic>{'method': 'open'},
      'rule': <String, dynamic>{
        'threshold': <String, dynamic>{'kind': 'majority'},
        'tieBreak': 'declare',
      },
      'schedule': <String, dynamic>{},
      'visibility': 'listed',
      'anchorMode': 'broadcast',
    });
    final decisionId = created['id'] as String;
    expect(decisionId, isNotEmpty);
    expect(created['state'], 'registration');
    final createIssuerHash = created['issuerPubKeyHash'] as String;
    expect(createIssuerHash, isNotEmpty);

    // ── getIssuer — fetch the SPKI pubkey and PROVE the trust-minimised
    //    binding: recomputed sha256hex(pem) == the anchored issuerPubKeyHash. ─
    final issuer = await client.getIssuer(decisionId);
    final issuerPem = issuer['issuerPublicKeyPem'] as String;
    final advertisedHash = issuer['issuerPubKeyHash'] as String;
    expect(
      blind_rsa.issuerKeyHash(issuerPem),
      advertisedHash,
      reason: 'recomputed issuer-key hash must equal the served hash',
    );
    expect(advertisedHash, createIssuerHash);
    // The public metadata view advertises the SAME anchored hash.
    final meta = await client.getDecision(decisionId);
    expect(meta['issuerPubKeyHash'], advertisedHash);
    expect(meta['ballotMode'], 'secret');

    // ── register ×3 — blind a credential LOCALLY under the issuer pubkey,
    //    the server blind-signs the opaque token, finalize into a credential. ─
    final serials = <String>[];
    final credentialSigs = <String>[];
    for (var i = 0; i < 3; i++) {
      final serial = randomSerial();
      final message = '$decisionId|$serial';
      final blinded = blind_rsa.blind(issuerPem, message);
      final reg = await client.register(decisionId, blinded.blindedB64);
      final blindSig = reg['blindSignature'] as String;
      expect(blindSig, isNotEmpty);
      final credentialSig = blind_rsa.finalize(
        issuerPem,
        message,
        blindSig,
        blinded.state,
      );
      serials.add(serial);
      credentialSigs.add(credentialSig);
    }
    // The §6 issued-credential ledger now counts 3 issuances.
    expect((await client.getDecision(decisionId))['issuedCount'], 3);

    // ── open — registration CLOSES; a late register is refused. ─────────────
    expect((await client.openDecision(decisionId))['state'], 'open');
    await expectLater(
      client.register(decisionId, 'AAAA'),
      throwsA(
        isA<ServerException>().having(
          (e) => e.isRegistrationClosed,
          'isRegistrationClosed',
          isTrue,
        ),
      ),
    );

    // ── cast ×3 (2× Yes, 1× No) with the anonymous credentials. A wrong byte
    //    in the Dart blinding makes the server reject this 403 INELIGIBLE. ────
    final choices = <int>[0, 0, 1];
    for (var i = 0; i < 3; i++) {
      final res = await client.castBallot(
        decisionId: decisionId,
        payload: <String, dynamic>{'kind': 'single', 'choice': choices[i]},
        idempotencyKey: 'cast-${serials[i]}',
        serial: serials[i],
        credentialSig: credentialSigs[i],
      );
      final receipt = res['receipt'] as Map<String, dynamic>;
      expect(receipt['ballotHash'], isA<String>());
      expect(
        receipt['logPosition'],
        i,
        reason: 'each credentialed cast appends one leaf in order',
      );
    }

    // ── a reused serial (different idempotency key) ⇒ 409 SERIAL_USED. ───────
    await expectLater(
      client.castBallot(
        decisionId: decisionId,
        payload: <String, dynamic>{'kind': 'single', 'choice': 1},
        idempotencyKey: 'cast-${serials[0]}-again',
        serial: serials[0],
        credentialSig: credentialSigs[0],
      ),
      throwsA(
        isA<ServerException>()
            .having((e) => e.isSerialUsed, 'isSerialUsed', isTrue)
            .having((e) => e.signature, 'signature', isNotNull),
      ),
    );

    // ── root reflects exactly 3 leaves (the rejected double-vote added none).
    final root = await client.getRoot(decisionId);
    expect(root['leafCount'], 3);

    // ── /ballots serves the serials publicly. ───────────────────────────────
    final page = await client.getBallots(decisionId, after: -1, limit: 10);
    final ballots = (page['ballots'] as List).cast<Map<String, dynamic>>();
    expect(ballots, hasLength(3));
    expect(
      ballots.map((b) => b['serial']).toSet(),
      serials.toSet(),
      reason: 'the public log binds the anonymous credential serials',
    );

    // ── close → publish. ────────────────────────────────────────────────────
    expect((await client.closeDecision(decisionId))['state'], 'closed');
    expect((await client.publishDecision(decisionId))['state'], 'published');

    // ── GET /verify ⇒ ok:true with every §11 check passing (incl.
    //    no-double-vote over the secret-mode serials). ────────────────────────
    final verify = await client.getVerify(decisionId);
    final report = verify['report'] as Map<String, dynamic>;
    final checks = (report['checks'] as List).cast<Map<String, dynamic>>();
    // ignore: avoid_print
    print(
      'LIVE SECRET RESULT: ok=${report['ok']} '
      'checks=${checks.map((c) => '${c['name']}:${c['ok']}').join(',')} '
      'tally=${report['tally']?['optionScores']} '
      'verdict=${report['verdict']?['outcome']}',
    );
    expect(
      report['ok'],
      isTrue,
      reason: 'verifier report: ${report['checks']}',
    );
    for (final c in checks) {
      expect(c['ok'], isTrue, reason: "§11 check '${c['name']}' failed");
    }
    final ndv = checks.firstWhere((c) => c['name'] == 'no-double-vote');
    expect((ndv['detail'] as String).contains('secret-mode'), isTrue);
    expect(report['tally']['optionScores'], <int>[2, 1]);
    expect(report['verdict']['outcome'], 'carried');
  });
}
