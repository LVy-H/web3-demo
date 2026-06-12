// JOIN surface (R3): the three entry modes (scan capability-gated, paste,
// type-code with auto-formatting), every parsed target routed through THE
// JoinTarget → location mapping (recorded via the navigate shim), and
// unrecognized input as a friendly INLINE error — never a navigation.
import 'package:core_storage/identity_store.dart';
import 'package:feature_join/feature_join.dart';
import 'package:feature_join/ui.dart'
    show kJoinEmptyClipboardCopy, kJoinUnrecognizedCopy;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tessera/capabilities/capability_prober.dart';
import 'package:tessera/routing/join_routing.dart';
import 'package:tessera/spaces/join_screen.dart';
import 'package:tessera/state/app_state.dart';

const addr = '0x1111111111111111111111111111111111111111';

/// AppState over a fully faked prober: canScanQr is the only knob these
/// tests turn (it derives from the platform — android scans, linux doesn't).
AppState appStateWith({required bool canScanQr}) => AppState(
  prober: CapabilityProber(
    checkRelayer: (_) async => false,
    proverAvailable: () => false,
    relayerUrl: () => 'http://relayer.test',
    hasDevSigner: () => false,
    walletConfigured: () => false,
    isWeb: false,
    platform: () => canScanQr ? TargetPlatform.android : TargetPlatform.linux,
  ),
  identityStore: InMemoryIdentityStore(),
);

Future<List<String>> pumpJoin(
  WidgetTester tester, {
  bool canScanQr = false,
  String? clipboard,
  String? scanResult,
}) async {
  final recorded = <String>[];
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appStateWith(canScanQr: canScanQr),
      child: MaterialApp(
        home: JoinScreen(
          navigateOverride: (_, location) => recorded.add(location),
          readClipboard: () async => clipboard,
          scanQr: (_) async => scanResult,
        ),
      ),
    ),
  );
  return recorded;
}

void main() {
  group('three entry modes', () {
    testWidgets('scan tile is HIDDEN when the device cannot scan', (
      tester,
    ) async {
      await pumpJoin(tester, canScanQr: false);
      expect(find.byKey(const Key('join-scan-tile')), findsNothing);
      // Paste and code stay — JOIN leads with what works (spec §4.3).
      expect(find.byKey(const Key('join-paste-tile')), findsOneWidget);
      expect(find.byKey(const Key('join-code-field')), findsOneWidget);
    });

    testWidgets('all three entries on a scanning device', (tester) async {
      await pumpJoin(tester, canScanQr: true);
      expect(find.byKey(const Key('join-scan-tile')), findsOneWidget);
      expect(find.byKey(const Key('join-paste-tile')), findsOneWidget);
      expect(find.byKey(const Key('join-code-field')), findsOneWidget);
    });

    testWidgets('a scanned QR routes through the mapping', (tester) async {
      final recorded = await pumpJoin(
        tester,
        canScanQr: true,
        scanResult: 'tessera://poll/$addr',
      );
      await tester.tap(find.byKey(const Key('join-scan-tile')));
      await tester.pump();
      expect(recorded, [locationForJoinTarget(const PollTarget(addr))]);
    });
  });

  group('paste → every JoinTarget type routes via locationForJoinTarget', () {
    Future<void> expectPasteRoutes(
      WidgetTester tester,
      String pasted,
      JoinTarget expected,
    ) async {
      final recorded = await pumpJoin(tester, clipboard: pasted);
      await tester.tap(find.byKey(const Key('join-paste-tile')));
      await tester.pump();
      expect(recorded, [locationForJoinTarget(expected)]);
      expect(find.byKey(const Key('join-inline-error')), findsNothing);
    }

    testWidgets('PollTarget', (tester) async {
      await expectPasteRoutes(
        tester,
        'https://app.tessera.vote/poll/$addr?module=ranked-vote',
        const PollTarget(addr, module: 'ranked-vote'),
      );
    });

    testWidgets('LiveVoteTarget (with ticket)', (tester) async {
      await expectPasteRoutes(
        tester,
        'tessera://live/$addr/vote?t=wire123',
        const LiveVoteTarget(addr, ticket: 'wire123'),
      );
    });

    testWidgets('LiveHostTarget', (tester) async {
      await expectPasteRoutes(
        tester,
        'tessera://live/$addr/host',
        const LiveHostTarget(addr),
      );
    });

    testWidgets('VerifyTarget', (tester) async {
      await expectPasteRoutes(
        tester,
        'tessera://verify?poll=$addr&nullifier=42',
        const VerifyTarget(poll: addr, nullifier: '42'),
      );
    });

    testWidgets('CodeTarget (a pasted code goes to /join/resolve)', (
      tester,
    ) async {
      await expectPasteRoutes(tester, 'tes-7q4mz2', const CodeTarget('7Q4MZ2'));
    });

    testWidgets('garbage is a friendly INLINE error, not a navigation', (
      tester,
    ) async {
      final recorded = await pumpJoin(tester, clipboard: 'lunch at noon?');
      await tester.tap(find.byKey(const Key('join-paste-tile')));
      await tester.pump();
      expect(recorded, isEmpty);
      expect(find.text(kJoinUnrecognizedCopy), findsOneWidget);
    });

    testWidgets('empty clipboard says copy-the-link-first', (tester) async {
      final recorded = await pumpJoin(tester, clipboard: null);
      await tester.tap(find.byKey(const Key('join-paste-tile')));
      await tester.pump();
      expect(recorded, isEmpty);
      expect(find.text(kJoinEmptyClipboardCopy), findsOneWidget);
    });
  });

  group('type-code entry: formatting + validation', () {
    final field = find.byKey(const Key('join-code-field'));
    final submit = find.byKey(const Key('join-code-submit'));

    testWidgets('uppercases, drops invalid symbols, caps at 6', (tester) async {
      await pumpJoin(tester);
      // 'u' is not a Crockford symbol; '!' is junk; the rest survives,
      // uppercased, truncated to 6.
      await tester.enterText(field, 'u7q!4mz2x');
      expect(find.text('7Q4MZ2'), findsOneWidget);
    });

    testWidgets('JOIN stays disabled until the code is whole', (tester) async {
      await pumpJoin(tester);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(field, '7Q4');
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(field, '7Q4MZ2');
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    });

    testWidgets('pasting a full canonical code drops the TES- prefix', (
      tester,
    ) async {
      await pumpJoin(tester);
      await tester.enterText(field, 'TES-ABC123');
      expect(find.text('ABC123'), findsOneWidget);
    });

    testWidgets(
      'submit routes the NORMALIZED code (aliases folded) via the mapping',
      (tester) async {
        final recorded = await pumpJoin(tester);
        await tester.enterText(field, 'oil123'); // O→0, I/L→1 on parse
        await tester.pump();
        await tester.tap(submit);
        await tester.pump();
        expect(recorded, [locationForJoinTarget(const CodeTarget('011123'))]);
      },
    );
  });
}
