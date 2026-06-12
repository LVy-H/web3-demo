// The wire packings must match the contracts exactly — pinned against the
// legacy helpers' documented examples.
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('packRanking', () {
    test('slot value is option+1, slot 0 most preferred', () {
      // [2, 0, 1] (C > A > B) → 0x213 = 531 (the documented example).
      expect(packRanking([2, 0, 1]), 531);
      expect(packRanking([0]), 1);
      expect(packRanking([]), 0);
    });

    test('rejects out-of-range and oversized rankings', () {
      expect(() => packRanking([8]), throwsArgumentError);
      expect(() => packRanking([-1]), throwsArgumentError);
      expect(
        () => packRanking([0, 1, 2, 3, 4, 5, 6, 7, 0]),
        throwsArgumentError,
      );
    });
  });

  group('packAlloc', () {
    test('direct 4-bit slots — NOT option+1', () {
      expect(packAlloc([6, 0, 8]), 0x806);
      expect(packAlloc([1]), 1);
      expect(packAlloc([0, 0, 15]), 0xF00);
    });

    test('rejects out-of-range votes', () {
      expect(() => packAlloc([16]), throwsArgumentError);
      expect(() => packAlloc([-1]), throwsArgumentError);
    });
  });
}
