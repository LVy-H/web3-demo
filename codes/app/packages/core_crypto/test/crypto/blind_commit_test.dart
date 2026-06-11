import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:core_crypto/crypto/blind_commit.dart';

void main() {
  // Golden vectors generated with viem (the exact encoding the contract and the
  // React useBlindVote hook use): keccak256(encodePacked(['uint256','bytes32'],
  // [option, salt])) for salt = 0x0123456789abcdef * 4.
  final salt = fromHex('0x${'0123456789abcdef' * 4}');
  const golden = {
    0: '0x6b7f88b4cc37e930ff7bee35478b38560f7698868b51543512cb7785ca8064ff',
    1: '0x6ceed93097fc6ab52a1e37491167960c8e3cebe47c49d9b65d5898439b64fd1c',
    2: '0xda3e9169e54796d9eb8dc7059930e0e0ffe2be126098228e85097c093bb04b64',
  };

  test('blindCommitHash matches the viem/contract golden vectors', () {
    golden.forEach((option, expected) {
      expect(toHex0x(blindCommitHash(option, salt)), expected,
          reason: 'option $option');
    });
  });

  test('salt must be exactly 32 bytes', () {
    expect(() => blindCommitHash(0, Uint8List(31)), throwsArgumentError);
  });

  test('generateSalt returns 32 unique random bytes', () {
    final a = generateSalt();
    final b = generateSalt();
    expect(a.length, 32);
    expect(a, isNot(b));
  });

  test('round-trips through hex', () {
    final s = generateSalt();
    expect(fromHex(toHex0x(s)), s);
  });
}
