import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/ui/features/settings/settings_screen.dart';

void main() {
  group('signerStatusLabel — resolves the active signing path', () {
    test('dev-signer present → "dev signer · <addr>"', () {
      final s = signerStatusLabel(
        canSign: true,
        signerAddress: '0x1234567890abcDEF1234567890abCDef12345678',
        sponsoredReady: false,
        walletConnected: false,
      );
      expect(s, startsWith('dev signer · '));
    });

    test('no dev-signer, probe still in flight → "…"', () {
      expect(
        signerStatusLabel(
          canSign: false,
          signerAddress: null,
          sponsoredReady: null,
          walletConnected: false,
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
          walletConnected: false,
        ),
        'wallet-free (sponsored relayer)',
      );
    });

    test(
      'no signer & no relayer, but a wallet IS connected → "wallet connected"',
      () {
        expect(
          signerStatusLabel(
            canSign: false,
            signerAddress: null,
            sponsoredReady: false,
            walletConnected: true,
          ),
          'wallet connected',
        );
      },
    );

    test(
      'nothing reachable and no wallet → honest "connect to sign" fallback',
      () {
        expect(
          signerStatusLabel(
            canSign: false,
            signerAddress: null,
            sponsoredReady: false,
            walletConnected: false,
          ),
          'wallet (connect to sign)',
        );
      },
    );

    test('dev-signer takes priority over a reachable relayer', () {
      expect(
        signerStatusLabel(
          canSign: true,
          signerAddress: '0xabc',
          sponsoredReady: true,
          walletConnected: true,
        ),
        startsWith('dev signer · '),
      );
    });

    test('sponsored relayer takes priority over a connected wallet', () {
      expect(
        signerStatusLabel(
          canSign: false,
          signerAddress: null,
          sponsoredReady: true,
          walletConnected: true,
        ),
        'wallet-free (sponsored relayer)',
      );
    });
  });
}
