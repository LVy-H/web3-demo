import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/ui/core/scan_router.dart';

/// Unit tests for the scanner's pure routing half. The camera decode itself is
/// the device-fenced half; this is the part that must always be correct, so it
/// is exercised exhaustively here (no camera / platform channel needed).
void main() {
  group('routeForScannedValue — recognized payloads', () {
    test('live-vote ticket (the host QR — tessera:// scheme)', () {
      expect(
        routeForScannedValue('tessera://live/0xAbC/vote?t=WIRE123'),
        '/live/0xAbC/vote?t=WIRE123',
      );
    });

    test('live host dashboard', () {
      expect(
        routeForScannedValue('tessera://live/0xAbC/host'),
        '/live/0xAbC/host',
      );
    });

    test('verify receipt deep-link', () {
      expect(
        routeForScannedValue('tessera://verify?poll=0x1&nullifier=0x2'),
        '/verify?poll=0x1&nullifier=0x2',
      );
    });

    test('poll deep-link with module', () {
      expect(
        routeForScannedValue('tessera://poll/0xDef?module=survey-vote'),
        '/poll/0xDef?module=survey-vote',
      );
    });

    test('https mirror of the live ticket (future web share)', () {
      expect(
        routeForScannedValue('https://tessera.app/live/0xA/vote?t=W'),
        '/live/0xA/vote?t=W',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        routeForScannedValue('  tessera://verify?poll=0x1  '),
        '/verify?poll=0x1',
      );
    });
  });

  group('routeForScannedValue — rejects (→ null)', () {
    test('empty string', () => expect(routeForScannedValue(''), isNull));
    test('whitespace only', () => expect(routeForScannedValue('   '), isNull));
    test(
      'foreign scheme',
      () => expect(routeForScannedValue('mailto:a@b.c'), isNull),
    );
    test(
      'unrecognized tessera path',
      () => expect(routeForScannedValue('tessera://wat/0x1'), isNull),
    );
    test(
      'plain text',
      () => expect(routeForScannedValue('just some text'), isNull),
    );
    test(
      'tessera root with no segment',
      () => expect(routeForScannedValue('tessera://'), isNull),
    );
    test(
      'live without the /vote|/host leaf',
      () => expect(routeForScannedValue('tessera://live/0xA'), isNull),
    );
  });

  // The share QR's writer must be the exact inverse of the reader: a poll's
  // generated link always scans back to that same poll-detail location.
  group('shareLinkForPoll ↔ routeForScannedValue round-trip', () {
    const addr = '0xAbC0000000000000000000000000000000000123';
    const modules = [
      'anon-vote',
      'blind-vote',
      'approval-vote',
      'ranked-vote',
      'quadratic-vote',
      'survey-vote',
    ];
    for (final m in modules) {
      test('module $m scans back to its poll route', () {
        final link = shareLinkForPoll(addr, module: m);
        expect(link, 'tessera://poll/$addr?module=$m');
        expect(routeForScannedValue(link), '/poll/$addr?module=$m');
      });
    }
    test('no module → bare poll link round-trips', () {
      final link = shareLinkForPoll(addr);
      expect(link, 'tessera://poll/$addr');
      expect(routeForScannedValue(link), '/poll/$addr');
    });
    test('empty module is treated as no module', () {
      expect(shareLinkForPoll(addr, module: ''), 'tessera://poll/$addr');
    });
  });
}
