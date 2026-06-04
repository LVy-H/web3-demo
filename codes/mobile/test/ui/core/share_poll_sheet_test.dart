import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tessera/data/services/nfc_service.dart';
import 'package:tessera/ui/core/share_poll_sheet.dart';

/// Configurable fake: `available` gates the NFC affordance; `writeUrl` records
/// the payload so the test can assert it equals the QR/link payload.
class _FakeNfc implements NfcService {
  final bool available;
  String? wroteUrl;
  _FakeNfc({this.available = false});

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<NfcWriteResult> writeUrl(String url) async {
    wroteUrl = url;
    return const NfcWriteResult(ok: true);
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  const addr = '0xAbC0000000000000000000000000000000000123';
  const link = 'tessera://poll/$addr?module=anon-vote';

  Widget host(NfcService nfc) => MaterialApp(
    home: Provider<NfcService>.value(
      value: nfc,
      child: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showSharePollSheet(
              context,
              address: addr,
              module: 'anon-vote',
              title: 'My Poll',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'shows the deep-link + QR and copies; no NFC button without a radio',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(host(_FakeNfc(available: false)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('SHARE POLL'), findsOneWidget);
      expect(find.text('My Poll'), findsOneWidget);
      expect(find.text(link), findsOneWidget); // the deep-link is shown
      expect(find.byType(QrImageView), findsOneWidget); // and encoded as a QR
      // No NFC radio → no NFC affordance (the QR is the baseline).
      expect(find.text('WRITE TO NFC TAG'), findsNothing);

      expect(find.text('COPY LINK'), findsOneWidget);
      await tester.tap(find.text('COPY LINK'));
      await tester.pumpAndSettle();
      expect(copied, link);
      expect(find.text('COPIED'), findsOneWidget);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    },
  );

  testWidgets('NFC available → WRITE TO NFC TAG writes the same link payload', (
    tester,
  ) async {
    final nfc = _FakeNfc(available: true);
    await tester.pumpWidget(host(nfc));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('WRITE TO NFC TAG'), findsOneWidget);
    await tester.tap(find.text('WRITE TO NFC TAG'));
    await tester.pumpAndSettle();

    // The NFC payload is the SAME tessera:// link the QR encodes.
    expect(nfc.wroteUrl, link);
    expect(find.textContaining('Written to tag'), findsOneWidget);
  });
}
