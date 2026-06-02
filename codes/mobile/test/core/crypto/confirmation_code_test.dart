import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/core/crypto/confirmation_code.dart';

/// Cross-client byte-compatibility tests. The golden codes come from the TS
/// reference lib (codes/frontend/src/lib/confirmationCode.ts) via the oracle
/// generator; a pass means the Dart port agrees with the web client + relayer,
/// not merely with itself.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/cross_client_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final ccVectors =
      (fixture['confirmationCode'] as List).cast<Map<String, dynamic>>();

  group('confirmationCode — golden cross-client vectors', () {
    test('reproduces the TS codes (commitment as decimal String)', () {
      for (final v in ccVectors) {
        expect(
          confirmationCode(v['nonce'] as String, v['commitment'] as String),
          v['code'],
          reason: 'nonce=${v['nonce']} commitment=${v['commitment']}',
        );
      }
    });

    test('reproduces the TS codes (commitment as BigInt)', () {
      for (final v in ccVectors) {
        expect(
          confirmationCode(
            v['nonce'] as String,
            BigInt.parse(v['commitment'] as String),
          ),
          v['code'],
        );
      }
    });
  });

  group('confirmationCode — invariants', () {
    test('always returns exactly 4 decimal digits', () {
      final commitments = <BigInt>[
        BigInt.zero,
        BigInt.one,
        BigInt.from(42),
        BigInt.parse('12345678901234567890123456789012345678901234567890'),
        BigInt.two.pow(200),
      ];
      for (final c in commitments) {
        expect(
          confirmationCode('aabbccddeeff0011', c),
          matches(RegExp(r'^[0-9]{4}$')),
        );
      }
    });

    test('hex-string vs bytes nonce, BigInt vs String commitment agree', () {
      const nonceHex = 'aabbccddeeff0011';
      final nonceBytes = Uint8List.fromList(hex.decode(nonceHex));
      final commitment = BigInt.parse(
        '12345678901234567890123456789012345678901234567890',
      );
      final fromHexAndBigint = confirmationCode(nonceHex, commitment);
      final fromBytesAndString =
          confirmationCode(nonceBytes, commitment.toString());
      expect(fromBytesAndString, fromHexAndBigint);
    });

    test('rejects a negative commitment', () {
      expect(
        () => confirmationCode('aabbccddeeff0011', BigInt.from(-1)),
        throwsArgumentError,
      );
    });
  });
}
