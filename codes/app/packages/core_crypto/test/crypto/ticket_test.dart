import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_crypto/crypto/ticket.dart';

/// Cross-client byte-compatibility for the signed ticket. Golden preimage/wire
/// come from codes/frontend/src/lib/ticket.ts (the relayer verifies the same
/// layout). A pass proves a Dart-signed ticket verifies on the relayer and a
/// relayer/web-signed ticket verifies here.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/cross_client_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final ed = fixture['ed25519'] as Map<String, dynamic>;
  final tv = fixture['ticket'] as Map<String, dynamic>;
  final seedHex = ed['seedHex'] as String;
  final pubKey = ed['pubKey'] as String;
  final fields = tv['fields'] as Map<String, dynamic>;
  final goldenPreimageHex = tv['preimageHex'] as String;
  final goldenWire = tv['wire'] as String;

  Ticket goldenTicket() => Ticket(
        p: fields['p'] as String,
        n: fields['n'] as String,
        e: fields['e'] as int,
      );

  group('ticket — golden cross-client vectors', () {
    test('ticketPreimage matches the 32-byte TS preimage', () {
      expect(hex.encode(ticketPreimage(goldenTicket())), goldenPreimageHex);
    });

    test('signTicket reproduces the exact TS wire string', () {
      expect(signTicket(goldenTicket(), seedHex), goldenWire);
    });

    test('decodeTicket round-trips the golden wire', () {
      final t = decodeTicket(goldenWire);
      expect(t.p, fields['p']);
      expect(t.n, fields['n']);
      expect(t.e, fields['e']);
    });
  });

  group('ticket — verifyTicket', () {
    test('valid + unexpired (now < e)', () {
      final r = verifyTicket(goldenWire, pubKey, now: (fields['e'] as int) - 1);
      expect(r.valid, isTrue);
      expect(r.ticket!.p, fields['p']);
    });

    test('expired when now >= e', () {
      final r = verifyTicket(goldenWire, pubKey, now: fields['e'] as int);
      expect(r.valid, isFalse);
      expect(r.reason, TicketInvalidReason.expired);
    });

    test('badSig for a different public key', () {
      const otherPub =
          '0000000000000000000000000000000000000000000000000000000000000001';
      final r = verifyTicket(goldenWire, otherPub, now: (fields['e'] as int) - 1);
      expect(r.valid, isFalse);
      expect(r.reason, TicketInvalidReason.badSig);
    });

    test('badSig for a tampered preimage byte', () {
      // Flip the first pollId byte; signature no longer matches.
      final bytes = base64Url.decode(base64Url.normalize(goldenWire));
      bytes[0] = bytes[0] ^ 0xff;
      final tampered = base64Url.encode(bytes).replaceAll('=', '');
      final r = verifyTicket(tampered, pubKey, now: (fields['e'] as int) - 1);
      expect(r.valid, isFalse);
      expect(r.reason, TicketInvalidReason.badSig);
    });

    test('malformed input does not throw', () {
      expect(verifyTicket('AAAA', pubKey, now: 1).reason,
          TicketInvalidReason.malformed);
      expect(verifyTicket('not valid base64 @@@', pubKey, now: 1).reason,
          TicketInvalidReason.malformed);
    });
  });

  group('ticket — createTicketPayload', () {
    test('sets expiry = now + ttl and normalises pollId', () {
      final t = createTicketPayload(
        '0x1111111111111111111111111111111111111111',
        1000,
      );
      expect(t.e, 1000 + ticketTtlSeconds);
      expect(t.p, '0x1111111111111111111111111111111111111111');
      expect(t.n.length, 16); // 8 bytes hex
    });

    test('rejects an invalid pollId', () {
      expect(() => createTicketPayload('0xabc', 1000), throwsArgumentError);
    });
  });
}
