import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/data/services/nfc_service.dart';
import 'package:tessera/data/services/nfc_service_factory.dart';

void main() {
  group('UnsupportedNfcService — the no-op baseline', () {
    test(
      'never available; write returns unsupported; cancel never throws',
      () async {
        const s = UnsupportedNfcService();
        expect(await s.isAvailable(), isFalse);
        final r = await s.writeUrl('tessera://poll/0x1?module=anon-vote');
        expect(r.ok, isFalse);
        expect(r.error, isNotNull);
        await s.cancel(); // no throw
      },
    );
  });

  test('createNfcService is a no-op on the non-Android VM test host', () async {
    // The VM test runs the dart:io branch; the host is not Android, so the
    // factory returns the no-op without touching the NFC radio/plugin.
    final s = createNfcService();
    expect(await s.isAvailable(), isFalse);
  });
}
