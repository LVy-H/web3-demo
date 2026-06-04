import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tessera/config.dart';
import 'package:tessera/data/services/network_config_store.dart';
import 'package:tessera/ui/features/settings/network_config_screen.dart';

Widget _host(NetworkConfigStore store) => MaterialApp(
  home: Provider<NetworkConfigStore>.value(
    value: store,
    child: const NetworkConfigScreen(),
  ),
);

/// The form is a tall ListView; give it a surface big enough to build + show
/// every field and both buttons (otherwise lazy children below the fold aren't
/// built and can't be found or tapped).
void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  tearDown(() => AppConfig.apply(null));

  testWidgets('renders the form prefilled with the effective config', (
    tester,
  ) async {
    _tallSurface(tester);
    await tester.pumpWidget(_host(InMemoryNetworkConfigStore()));
    await tester.pumpAndSettle();

    expect(find.text('NETWORK'), findsOneWidget);
    expect(find.text('RPC URL'), findsOneWidget);
    expect(find.text('RELAYER URL'), findsOneWidget);
    expect(find.text('CHAIN ID'), findsOneWidget);
    // Prefilled from the compile-time defaults.
    expect(find.text(AppConfig.defaults.rpcUrl), findsOneWidget);
    expect(find.text('${AppConfig.defaults.chainId}'), findsOneWidget);
  });

  testWidgets('saving the (valid) defaults persists + shows the apply dialog', (
    tester,
  ) async {
    _tallSurface(tester);
    final store = InMemoryNetworkConfigStore();
    await tester.pumpWidget(_host(store));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('SAVE'));
    await tester.pumpAndSettle();

    expect(await store.load(), isNotNull);
    expect(find.text('SAVED'), findsOneWidget);
  });

  testWidgets('invalid input blocks the save (no write, error shown)', (
    tester,
  ) async {
    _tallSurface(tester);
    final store = InMemoryNetworkConfigStore();
    await tester.pumpWidget(_host(store));
    await tester.pumpAndSettle();

    // Field 0 is the RPC URL. Make it invalid, then try to save.
    await tester.enterText(find.byType(TextFormField).first, 'notaurl');
    await tester.tap(find.textContaining('SAVE'));
    await tester.pumpAndSettle();

    expect(find.text('http(s) URL required'), findsOneWidget);
    expect(await store.load(), isNull); // never persisted
    expect(find.text('SAVED'), findsNothing);
  });

  testWidgets('reset clears the stored override', (tester) async {
    _tallSurface(tester);
    final store = InMemoryNetworkConfigStore(
      const NetworkConfig(
        rpcUrl: 'https://x.example',
        relayerUrl: 'https://y.example',
        registryAddress: '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
        semaphoreAddress: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
        chainId: 5,
      ),
    );
    await tester.pumpWidget(_host(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('RESET TO DEFAULTS'));
    await tester.pumpAndSettle();

    expect(await store.load(), isNull);
    expect(find.text('SAVED'), findsOneWidget);
  });
}
