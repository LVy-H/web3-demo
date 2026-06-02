import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/data/services/proximity_service.dart';

void main() {
  test('UnsupportedProximityService is an inert no-op', () async {
    const p = UnsupportedProximityService();
    expect(p.supported, isFalse);
    final r = await p.attest('beacon-uuid');
    expect(r.verified, isFalse);
    expect(r.method, 'none');
  });

  test('factory yields a no-op on this (radio-less) platform', () {
    final p = createProximityService();
    expect(p.supported, isFalse);
  });
}
