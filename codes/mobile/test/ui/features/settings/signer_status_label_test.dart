import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/ui/features/settings/settings_screen.dart';

void main() {
  group('signerStatusLabel — resolves the active signing path', () {
    test('dev-signer present → "dev signer · <addr>"', () {
      final s = signerStatusLabel(
        canSign: true,
        signerAddress: '0x1234567890abcDEF1234567890abCDef12345678',
        sponsoredReady: false,
      );
      expect(s, startsWith('dev signer · '));
    });

    test('no dev-signer, probe still in flight → "…"', () {
      expect(
        signerStatusLabel(
          canSign: false,
          signerAddress: null,
          sponsoredReady: null,
        ),
        '…',
      );
    });

    test('no dev-signer, sponsored relayer reachable → wallet-free', () {
      expect(
        signerStatusLabel(
          canSign: false,
          signerAddress: null,
          sponsoredReady: true,
        ),
        'wallet-free (sponsored relayer)',
      );
    });

    test('no dev-signer, nothing reachable → honest wallet fallback', () {
      expect(
        signerStatusLabel(
          canSign: false,
          signerAddress: null,
          sponsoredReady: false,
        ),
        'wallet (connect to sign)',
      );
    });

    test('dev-signer takes priority over a reachable relayer', () {
      expect(
        signerStatusLabel(
          canSign: true,
          signerAddress: '0xabc',
          sponsoredReady: true,
        ),
        startsWith('dev signer · '),
      );
    });
  });
}
