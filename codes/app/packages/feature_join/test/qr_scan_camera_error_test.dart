// The QR scanner's camera-denied / no-camera fallback: instead of a black or
// blank scanner (or a crash), the user sees a clear Dark-Bauhaus message that
// routes them to the always-available paste/code path. This pumps that panel
// in isolation — no real camera, no plugin channel — by constructing the
// MobileScannerException the scanner's errorBuilder hands us.
import 'package:flutter_test/flutter_test.dart';
import 'package:feature_join/ui.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

Future<void> _pump(WidgetTester tester, MobileScannerErrorCode code) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JoinScanCameraError(
            error: MobileScannerException(errorCode: code),
          ),
        ),
      ),
    );

void main() {
  testWidgets('denied permission → tells the user to paste instead', (
    tester,
  ) async {
    await _pump(tester, MobileScannerErrorCode.permissionDenied);

    expect(find.byKey(JoinScanCameraError.viewKey), findsOneWidget);
    expect(find.textContaining('paste'), findsOneWidget);
    expect(find.textContaining('denied'), findsOneWidget);
    // No black/blank scanner sneaking through.
    expect(find.byType(MobileScanner), findsNothing);
  });

  testWidgets(
    'camera unavailable (no camera / generic) → paste fallback copy',
    (tester) async {
      await _pump(tester, MobileScannerErrorCode.controllerUninitialized);

      expect(find.byKey(JoinScanCameraError.viewKey), findsOneWidget);
      expect(find.textContaining("isn't available"), findsOneWidget);
      expect(find.textContaining('paste'), findsOneWidget);
    },
  );
}
