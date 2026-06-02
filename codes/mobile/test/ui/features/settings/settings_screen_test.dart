import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:tessera/ui/features/settings/settings_screen.dart';

Widget _host() => MaterialApp(
      home: Provider<ChainWriter>(
        create: (_) =>
            ChainWriter(rpcUrl: 'http://127.0.0.1:8545', chainId: 31337),
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
