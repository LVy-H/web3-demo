import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/data/services/identity_store.dart';

void main() {
  group('generateIdentitySeed', () {
    test('returns 0x + 64 lowercase hex chars', () {
      expect(generateIdentitySeed(), matches(RegExp(r'^0x[0-9a-f]{64}$')));
    });

    test('is unique across calls', () {
      expect(generateIdentitySeed(), isNot(generateIdentitySeed()));
    });
  });

  group('InMemoryIdentityStore', () {
    test('read is null before any write', () async {
      expect(await InMemoryIdentityStore().read(), isNull);
    });

    test('write then read round-trips; delete clears', () async {
      final store = InMemoryIdentityStore();
      await store.write('0xabc');
      expect(await store.read(), '0xabc');
      await store.delete();
      expect(await store.read(), isNull);
    });
  });
}
