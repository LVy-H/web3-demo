import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkvote_mobile/core/crypto/org_keypair.dart';
import 'package:zkvote_mobile/core/crypto/ticket.dart';

/// In-memory [KeyStore] so the lib is testable without platform storage.
class MemStore implements KeyStore {
  final Map<String, String> dump = {};
  @override
  String? getItem(String key) => dump[key];
  @override
  void setItem(String key, String value) => dump[key] = value;
  @override
  void removeItem(String key) => dump.remove(key);
}

const pollA = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const pollB = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/cross_client_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final ed = fixture['ed25519'] as Map<String, dynamic>;

  group('orgKeypair', () {
    test('publicKeyFor reproduces the golden TS public key', () {
      expect(publicKeyFor(ed['seedHex'] as String), ed['pubKey']);
    });

    test('generated keypair: hex-shaped and pubKey derives from privKey', () {
      final kp = generateOrgKeypair();
      expect(kp.privKey, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(kp.pubKey, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(publicKeyFor(kp.privKey), kp.pubKey);
    });

    test('a generated key signs a ticket that verifies against its pubKey', () {
      final kp = generateOrgKeypair();
      final enc = signTicket(createTicketPayload(pollA, 1000), kp.privKey);
      expect(verifyTicket(enc, kp.pubKey, now: 1000).valid, isTrue);
    });

    test('save then load returns the identical keypair', () {
      final store = MemStore();
      final kp = generateOrgKeypair();
      saveOrgKeypair(pollA, kp, store);
      expect(loadOrgKeypair(pollA, store), kp);
    });

    test('returns null for an unknown poll', () {
      expect(loadOrgKeypair(pollA, MemStore()), isNull);
    });

    test('getOrCreate is idempotent per poll and isolated across polls', () {
      final store = MemStore();
      final a1 = getOrCreateOrgKeypair(pollA, store);
      final a2 = getOrCreateOrgKeypair(pollA, store);
      final b1 = getOrCreateOrgKeypair(pollB, store);
      expect(a2, a1); // same poll → same key
      expect(b1 == a1, isFalse); // different poll → different key
    });

    test('corrupt stored value returns null without throwing', () {
      final store = MemStore();
      store.setItem('org-keypair-${pollA.toLowerCase()}', 'not json{');
      expect(loadOrgKeypair(pollA, store), isNull);
      store.setItem(
        'org-keypair-${pollA.toLowerCase()}',
        jsonEncode({'privKey': 'short'}),
      );
      expect(loadOrgKeypair(pollA, store), isNull);
    });

    test('clear removes the stored key', () {
      final store = MemStore();
      saveOrgKeypair(pollA, generateOrgKeypair(), store);
      clearOrgKeypair(pollA, store);
      expect(loadOrgKeypair(pollA, store), isNull);
    });
  });
}
