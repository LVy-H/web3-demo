import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards against bundle DRIFT. The web build references `web/zkprover.js`; the
/// Android APK ships only Flutter `assets:`, so the mobile WebView prover loads
/// `assets/zk/zkprover.js` — a COPY of the same vite bundle. If the two diverge,
/// mobile would prove with a stale prover while web uses the fresh one (or vice
/// versa). This test fails the moment they differ, so any rebuild of
/// `web/zkprover.js` must be re-copied into `assets/zk/` (see the M2 design).
void main() {
  test('assets/zk/zkprover.js is byte-identical to web/zkprover.js', () {
    // In the workspace, the web copy ships with the app shell; the asset copy
    // is bundled by this package (core_crypto). Paths are package-root-relative.
    final web = File('../../apps/tessera/web/zkprover.js');
    final asset = File('assets/zk/zkprover.js');
    expect(web.existsSync(), isTrue,
        reason: 'apps/tessera/web/zkprover.js must exist');
    expect(asset.existsSync(), isTrue,
        reason: 'assets/zk/zkprover.js (the bundled mobile prover) must exist');

    final webSha = sha256.convert(web.readAsBytesSync()).toString();
    final assetSha = sha256.convert(asset.readAsBytesSync()).toString();
    expect(assetSha, webSha,
        reason: 'assets/zk/zkprover.js drifted from web/zkprover.js — re-copy '
            'the rebuilt vite bundle into assets/zk/ (web_prover build output).');
  });
}
