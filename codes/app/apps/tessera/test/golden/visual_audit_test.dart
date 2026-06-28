// HEADLESS VISUAL-AUDIT HARNESS — render-time regression catcher.
//
// WHY THIS EXISTS
// ----------------
// Logic tests, `dart analyze`, and CI never look at pixels. This harness
// renders real UI surfaces to PNG goldens so a human or agent can OPEN the
// files and eyeball overflow, contrast, and spacing — the regressions the
// rest of the gate is blind to. It caught a sub-WCAG-AA contrast issue once;
// keeping it committed makes that catch repeatable and discoverable.
//
// IT MUST NEVER GATE CI
// ----------------------
// Golden pixels are platform-/engine-dependent (font hinting, rasterizer),
// so these tests are tagged `golden` and EXCLUDED from the default test run
// (`melos test` appends `--exclude-tags golden`). They run only on demand via
// `melos test:golden`. The generated PNGs are git-ignored — regenerate them
// locally; never commit them and never assert on them in CI.
//
// HOW TO RUN (from codes/app/)
// -----------------------------
//   # (Re)generate the PNGs, then open them to inspect:
//   cd apps/tessera && flutter test --update-goldens --tags golden \
//       test/golden/visual_audit_test.dart
//   # PNGs land in apps/tessera/test/golden/goldens/*.png — open them.
//
//   # Or via melos, from codes/app/:
//   dart run melos test:golden            # runs the tagged goldens
//
// After an intentional UI change, re-run with --update-goldens and re-inspect
// the PNGs. Without --update-goldens the tests COMPARE against whatever PNGs
// exist locally (and may fail on a different platform — that is expected and
// is exactly why they never gate CI).
@Tags(['golden'])
library;

import 'package:core_chain/chain_reader.dart';
import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/voter_journey.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/created_polls_store.dart';
import 'package:design_system/theme.dart';
import 'package:design_system/widgets/results_bars.dart';
import 'package:feature_organize/feature_organize.dart';
import 'package:feature_vote/feature_vote.dart';
import 'package:feature_you/feature_you.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

// ── Walkthrough fakes ──────────────────────────────────────────────────────
// The README's hero walkthrough (create → vote → results → verify) renders the
// REAL production screens. The organizer create-flow needs an OrganizerJourney
// port; we feed it the same faked wire deps the create-flow widget test uses,
// so what renders is the genuine form, not a mock.
const _relayerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
const _pollAddress = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
const _flatAbi =
    '[{"type":"function","name":"initialize","stateMutability":"nonpayable",'
    '"inputs":[{"name":"semaphore","type":"address"},'
    '{"name":"_owner","type":"address"},'
    '{"name":"options","type":"string[]"}],"outputs":[]}]';

class _FakeRelay implements RelayClient {
  @override
  Future<RelayerInfo?> getRelayerInfo() async =>
      const RelayerInfo(relayer: _relayerAddress);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('RelayClient.${invocation.memberName}');
}

class _FakeReader implements ChainReader {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ChainReader.${invocation.memberName}');
}

class _StubGateway implements OrganizeRelayGateway {
  @override
  Future<CreatePollResult> createPoll({
    required String moduleType,
    required String title,
    required String description,
    required String initDataHex,
    required int visibility,
    required int resultsPolicy,
  }) async => const CreatePollResult(pollAddress: _pollAddress);
  @override
  Future<void> startVoting(String pollAddress) async {}
  @override
  Future<void> endVoting(String pollAddress) async {}
}

const _sponsoredOnly = Capabilities(
  canProve: false,
  canSign: false,
  canScanQr: false,
  hasNfc: false,
  hasBle: false,
  canUseWallet: false,
  relayerAvailable: true,
);

void main() {
  // Load the REAL bundled fonts so the goldens render with Inter +
  // JetBrains Mono (their actual metrics), not the test runner's blank
  // Ahem-style fallback. Without this, contrast/overflow checks would be
  // measured against the wrong glyphs.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader(
      'JetBrainsMono',
    )..addFont(rootBundle.load('assets/fonts/JetBrainsMono.ttf'))).load();
  });

  // Deterministic surface: fixed logical size at devicePixelRatio 1, reset
  // after each test so one surface can't leak its geometry into the next.
  void setSurface(
    WidgetTester tester, {
    required double width,
    double height = 800,
  }) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
  }

  tearDown(() {
    // `tester` isn't in scope here; reset via the binding's primary view.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  // Every surface goes through the real Dark Bauhaus theme on a void
  // scaffold, sized to the deterministic surface so the golden is stable.
  Future<void> pumpSurface(
    WidgetTester tester, {
    required Widget child,
    double width = 390,
    double height = 800,
    Color background = Db.void_,
  }) async {
    setSurface(tester, width: width, height: height);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildDarkBauhausTheme(),
        home: Scaffold(
          backgroundColor: background,
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ── contrast-swatch ─────────────────────────────────────────────────────
  // Every Db text color (sans + mono) on the page void AND on a slate2 panel,
  // so an agent can eyeball whether the dim tones still clear WCAG AA on the
  // surfaces they actually sit on. This is the surface that once exposed
  // sub-AA contrast.
  testWidgets('contrast-swatch', (tester) async {
    const samples = <(String, Color)>[
      ('chalk', Db.chalk),
      ('chalkDim', Db.chalkDim),
      ('mute', Db.mute),
      ('muteDim', Db.muteDim),
      ('segnale', Db.segnale),
      ('amber', Db.amber),
    ];

    Widget swatchColumn(Color bg, String surfaceLabel) => Container(
      width: 320,
      color: bg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(surfaceLabel, style: dbLabel(size: 11, color: Db.mute)),
          const SizedBox(height: 12),
          for (final (label, color) in samples) ...[
            Text('$label — sans Aa 0123', style: dbSans(15, 600, color)),
            const SizedBox(height: 2),
            Text('$label — mono Aa 0123', style: dbMono(13, color)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );

    await pumpSurface(
      tester,
      width: 720,
      height: 640,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          swatchColumn(Db.void_, 'ON Db.void_'),
          const SizedBox(width: 16),
          swatchColumn(Db.slate2, 'ON Db.slate2 PANEL'),
        ],
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/contrast-swatch.png'),
    );
  });

  // ── results-bars (typical tally) ────────────────────────────────────────
  testWidgets('results-bars', (tester) async {
    final options = <ResultOption>[
      (label: 'Approve the treasury grant', count: BigInt.from(128)),
      (label: 'Reject', count: BigInt.from(74)),
      (label: 'Abstain', count: BigInt.from(31)),
    ];
    await pumpSurface(
      tester,
      width: 390,
      height: 360,
      child: ResultsBars(options: options),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/results-bars.png'),
    );
  });

  // ── results-bars-long (overflow check: very long labels) ────────────────
  testWidgets('results-bars-long', (tester) async {
    final options = <ResultOption>[
      (
        label:
            'Ratify the multi-year community treasury endowment and delegate '
            'spending authority to the elected stewards council',
        count: BigInt.from(9001),
      ),
      (
        label:
            'Reject the proposal in its entirety and re-open the discussion '
            'period for another two full governance cycles',
        count: BigInt.parse('123456789012345678901234567890'),
      ),
    ];
    await pumpSurface(
      tester,
      width: 390,
      height: 320,
      child: ResultsBars(options: options),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/results-bars-long.png'),
    );
  });

  // ── results-bars-xl-textscale (large-font overflow at narrow width) ──────
  testWidgets('results-bars-xl-textscale', (tester) async {
    final options = <ResultOption>[
      (label: 'Approve the treasury grant', count: BigInt.from(128)),
      (label: 'Reject', count: BigInt.from(74)),
    ];
    await pumpSurface(
      tester,
      width: 340,
      height: 480,
      child: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: ResultsBars(options: options),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/results-bars-xl-textscale.png'),
    );
  });

  // ── distribute-sheet ────────────────────────────────────────────────────
  // DistributeSheet imports cleanly via the feature_organize barrel and
  // renders without a provider tree once we inject a no-op share action
  // (so the real share_plus method channel is never touched under
  // `flutter test`).
  testWidgets('distribute-sheet', (tester) async {
    await pumpSurface(
      tester,
      width: 390,
      height: 760,
      background:
          Db.slate, // the sheet's real backdrop (see DistributeSheet.show)
      child: DistributeSheet(
        // Production-faithful: the real shareLinkForPoll() format, and
        // nfcAvailable=false — the capability `hasNfc` is permanently false, so
        // the NFC tile never renders in production (rendering it true would show
        // a dead state and mislead the inspector).
        shareLink:
            'tessera://poll/0x5FbDB2315678afecb367f032d93F642f64180aa3'
            '?module=anon-vote',
        nfcAvailable: false,
        onShare: (_) async {},
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/distribute-sheet.png'),
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // README WALKTHROUGH — create → vote → results → verify, all real screens.
  // ════════════════════════════════════════════════════════════════════════

  // ── walk-create (organizer) ──────────────────────────────────────────────
  // The genuine CreateFlowView draft form, driven by the OrganizerJourney
  // machine over faked wire deps, pre-filled like a real first decision.
  testWidgets('walk-create', (tester) async {
    final port = RelayOrganizerPort(
      relay: _FakeRelay(),
      reader: _FakeReader(),
      gateway: _StubGateway(),
      createdPolls: InMemoryCreatedPollsStore(),
      flatModuleAbiJson: _flatAbi,
      surveyVotingAbiJson: _flatAbi,
    );
    tester.view.physicalSize = const Size(390, 1450);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildDarkBauhausTheme(),
        home: CreateFlowView(
          port: port,
          capabilities: _sponsoredOnly,
          onDone: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(CreateFlowView.titleFieldKey),
      'Approve the treasury grant?',
    );
    await tester.enterText(find.byKey(const Key('create-option-0')), 'Approve');
    await tester.enterText(find.byKey(const Key('create-option-1')), 'Reject');
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/walk-create.png'),
    );
  });

  // ── walk-ballot (voter) ──────────────────────────────────────────────────
  // The real VOTE chrome (phase strip + pick-one ballot tiles) plus the
  // enabled cast button, exactly as the voter sees it mid-decision.
  testWidgets('walk-ballot', (tester) async {
    await pumpSurface(
      tester,
      width: 390,
      height: 470,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PhaseStrip(phase: 1),
          const SizedBox(height: 20),
          Text('Approve the treasury grant?', style: dbSans(20, 800, Db.chalk)),
          const SizedBox(height: 6),
          Text(
            'Pick one. Your vote is private — only the tally is public.',
            style: dbMono(11, Db.mute, height: 1.5),
          ),
          const SizedBox(height: 18),
          SingleChoiceBallot(
            options: const ['Approve the treasury grant', 'Reject', 'Abstain'],
            onChanged: (_) {},
            initial: const SingleChoice(0),
          ),
          const SizedBox(height: 6),
          // Faithful enabled cast button — mirrors PrimaryActionButton's
          // enabled branch (segnale fill, void label) without needing a live
          // NextAction from the machine.
          Container(
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Db.segnale,
              border: Border.fromBorderSide(BorderSide(color: Db.segnale)),
            ),
            child: Text(
              'CAST VOTE',
              style: dbSans(13, 800, Db.void_, letterSpacing: 1.2),
            ),
          ),
        ],
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/walk-ballot.png'),
    );
  });

  // ── walk-receipt (voter) ─────────────────────────────────────────────────
  // The real ReceiptPanel: the private, verifiable receipt a voter keeps.
  testWidgets('walk-receipt', (tester) async {
    await pumpSurface(
      tester,
      width: 390,
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PhaseStrip(phase: 2),
          const SizedBox(height: 20),
          const ReceiptPanel(code: '8462190375516024873190462285517043'),
        ],
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/walk-receipt.png'),
    );
  });

  // ── walk-verify (anyone) ─────────────────────────────────────────────────
  // The real VerifyView with a counted receipt auto-checked — the
  // "was my vote counted?" answer anyone can run, no voting pass needed.
  testWidgets('walk-verify', (tester) async {
    setSurface(tester, width: 390, height: 820);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildDarkBauhausTheme(),
        home: VerifyView(
          checkReceipt: (_, _) async => true,
          lookupPollTitle: (_) async => 'Approve the treasury grant?',
          initialPollAddress: _pollAddress,
          initialReceiptCode: '8462190375516024873190462285517043',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/walk-verify.png'),
    );
  });
}
