import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/digests/keccak.dart';

/// Survey ballot commitment for the Phase 12d `survey-vote` module.
///
/// The client computes `message` BEFORE proving and binds it to the single
/// Semaphore signal; the `ZkSurveyVoting` contract RECOMPUTES it on-chain from
/// calldata (`uint256(keccak256(abi.encode(answers))) >> 8`) and requires
/// `proof.message == that`. If this Dart serialization does not match Solidity's
/// `keccak256(abi.encode(uint256[]))` byte-for-byte, every survey cast reverts
/// (`TamperedVoteSignal`). The cross-impl gate-2 test pins this against frozen
/// ethers/Solidity literals (`test/core/crypto/survey_commit_test.dart`).
///
/// NOTE on `BigInt` (load-bearing): the keccak digest is a 256-bit value and the
/// result of `>> 8` is a 248-bit field element — both FAR beyond Dart's native
/// 64-bit `int`. The digest is parsed to [BigInt] (big-endian, unsigned) and the
/// shift is a [BigInt] shift. An `int` here would be silently catastrophic.
///
/// This is `abi.encode` (offset + length + words) — NOT `abi.encodePacked`. See
/// `core/crypto/blind_commit.dart` for prior-art pointycastle keccak in Dart,
/// but note it uses the WRONG (packed) layout for this commitment.

/// `abi.encode(uint256[] answers)` — the canonical, length-prefixed layout
/// Solidity produces for a dynamic array of a static type:
///
/// ```
/// [ 0x20            ]  // 32-byte big-endian offset to the array data
/// [ answers.length  ]  // 32-byte big-endian length n
/// [ answers[0] ] … [ answers[n-1] ]  // n × 32-byte big-endian words
/// ```
///
/// i.e. `32 * (2 + n)` bytes total. Each [BigInt] answer is left-padded into a
/// 32-byte big-endian word. Answers must be non-negative and fit in 256 bits.
Uint8List abiEncodeUint256Array(List<BigInt> answers) {
  final n = answers.length;
  final out = Uint8List(32 * (2 + n));

  // word 0: offset to the array data = 0x20.
  _writeWordBE(out, 0, BigInt.from(0x20));
  // word 1: array length n.
  _writeWordBE(out, 1, BigInt.from(n));
  // words 2..2+n-1: each answer as a 32-byte big-endian word.
  for (var q = 0; q < n; q++) {
    _writeWordBE(out, 2 + q, answers[q]);
  }
  return out;
}

/// Write [value] as a 32-byte big-endian word at word index [wordIndex] (byte
/// offset `wordIndex * 32`). [value] must be in `[0, 2^256)`.
void _writeWordBE(Uint8List buf, int wordIndex, BigInt value) {
  if (value.isNegative) {
    throw ArgumentError('uint256 word must be non-negative, got $value');
  }
  if (value.bitLength > 256) {
    throw ArgumentError('uint256 word overflows 256 bits, got $value');
  }
  final base = wordIndex * 32;
  var v = value;
  final mask = BigInt.from(0xff);
  // Fill from the least-significant byte (rightmost) leftward; leading bytes
  // stay zero (left-padding), matching big-endian 32-byte words.
  for (var i = 31; i >= 0 && v > BigInt.zero; i--) {
    buf[base + i] = (v & mask).toInt();
    v = v >> 8;
  }
}

/// The survey ballot commitment:
/// `message = ( BigInt(keccak256(abi.encode(answers))) >> 8 )`.
///
/// The `>> 8` drops the low byte of the 256-bit keccak digest, yielding a
/// 248-bit value that is ALWAYS `< BN254 r` (~2^254) — a valid in-field
/// Semaphore signal. This is byte-identical to ethers'
/// `BigInt(keccak256(abi.encode(['uint256[]'], [answers]))) >> 8n` and the
/// contract's on-chain `uint256(keccak256(abi.encode(answers))) >> 8`.
BigInt surveyCommitment(List<BigInt> answers) {
  final preimage = abiEncodeUint256Array(answers);
  final digest = KeccakDigest(256).process(preimage); // 32-byte big-endian
  // Parse the 32-byte digest as an unsigned big-endian BigInt, then >> 8.
  final asInt = BigInt.parse(hex.encode(digest), radix: 16);
  return asInt >> 8;
}
