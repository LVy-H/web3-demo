import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:core_crypto/crypto/confirmation_code.dart';
import 'package:core_crypto/crypto/org_keypair.dart';
import 'package:core_crypto/crypto/ticket.dart';
import 'package:core_relay/relay_client.dart';

/// GOLD-STANDARD cross-client proof: a ticket signed by the Dart org_keypair +
/// ticket libs is accepted by the REAL relayer's ed25519 verifier, the
/// Dart-derived confirmation code round-trips through the queue, and redeem
/// consumes it. This exercises the whole ticket flow against the running server
/// (not just a golden vector).
///
/// Requires the relayer on :3001:
///   cd codes/relayer && RELAYER_PRIVATE_KEY=0xHARDHAT_KEY RPC_URL=http://127.0.0.1:8545 PORT=3001 npm start
/// Skips (does not fail) when the relayer is unreachable.
void main() {
  const base = 'http://localhost:3001';
  const pollId = '0x1111111111111111111111111111111111111111';

  Future<bool> relayerUp() async {
    try {
      final r = await http
          .get(Uri.parse('$base/api/relay/status'))
          .timeout(const Duration(seconds: 3));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  test('Dart-signed ticket accepted by the real relayer; code round-trips; redeem consumes',
      () async {
    if (!await relayerUp()) {
      markTestSkipped('relayer not running on :3001');
      return;
    }
    final client = RelayClient(baseUrl: base);

    // 1. Dart org keypair → register the verification anchor.
    final kp = generateOrgKeypair();
    await client.issueOrgKey(pollId, kp.pubKey);

    // 2. Dart-signed ticket + Dart-derived confirmation code.
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ticket = createTicketPayload(pollId, now);
    final wire = signTicket(ticket, kp.privKey);
    const commitment = '12345678901234567890';
    final code = confirmationCode(ticket.n, commitment);

    // 3. Relayer verifies the Dart-signed ticket's ed25519 signature.
    final res = await client.postPending(pollId, wire, commitment, code);
    expect(res.ok, isTrue, reason: 'relayer rejected the Dart ticket: ${res.error}');

    // 4. The queue returns our entry with the same code + commitment.
    final queue = await client.fetchQueue(pollId);
    expect(
      queue.any((v) =>
          v.confirmationCode == code &&
          v.ephemeralIdentityCommitment == commitment),
      isTrue,
    );

    // 5. Redeem consumes the ticket; re-posting the same nonce is rejected (409).
    await client.redeemTicket(pollId, wire);
    final reposted = await client.postPending(pollId, wire, commitment, code);
    expect(reposted.ok, isFalse);
    expect(reposted.status, 409);

    client.close();
  });
}
