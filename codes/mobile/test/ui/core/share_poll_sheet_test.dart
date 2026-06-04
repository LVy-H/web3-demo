import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tessera/ui/core/share_poll_sheet.dart';

void main() {
  const addr = '0xAbC0000000000000000000000000000000000123';

  testWidgets('share sheet shows the deep-link + QR and copies', (
    tester,
  ) async {
    // Capture what gets written to the clipboard (the platform channel is not
    // backed in tests, so intercept it instead of letting it no-op/throw).
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
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

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    const link = 'tessera://poll/$addr?module=anon-vote';
    expect(find.text('SHARE POLL'), findsOneWidget);
    expect(find.text('My Poll'), findsOneWidget);
    expect(find.text(link), findsOneWidget); // the deep-link is shown
    expect(find.byType(QrImageView), findsOneWidget); // and encoded as a QR

    // Copy writes the link to the clipboard and flips the label to COPIED.
    expect(find.text('COPY LINK'), findsOneWidget);
    await tester.tap(find.text('COPY LINK'));
    await tester.pumpAndSettle();
    expect(copied, link);
    expect(find.text('COPIED'), findsOneWidget);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
}
