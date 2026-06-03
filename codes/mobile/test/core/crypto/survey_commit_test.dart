import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/core/crypto/survey_commit.dart';

/// Gate 2 — keccak serialization cross-implementation match (Phase 12d survey).
///
/// The survey ballot commitment `message = keccak256(abi.encode(answers)) >> 8`
/// is computed by THREE implementations that MUST agree byte-for-byte:
///   - Dart  (this `surveyCommitment` helper, pointycastle keccak)
///   - JS    (ethers `BigInt(keccak256(coder.encode(['uint256[]'],[a]))) >> 8n`)
///   - Solidity (`uint256(keccak256(abi.encode(answers))) >> 8`, on-chain)
/// If they diverge by a single byte, `proof.message != recomputed` and EVERY
/// survey cast reverts (`TamperedVoteSignal`).
///
/// The expected values below are HARDCODED LITERALS, computed ONCE via Node +
/// ethers with the SAME expression the contract test uses:
///   const coder = ethers.AbiCoder.defaultAbiCoder();
///   const surveyMsg = (a) =>
///     BigInt(ethers.keccak256(coder.encode(['uint256[]'], [a]))) >> 8n;
/// (the exact `surveyMsg` in `codes/contracts/test/ZkSurveyVoting.test.ts`).
/// Because `ZkSurveyVoting.test.ts`'s passing `[2,5]` test proves that ethers
/// value is byte-equal to Solidity's on-chain `keccak256(abi.encode(answers))>>8`
/// (the cast only succeeds if `proof.message == the contract's recompute`),
/// asserting the Dart helper equals these literals transitively pins
/// **Dart ≡ JS ≡ Solidity**. Re-deriving them in Dart would defeat the purpose;
/// frozen literals are what actually catch a layout/endianness bug.
void main() {
  // ── Frozen cross-impl vectors (ethers/Solidity, NOT Dart-rederived) ─────────
  // Each: answers → keccak256(abi.encode(uint256[] answers)) >> 8 (decimal).
  const vectors = <(List<int>, String)>[
    // The spec's worked fixed vector: Q0 single-choice = option 2, Q1
    // multi-select = bitmask 0b0101 = 5 ({A, C}). This is the SAME [2,5] the
    // passing ZkSurveyVoting.test.ts Gate-2 test casts on-chain.
    (
      [2, 5],
      '180653404585830033325972674113326059354765865067025140798154610466511279271',
    ),
    // Single-element vector (one single-choice question, option 2).
    (
      [2],
      '166399664726539790152100863871307623673154079193654559706724864657210037118',
    ),
    // Wider / boundary vector: 3 questions including a full-width 4-bit bitmask
    // (15 = 0b1111, all of A/B/C/D) — exercises the offset+length+3-words layout.
    (
      [1, 15, 7],
      '26907087867892346381548911838475224144017244084761258444145995205971634838',
    ),
  ];

  group('surveyCommitment — Gate 2 cross-impl (Dart === ethers/Solidity)', () {
    for (final (answers, expected) in vectors) {
      test('answers=$answers matches the frozen ethers/Solidity literal', () {
        final got = surveyCommitment(answers.map(BigInt.from).toList());
        expect(got, BigInt.parse(expected), reason: 'answers=$answers');
      });
    }
  });

  group(
    'abiEncodeUint256Array — abi.encode layout (offset + length + words)',
    () {
      test('[2,5] preimage is exactly 4 words (offset, length, a0, a1)', () {
        final bytes = abiEncodeUint256Array([BigInt.from(2), BigInt.from(5)]);
        // 32 * (2 + n) = 32 * 4 = 128 bytes.
        expect(bytes.length, 128);
        expect(
          hex.encode(bytes),
          // word0 offset 0x20, word1 length 2, word2 = 2, word3 = 5 — the spec's
          // worked preimage, byte-for-byte (also what ethers prints).
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '0000000000000000000000000000000000000000000000000000000000000002'
          '0000000000000000000000000000000000000000000000000000000000000005',
        );
      });

      test('empty array is offset + zero length (2 words)', () {
        final bytes = abiEncodeUint256Array(const []);
        expect(bytes.length, 64);
        expect(
          hex.encode(bytes),
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000000',
        );
      });

      test('a large answer is left-padded big-endian into its 32-byte word', () {
        // 0xdeadbeef as the sole answer → length 1, word = right-aligned bytes.
        final bytes = abiEncodeUint256Array([BigInt.from(0xdeadbeef)]);
        expect(bytes.length, 96);
        expect(
          hex.encode(bytes),
          '0000000000000000000000000000000000000000000000000000000000000020'
          '0000000000000000000000000000000000000000000000000000000000000001'
          '00000000000000000000000000000000000000000000000000000000deadbeef',
        );
      });
    },
  );

  group('surveyCommitment — field-element sanity', () {
    // BN254 scalar field modulus r (~2^254). The >> 8 of a 256-bit digest is
    // always a 248-bit value, so the result is always a valid in-field signal.
    final bn254r = BigInt.parse(
      '21888242871839275222246405745257275088548364400416034343698204186575808495617',
    );

    test('result is > 0 and < BN254 r for the worked vector', () {
      final m = surveyCommitment([BigInt.from(2), BigInt.from(5)]);
      expect(m > BigInt.zero, isTrue);
      expect(m < bn254r, isTrue);
    });

    test('result is a 248-bit value (digest >> 8) for every frozen vector', () {
      for (final (answers, _) in vectors) {
        final m = surveyCommitment(answers.map(BigInt.from).toList());
        expect(m > BigInt.zero, isTrue, reason: 'answers=$answers');
        expect(m < bn254r, isTrue, reason: 'answers=$answers');
        // keccak digest is 256 bits → >> 8 ≤ 248 bits.
        expect(m.bitLength <= 248, isTrue, reason: 'answers=$answers');
      }
    });
  });
}
