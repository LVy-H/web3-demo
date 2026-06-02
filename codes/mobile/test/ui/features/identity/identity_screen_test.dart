import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tessera/data/services/identity_store.dart';
import 'package:tessera/ui/features/identity/identity_screen.dart';
import 'package:tessera/ui/features/identity/identity_view_model.dart';

Widget _host(IdentityStore store) => ChangeNotifierProvider(
      create: (_) => IdentityViewModel(store)..load(),
      child: const MaterialApp(home: IdentityScreen()),
    );

void main() {
  testWidgets('empty store renders the hero + "No identity yet"',
      (tester) async {
    await tester.pumpWidget(_host(InMemoryIdentityStore()));
    await tester.pumpAndSettle();

    expect(find.text('IDENTITY'), findsOneWidget);
    expect(find.text('No identity yet'), findsOneWidget);
    expect(find.text('CREATE NEW IDENTITY'), findsOneWidget);
    expect(find.text('SEED'), findsNothing);
  });

  testWidgets('creating an identity reveals the seed panel', (tester) async {
    await tester.pumpWidget(_host(InMemoryIdentityStore()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CREATE NEW IDENTITY'));
    await tester.pumpAndSettle();

    expect(find.text('Identity ready'), findsOneWidget);
    expect(find.text('SEED'), findsOneWidget);
    expect(find.text('REVEAL'), findsOneWidget);
    expect(find.text('CLEAR IDENTITY'), findsOneWidget);
  });

  testWidgets('an existing seed loads straight into the ready state',
      (tester) async {
    await tester.pumpWidget(_host(InMemoryIdentityStore('0xfeed')));
    await tester.pumpAndSettle();

    expect(find.text('Identity ready'), findsOneWidget);
    expect(find.text('SEED'), findsOneWidget);
  });
}
