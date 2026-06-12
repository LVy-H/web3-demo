import 'package:feature_you/feature_you.dart';
import 'package:flutter_test/flutter_test.dart';

VoteReceipt receipt(
  String poll,
  String code, {
  String title = 'Club budget',
  int savedAtMs = 1000,
}) => VoteReceipt(
  pollAddress: poll,
  pollTitle: title,
  receiptCode: code,
  savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs),
);

void main() {
  group('VoteReceipt encode/decode', () {
    test('round-trips a list', () {
      final encoded = VoteReceipt.encodeList([
        receipt('0xAAA', '123', savedAtMs: 42),
        receipt('0xBBB', '456', title: '', savedAtMs: 7),
      ]);
      final decoded = VoteReceipt.decodeList(encoded);
      expect(decoded, hasLength(2));
      expect(decoded[0].pollAddress, '0xAAA');
      expect(decoded[0].pollTitle, 'Club budget');
      expect(decoded[0].receiptCode, '123');
      expect(decoded[0].savedAt.millisecondsSinceEpoch, 42);
      expect(decoded[1].pollTitle, '');
    });

    test('null / empty / corrupt blobs decode to an empty list', () {
      expect(VoteReceipt.decodeList(null), isEmpty);
      expect(VoteReceipt.decodeList(''), isEmpty);
      expect(VoteReceipt.decodeList('not json'), isEmpty);
      expect(VoteReceipt.decodeList('{"a":1}'), isEmpty);
    });

    test('malformed entries are skipped, valid ones survive', () {
      const blob =
          '[{"poll":"0xAAA","code":"1","title":"t","savedAt":5},'
          '{"poll":"","code":"2"},'
          '{"nope":true},'
          '{"poll":"0xBBB","code":"3"}]';
      final decoded = VoteReceipt.decodeList(blob);
      expect(decoded.map((r) => r.receiptCode), ['1', '3']);
    });
  });

  group('InMemoryReceiptsStore', () {
    test('save inserts newest first and upserts on (poll, code)', () async {
      final store = InMemoryReceiptsStore();
      await store.save(receipt('0xAAA', '1'));
      await store.save(receipt('0xBBB', '2'));
      // Same poll+code (case-insensitive address) replaces, moves to front.
      await store.save(receipt('0xaaa', '1', title: 'Updated'));

      final all = await store.loadAll();
      expect(all, hasLength(2));
      expect(all.first.pollTitle, 'Updated');
      expect(all.last.receiptCode, '2');
    });

    test('remove and clear', () async {
      final store = InMemoryReceiptsStore([
        receipt('0xAAA', '1'),
        receipt('0xBBB', '2'),
      ]);
      await store.remove('0xaaa', '1');
      expect((await store.loadAll()).single.receiptCode, '2');
      await store.clear();
      expect(await store.loadAll(), isEmpty);
    });
  });
}
