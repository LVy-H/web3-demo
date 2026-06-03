import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/core/voting/quadratic_alloc.dart';

/// Vector tests for the packed-allocation codec + quadratic credit-cost helpers.
///
/// These mirror `ZkQuadraticVoting.sol` bit-for-bit. The encoding is DIRECT
/// (slot `i` ⇒ option `i`, NO `+1`) and `0` is a valid allocation — so the
/// round-trip vectors deliberately include INTERNAL zeros (e.g. `[6,0,8]`) that
/// would break a contiguous-prefix "stop at first zero" decoder.
void main() {
  group('packAlloc / unpackAlloc (direct 4-bit slots, spec table)', () {
    // 3-option poll [A, B, C]: slot 0=A, slot 1=B, slot 2=C, LSB-first.
    test('pack matches the spec packed-dec column', () {
      // (vA,vB,vC)=(10,0,0) → slots (s2 s1 s0)=`0 0 A` → 0x00A = 10
      expect(packAlloc([10, 0, 0]), 10);
      // (6,8,0) → `0 8 6` → 0x086 = 134
      expect(packAlloc([6, 8, 0]), 134);
      // (5,5,5) → `5 5 5` → 0x555 = 1365
      expect(packAlloc([5, 5, 5]), 1365);
      // (0,0,0) → 0x000 = 0 (the EmptyBallot value)
      expect(packAlloc([0, 0, 0]), 0);
    });

    test('unpack inverts pack for the spec rows', () {
      expect(unpackAlloc(10, 3), [10, 0, 0]);
      expect(unpackAlloc(134, 3), [6, 8, 0]);
      expect(unpackAlloc(1365, 3), [5, 5, 5]);
      expect(unpackAlloc(0, 3), [0, 0, 0]);
    });

    test(
      'round-trips allocations with INTERNAL zeros (no break-on-zero bug)',
      () {
        // The critical difference from the ranked codec: a 0 in the MIDDLE of
        // the vector is a valid allocation and must survive the round-trip. A
        // decoder that stopped at the first zero (the ranked contiguous-prefix
        // rule) would return [6] here instead of [6,0,8] — this asserts it
        // doesn't.
        for (final v in <List<int>>[
          [6, 0, 8],
          [0, 5, 0, 5],
          [0, 0, 7],
          [3, 0, 0, 4, 0],
          [1, 2, 3, 0, 0, 4, 0, 5], // full 8 slots with internal zeros
        ]) {
          final packed = packAlloc(v);
          expect(
            unpackAlloc(packed, v.length),
            v,
            reason: 'round-trip failed for $v (packed=$packed)',
          );
        }
      },
    );

    test('every slot value 0..15 round-trips in every slot position', () {
      for (var slot = 0; slot < kMaxQuadraticOptions; slot++) {
        for (var v = 0; v <= kMaxSlotVotes; v++) {
          final votes = List<int>.filled(kMaxQuadraticOptions, 0);
          votes[slot] = v;
          final packed = packAlloc(votes);
          expect(unpackAlloc(packed, kMaxQuadraticOptions)[slot], v);
        }
      }
    });

    test('packed allocation always stays under the 32-bit bound', () {
      final full = List<int>.filled(kMaxQuadraticOptions, kMaxSlotVotes);
      final packed = packAlloc(full); // all slots = 0xF
      expect(packed, kPackedAllocBound - 1); // 0xFFFFFFFF
      expect(packed < kPackedAllocBound, isTrue);
    });

    test('packAlloc rejects too many options', () {
      final tooMany = List<int>.filled(kMaxQuadraticOptions + 1, 1);
      expect(() => packAlloc(tooMany), throwsArgumentError);
    });

    test('packAlloc rejects out-of-range slot values', () {
      expect(() => packAlloc([16]), throwsArgumentError); // > 4-bit max
      expect(() => packAlloc([-1]), throwsArgumentError);
    });
  });

  group('creditsSpent = Σ vᵢ² (boundary vectors)', () {
    test('[10] → 100 (exactly CREDITS, valid)', () {
      expect(creditsSpent([10]), 100);
      expect(creditsSpent([10]) <= kQuadraticCredits, isTrue);
    });

    test('[6,8] → 36+64 = 100 (exactly CREDITS, valid)', () {
      expect(creditsSpent([6, 8]), 100);
      expect(creditsSpent([6, 8]) <= kQuadraticCredits, isTrue);
    });

    test('[10,1] → 101 (OverBudget — would be rejected on-chain)', () {
      expect(creditsSpent([10, 1]), 101);
      expect(creditsSpent([10, 1]) > kQuadraticCredits, isTrue);
    });

    test('[11] → 121 (single over-budget option)', () {
      expect(creditsSpent([11]), 121);
      expect(creditsSpent([11]) > kQuadraticCredits, isTrue);
    });

    test('[5,5,5] → 75 (within budget)', () {
      expect(creditsSpent([5, 5, 5]), 75);
    });

    test('internal zeros do not add cost', () {
      expect(creditsSpent([6, 0, 8]), 100); // 36 + 0 + 64
    });
  });

  group('totalVotes = Σ vᵢ (empty-ballot detection)', () {
    test('all-zero allocation has zero total votes (EmptyBallot)', () {
      expect(totalVotes([0, 0, 0]), 0);
    });

    test('any nonzero slot makes the ballot non-empty', () {
      expect(totalVotes([0, 1, 0]), 1);
      expect(totalVotes([10, 0, 0]), 10);
      expect(totalVotes([6, 8, 0]), 14);
    });
  });

  group('mirrors of the contract constants', () {
    test('CREDITS, MAX_OPTIONS, and the packed bound match the contract', () {
      expect(kQuadraticCredits, 100);
      expect(kMaxQuadraticOptions, 8);
      expect(kMaxSlotVotes, 15);
      expect(kPackedAllocBound, 1 << 32);
    });
  });
}
