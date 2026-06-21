import 'package:core_crypto/crypto/idempotency_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('is deterministic for the same (seed, decision)', () {
    final a = ballotIdempotencyKey(identitySeed: 's', decisionId: 'd');
    final b = ballotIdempotencyKey(identitySeed: 's', decisionId: 'd');
    expect(a, b);
    expect(a.length, 64); // SHA-256 hex
  });

  test('differs across seeds and across decisions', () {
    final base = ballotIdempotencyKey(identitySeed: 's1', decisionId: 'd1');
    expect(
      ballotIdempotencyKey(identitySeed: 's2', decisionId: 'd1'),
      isNot(base),
    );
    expect(
      ballotIdempotencyKey(identitySeed: 's1', decisionId: 'd2'),
      isNot(base),
    );
  });

  test('the space separator avoids a concatenation collision', () {
    // ('ab', 'c') must not collide with ('a', 'b c') or ('a b', 'c').
    final k1 = ballotIdempotencyKey(identitySeed: 'ab', decisionId: 'c');
    final k2 = ballotIdempotencyKey(identitySeed: 'a', decisionId: 'b c');
    expect(k1, isNot(k2));
  });
}
