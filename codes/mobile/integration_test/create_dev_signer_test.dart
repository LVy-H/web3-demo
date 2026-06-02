// On-device test for the dev-signer "Connect Wallet First" bypass: with
// DEV_PRIVATE_KEY set, Create deploys directly (no wallet) and the tx lands on
// the host Hardhat node.
//
// Run (stack must be up):
//   flutter test integration_test/create_dev_signer_test.dart -d linux \
//     --dart-define DEV_PRIVATE_KEY=0x59c6...690d \
//     --dart-define REGISTRY_ADDRESS=0x... --dart-define RPC_URL=http://127.0.0.1:8545
import 'package:flutter/material.dart' show NavigationDestination, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tessera/main.dart' as app;

Future<bool> pumpUntilFound(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 25)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dev-signer bypasses wallet: Create deploys directly',
      (tester) async {
    await app.main();
    await tester.pump(const Duration(seconds: 1));

    // Go to the Create tab.
    final createTab = find.descendant(
        of: find.byType(NavigationDestination), matching: find.text('CREATE'));
    expect(await pumpUntilFound(tester, find.text('CREATE')), isTrue);
    await tester.tap(createTab.first);
    await tester.pump(const Duration(seconds: 1));

    // The dev-signer is active → the wallet gate is replaced by a deploy button.
    expect(await pumpUntilFound(tester, find.text('DEPLOY POLL (DEV SIGNER)')),
        isTrue,
        reason: 'DEV_PRIVATE_KEY active should bypass "CONNECT WALLET FIRST"');
    expect(find.text('CONNECT WALLET FIRST'), findsNothing);
    expect(find.textContaining('Dev signer active'), findsWidgets);

    // Fill the title (options default to Yes/No) and deploy for real.
    await tester.enterText(find.byType(TextField).first, 'Dev Signer Poll');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('DEPLOY POLL (DEV SIGNER)'));

    // The tx is signed locally + broadcast; success shows the "Deploy sent"
    // snackbar (createAnonPoll returned a real hash).
    expect(await pumpUntilFound(tester, find.textContaining('Deploy sent')),
        isTrue,
        reason: 'the dev-signed createPoll landed on-chain');
  });
}
