import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/ui/core/signing_explainer.dart';

void main() {
  testWidgets(
    'signing explainer leads with wallet-free and lists three paths',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showSigningExplainerSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Leads with the reassurance.
      expect(find.text("You don't need a wallet."), findsOneWidget);
      // All three paths are present, with the sponsored one tagged DEFAULT.
      expect(find.text('Wallet-free (sponsored relayer)'), findsOneWidget);
      expect(find.text('Local dev-signer'), findsOneWidget);
      expect(find.text('Connect a wallet'), findsOneWidget);
      expect(find.text('DEFAULT'), findsOneWidget);
    },
  );
}
