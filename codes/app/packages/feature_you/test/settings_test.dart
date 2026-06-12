// Settings (R3): network panel persists via NetworkConfigStore + fires the
// R2f capability re-probe hook; validation gates bad input; diagnostics
// reports probe results and honest proving copy.
import 'package:core_chain/config.dart';
import 'package:core_storage/network_config_store.dart';
import 'package:feature_you/feature_you.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkSettingsScreen', () {
    late InMemoryNetworkConfigStore store;
    late int reprobes;

    Future<void> pump(WidgetTester tester) async {
      reprobes = 0;
      // Tall surface so the whole (lazy) form ListView builds — the SAVE
      // button sits below a 600px fold.
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkSettingsScreen(
            store: store,
            onConfigChanged: () async => reprobes++,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() {
      store = InMemoryNetworkConfigStore();
    });

    Finder fieldWithText(String text) =>
        find.widgetWithText(TextFormField, text);

    testWidgets('save persists the edited config and triggers the re-probe', (
      tester,
    ) async {
      await pump(tester);

      // Fields are prefilled with the effective (default) config.
      await tester.enterText(
        fieldWithText(AppConfig.relayerUrl),
        'https://relayer.example',
      );
      await tester.tap(find.textContaining('SAVE'));
      await tester.pumpAndSettle();

      final saved = await store.load();
      expect(saved, isNotNull);
      expect(saved!.relayerUrl, 'https://relayer.example');
      expect(saved.rpcUrl, AppConfig.rpcUrl, reason: 'untouched field kept');
      expect(reprobes, 1, reason: 'capability re-probe hook must fire');
      expect(find.text('SAVED'), findsOneWidget);
      // Test host is not web → honest restart copy.
      expect(find.textContaining('Restart the app'), findsOneWidget);
    });

    testWidgets('invalid input never reaches the store', (tester) async {
      await pump(tester);

      await tester.enterText(fieldWithText(AppConfig.relayerUrl), 'not-a-url');
      await tester.tap(find.textContaining('SAVE'));
      await tester.pumpAndSettle();

      expect(find.text('http(s) URL required'), findsOneWidget);
      expect(await store.load(), isNull);
      expect(reprobes, 0);
    });

    testWidgets('reset clears the override and re-probes', (tester) async {
      store = InMemoryNetworkConfigStore(
        AppConfig.defaults.copyWith(relayerUrl: 'https://old.example'),
      );
      await pump(tester);

      await tester.tap(find.text('RESET TO DEFAULTS'));
      await tester.pumpAndSettle();

      expect(await store.load(), isNull);
      expect(reprobes, 1);
      expect(find.text('SAVED'), findsOneWidget);
    });

    testWidgets('a failing store resets the button and surfaces the error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkSettingsScreen(
            store: _ThrowingNetworkConfigStore(),
            onConfigChanged: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('SAVE'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not save'), findsOneWidget);
      expect(find.textContaining('SAVING…'), findsNothing, reason: 'no hang');
    });
  });

  group('DiagnosticsScreen', () {
    testWidgets('reports reachable chain and unreachable relayer honestly', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(
            checkChain: () async => true,
            checkRelayer: () async => false,
            canProve: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('REACHABLE'), findsOneWidget);
      expect(find.text('UNREACHABLE'), findsOneWidget);
      expect(find.textContaining('Not available'), findsOneWidget);
    });

    testWidgets('throwing probes degrade to unreachable, not a crash', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(
            checkChain: () async => throw StateError('boom'),
            checkRelayer: () async => true,
            canProve: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('UNREACHABLE'), findsOneWidget);
      expect(find.text('REACHABLE'), findsOneWidget);
    });
  });

  group('provingStatusCopy', () {
    test('honest per-platform copy', () {
      expect(
        provingStatusCopy(
          canProve: true,
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        contains('in this browser'),
      );
      expect(
        provingStatusCopy(
          canProve: false,
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        contains('iPhones and iPads'),
      );
      expect(
        provingStatusCopy(
          canProve: false,
          isWeb: false,
          platform: TargetPlatform.linux,
        ),
        contains('desktop builds'),
      );
      // The can't-prove copy must say what the device CAN still do (§4.3).
      expect(
        provingStatusCopy(
          canProve: false,
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        contains('check receipts'),
      );
    });
  });
}

class _ThrowingNetworkConfigStore implements NetworkConfigStore {
  @override
  Future<NetworkConfig?> load() async => null;
  @override
  Future<void> save(NetworkConfig config) async =>
      throw StateError('secure storage unavailable');
  @override
  Future<void> clear() async => throw StateError('secure storage unavailable');
}
