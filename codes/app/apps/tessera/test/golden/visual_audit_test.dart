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

import 'package:design_system/theme.dart';
import 'package:design_system/widgets/results_bars.dart';
import 'package:feature_organize/feature_organize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

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
        shareLink:
            'https://tessera.vote/join#anon-vote='
            '0x5FbDB2315678afecb367f032d93F642f64180aa3',
        nfcAvailable: true,
        onShare: (_) async {},
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/distribute-sheet.png'),
    );
  });
}
