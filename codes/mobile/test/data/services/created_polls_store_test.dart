import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/data/services/created_polls_store.dart';

void main() {
  group('InMemoryCreatedPollsStore', () {
    test(
      'add records it; all reflects it (lowercased, deduped by case)',
      () async {
        final s = InMemoryCreatedPollsStore();
        expect(await s.all(), isEmpty);
        await s.add('0xAbC0000000000000000000000000000000000123');
        await s.add('0xabc0000000000000000000000000000000000123'); // dup (case)
        await s.add('0xDef0000000000000000000000000000000000456');
        final all = await s.all();
        expect(all, hasLength(2));
        expect(all, contains('0xabc0000000000000000000000000000000000123'));
        expect(all, contains('0xdef0000000000000000000000000000000000456'));
      },
    );

    test('seeds from an initial iterable (lowercased)', () async {
      final s = InMemoryCreatedPollsStore(['0xAAA', '0xBBB']);
      expect(await s.all(), {'0xaaa', '0xbbb'});
    });

    test(
      'all() returns a copy — mutating it does not affect the store',
      () async {
        final s = InMemoryCreatedPollsStore(['0xaaa']);
        (await s.all()).add('0xbbb');
        expect(await s.all(), {'0xaaa'});
      },
    );
  });
}
