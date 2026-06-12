// Voting pass flows (R3): create / import / backup / remove against a fake
// store, the AppState-notification contract (the injected onPassChanged
// callback), the advanced registration-code panel, and the jargon ban.
import 'package:core_storage/identity_store.dart';
import 'package:feature_you/feature_you.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryIdentityStore store;
  late int passChangedCalls;
  String? passwordAtNotify; // store contents AT notification time

  VotingPassController buildController({
    RegistrationCodeDeriver? deriveRegistrationCode,
  }) {
    passChangedCalls = 0;
    passwordAtNotify = null;
    return VotingPassController(
      store: store,
      onPassChanged: () async {
        passChangedCalls++;
        passwordAtNotify = await store.read();
      },
      deriveRegistrationCode: deriveRegistrationCode,
    );
  }

  Future<VotingPassController> pump(
    WidgetTester tester, {
    RegistrationCodeDeriver? deriveRegistrationCode,
  }) async {
    final controller = buildController(
      deriveRegistrationCode: deriveRegistrationCode,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VotingPassSection(controller: controller),
          ),
        ),
      ),
    );
    await controller.load();
    await tester.pumpAndSettle();
    return controller;
  }

  setUp(() {
    store = InMemoryIdentityStore();
  });

  testWidgets('no pass → CREATE PASS stores a seed and notifies AppState', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('No pass yet'), findsOneWidget);

    await tester.tap(find.text('CREATE PASS'));
    await tester.pumpAndSettle();

    final seed = await store.read();
    expect(seed, isNotNull);
    expect(seed, startsWith('0x'));
    expect(seed!.length, 66, reason: '32-byte hex seed');
    expect(passChangedCalls, 1, reason: 'AppState must be notified');
    expect(
      passwordAtNotify,
      seed,
      reason: 'notification fires AFTER the seed is persisted',
    );
    expect(find.text('Active on this device'), findsOneWidget);
  });

  testWidgets('import flow stores the pasted pass and notifies', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('IMPORT A PASS'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0xfeed');
    await tester.tap(find.text('IMPORT'));
    await tester.pumpAndSettle();

    expect(await store.read(), '0xfeed');
    expect(passChangedCalls, 1);
    expect(find.text('Active on this device'), findsOneWidget);
  });

  testWidgets('import with blank input shows an error and does not notify', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('IMPORT A PASS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IMPORT'));
    await tester.pumpAndSettle();

    expect(find.text('Paste your pass first.'), findsOneWidget);
    expect(await store.read(), isNull);
    expect(passChangedCalls, 0);
  });

  testWidgets('backup reveals the pass with the password warning', (
    tester,
  ) async {
    store = InMemoryIdentityStore('0xdeadbeef');
    await pump(tester);
    expect(find.text('Active on this device'), findsOneWidget);
    // Hidden until the user opens the backup panel.
    expect(find.text('0xdeadbeef'), findsNothing);

    await tester.tap(find.text('BACK UP PASS'));
    await tester.pumpAndSettle();

    expect(find.text('0xdeadbeef'), findsOneWidget);
    expect(find.textContaining('Treat this like a password'), findsOneWidget);
    expect(find.text('COPY'), findsOneWidget);
  });

  testWidgets('remove flow confirms, clears the store and notifies', (
    tester,
  ) async {
    store = InMemoryIdentityStore('0xdeadbeef');
    await pump(tester);

    await tester.tap(find.text('REMOVE FROM THIS DEVICE'));
    await tester.pumpAndSettle();
    expect(find.text('REMOVE PASS?'), findsOneWidget);

    await tester.tap(find.text('REMOVE'));
    await tester.pumpAndSettle();

    expect(await store.read(), isNull);
    expect(passChangedCalls, 1);
    expect(find.text('No pass yet'), findsOneWidget);
  });

  testWidgets('advanced panel derives and shows the registration code with the '
      'give-to-an-organizer copy', (tester) async {
    store = InMemoryIdentityStore('0xdeadbeef');
    String? derivedFor;
    await pump(
      tester,
      deriveRegistrationCode: (seed) async {
        derivedFor = seed;
        return '424242424242';
      },
    );

    await tester.tap(find.text('ADVANCED'));
    await tester.pumpAndSettle();

    expect(derivedFor, '0xdeadbeef');
    expect(find.text('REGISTRATION CODE'), findsOneWidget);
    expect(find.text('424242424242'), findsOneWidget);
    expect(find.textContaining('Give this to an organizer'), findsOneWidget);
  });

  testWidgets('advanced panel is honest when no prover exists', (tester) async {
    store = InMemoryIdentityStore('0xdeadbeef');
    await pump(tester); // no deriver

    await tester.tap(find.text('ADVANCED'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Not available on this device yet'),
      findsOneWidget,
    );
  });

  testWidgets('primary copy never says Semaphore / commitment / nullifier', (
    tester,
  ) async {
    store = InMemoryIdentityStore('0xdeadbeef');
    await pump(tester, deriveRegistrationCode: (_) async => '42');
    // Open everything — the ban covers the whole surface.
    await tester.tap(find.text('BACK UP PASS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ADVANCED'));
    await tester.pumpAndSettle();

    for (final banned in ['Semaphore', 'commitment', 'nullifier', 'identity']) {
      expect(
        find.textContaining(banned),
        findsNothing,
        reason: '"$banned" is jargon (spec §3 principle 5)',
      );
    }
  });
}
