import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:tessera/data/services/relay_client.dart';
import 'package:tessera/data/services/wallet_service.dart';
import 'package:tessera/ui/features/settings/settings_screen.dart';

Widget _host() => MaterialApp(
  home: MultiProvider(
    providers: [
      Provider<ChainWriter>(
        create: (_) =>
            ChainWriter(rpcUrl: 'http://127.0.0.1:8545', chainId: 31337),
      ),
      // No registry in the relayer's /info response → the signer resolves to
      // the honest 'wallet (connect to sign)' fallback (no dev key, no wallet).
      Provider<RelayClient>(
        create: (_) => RelayClient(
          baseUrl: 'http://relayer.test',
          client: MockClient((_) async => http.Response('{}', 503)),
        ),
      ),
      ChangeNotifierProvider<WalletService>(
        create: (_) => WalletService(registryAbiJson: '[]', anonAbiJson: '[]'),
      ),
    ],
    child: const SettingsScreen(),
  ),
);

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Tessera',
      packageName: 'tessera',
      version: '0.2.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('renders the diagnostics sections + version', (tester) async {
    // Tall surface so every section (incl. ABOUT at the bottom) is built — the
    // ListView lazily builds only visible children, and the screen is now taller
    // than the default 800×600 (overflow-at-narrow-width is covered separately
    // in narrow_overflow_test).
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('NETWORK'), findsOneWidget);
    expect(find.text('SIGNING & PROVING'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.text('Tessera'), findsOneWidget);
    expect(find.text('0.2.0+1'), findsOneWidget); // version+build
    // No dev key configured in the test → wallet signer.
    expect(find.textContaining('wallet'), findsOneWidget);
  });
}
