import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/data/services/proximity_service.dart';
import 'package:tessera/data/services/proximity_service_factory.dart';

void main() {
  test('UnsupportedProximityService is an inert no-op', () async {
    const p = UnsupportedProximityService();
    expect(p.supported, isFalse);
    final r = await p.attest('beacon-uuid');
    expect(r.verified, isFalse);
    expect(r.method, 'none');
  });

  test('factory yields a no-op on this (radio-less) VM test host', () {
    final p = createProximityService();
    expect(p.supported, isFalse);
  });

  group('bleBeaconUuid — shared beacon id derived from the poll address', () {
    test('formats the first 128 bits of the address as a UUID', () {
      final id = bleBeaconUuid('0xd8058efe0198ae9dD7D563e1b4938Dcbc86A1F81');
      expect(id, 'd8058efe-0198-ae9d-d7d5-63e1b4938dcb');
    });

    test('is deterministic + case/0x-insensitive (org and voter agree)', () {
      expect(
        bleBeaconUuid('0xABCDEF0123456789abcdef0123456789ABCDEF01'),
        bleBeaconUuid('abcdef0123456789ABCDEF0123456789abcdef01'),
      );
    });

    test('short addresses pad to a full 128-bit UUID', () {
      expect(bleBeaconUuid('0x1234'), '12340000-0000-0000-0000-000000000000');
    });
  });
}
