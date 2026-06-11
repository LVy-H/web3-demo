import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/digests/keccak.dart';

/// Commit-reveal helpers for the M2 blind-voting module. The on-chain commit is
/// `keccak256(abi.encodePacked(uint256 optionIndex, bytes32 salt))` — byte-identical
/// to the contract (`ZkBlindVoting.commitVote`) and the React `useBlindVote` hook,
/// so a commit made here reveals correctly anywhere.

/// 32 cryptographically-random bytes for a commit salt.
Uint8List generateSalt([Random? rng]) {
  final r = rng ?? Random.secure();
  return Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
}

/// `keccak256(abi.encodePacked(uint256 optionIndex, bytes32 salt))`.
/// [salt] must be exactly 32 bytes. Returns the 32-byte digest.
Uint8List blindCommitHash(int optionIndex, Uint8List salt) {
  if (salt.length != 32) {
    throw ArgumentError('salt must be 32 bytes, got ${salt.length}');
  }
  if (optionIndex < 0) {
    throw ArgumentError('optionIndex must be non-negative');
  }
  // uint256 optionIndex as 32-byte big-endian.
  final option = Uint8List(32);
  var v = optionIndex;
  for (var i = 31; i >= 0 && v > 0; i--) {
    option[i] = v & 0xff;
    v >>= 8;
  }
  final packed = Uint8List(64)
    ..setRange(0, 32, option)
    ..setRange(32, 64, salt);
  return KeccakDigest(256).process(packed);
}

/// `0x`-prefixed lowercase hex of [b].
String toHex0x(Uint8List b) => '0x${hex.encode(b)}';

/// Parse a `0x`-prefixed (or bare) hex string into bytes.
Uint8List fromHex(String s) =>
    Uint8List.fromList(hex.decode(s.startsWith('0x') ? s.substring(2) : s));
