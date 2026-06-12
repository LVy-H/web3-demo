import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

/// Phase 11 M1 spike host: drives a `webview_flutter` WebView that runs the SAME
/// `web/zkprover.js` Semaphore bundle the web build uses, to generate a Groth16
/// vote proof ON-DEVICE from BUNDLED depth-16 artifacts.
///
/// The bundle, host page and the two artifacts are served from a single Dart
/// loopback [HttpServer] on `127.0.0.1`. Single-origin means the page's relative
/// `<script src="zkprover.js">` resolves and snarkjs `fetch()`es the artifacts
/// with no CORS — the exact path the host-side preflight
/// (`web_prover/spike_bundled_artifacts.mjs`) proved produces a vkey-valid
/// depth-16 proof. Two artifact-delivery strategies are supported so the spike
/// can report which works on the emulator:
///   - [ArtifactDelivery.localhostHttp] — pass the loopback URLs straight to
///     snarkjs (primary; known-good from the preflight).
///   - [ArtifactDelivery.blobUrl] — ship the bytes into JS as base64, build
///     `URL.createObjectURL(new Blob([...]))` there (the spec's preferred
///     production path; ~4.5 MB base64 stresses the Dart→JS string bridge).
///
/// This is the spike harness for the M1 go/no-go gate; [ProofServiceMobile]
/// (M2) wraps the same machinery behind the [ProofService] contract.
enum ArtifactDelivery { localhostHttp, blobUrl }

class WebViewProverHost {
  static const _depth = 16;
  static const _wasmAsset = 'packages/core_crypto/assets/zk/semaphore-16.wasm';
  static const _zkeyAsset = 'packages/core_crypto/assets/zk/semaphore-16.zkey';
  static const _bundleAsset = 'packages/core_crypto/assets/zk/zkprover.js';
  static const _pageAsset = 'packages/core_crypto/assets/zk/prover_host.html';

  final Duration timeout;
  WebViewProverHost({this.timeout = const Duration(minutes: 3)});

  HttpServer? _server;
  WebViewController? _controller;
  Uint8List? _wasm;
  Uint8List? _zkey;
  int _port = 0;

  final _ready = Completer<bool>();
  int _nextId = 1;
  final _pending = <int, Completer<Map<String, dynamic>>>{};

  /// The mountable widget controller. The WebView must be attached to the tree
  /// (a 1x1 offstage `WebViewWidget`) for JS to execute on Android.
  ///
  /// Eagerly created on first access so a host page / companion widget can mount
  /// the WebView BEFORE [init] runs — the production [ProofServiceMobile] mounts
  /// the controller in `MaterialApp.builder` at app start, then calls [init]
  /// lazily on the first proof. The spike test creates it implicitly via [init].
  WebViewController get controller => _controller ??= _buildController();

  WebViewController _buildController() => WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel('Prover', onMessageReceived: _onMessage);

  /// Start the loopback server, load the host page, await the JS readiness
  /// handshake. Idempotent-ish: call once per host.
  Future<void> init() async {
    _wasm = (await rootBundle.load(_wasmAsset)).buffer.asUint8List();
    _zkey = (await rootBundle.load(_zkeyAsset)).buffer.asUint8List();
    final bundle = (await rootBundle.load(_bundleAsset)).buffer.asUint8List();
    final page = (await rootBundle.load(_pageAsset)).buffer.asUint8List();

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen((req) {
      final path = req.uri.path;
      void send(List<int> bytes, String type) {
        req.response.headers.set(HttpHeaders.contentTypeHeader, type);
        // Same-origin, but be liberal — snarkjs/Blob requests stay local.
        req.response.headers.set('Access-Control-Allow-Origin', '*');
        req.response.add(bytes);
        req.response.close();
      }

      if (path.endsWith('semaphore-16.wasm')) {
        send(_wasm!, 'application/wasm');
      } else if (path.endsWith('semaphore-16.zkey')) {
        send(_zkey!, 'application/octet-stream');
      } else if (path.endsWith('zkprover.js')) {
        send(bundle, 'text/javascript');
      } else {
        send(page, 'text/html'); // prover_host.html (and any other path)
      }
    });

    // Reuse the eagerly-built controller if a widget already mounted it (the
    // production path), else build it now (the spike-test path).
    final c = controller;
    await c.loadRequest(Uri.parse('http://127.0.0.1:$_port/prover_host.html'));

    final ready = await _ready.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => false,
    );
    if (!ready) {
      throw StateError(
        'WebView prover host never reached readiness (zkprover.js '
        'failed to load / expose globals)',
      );
    }
  }

  void _onMessage(JavaScriptMessage msg) {
    Map<String, dynamic> obj;
    try {
      obj = jsonDecode(msg.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final tag = obj['tag'];
    if (tag == 'ready') {
      if (!_ready.isCompleted) _ready.complete(obj['ok'] == true);
    } else if (tag == 'proof') {
      final id = obj['id'] as int?;
      if (id != null) _pending.remove(id)?.complete(obj);
    }
  }

  String get _httpWasm => 'http://127.0.0.1:$_port/semaphore-16.wasm';
  String get _httpZkey => 'http://127.0.0.1:$_port/semaphore-16.zkey';

  /// Generate a depth-16 vote proof in the WebView using [delivery] for the
  /// artifacts. Returns the proof JSON map (`merkleTreeDepth`, `points`, …).
  ///
  /// [message] is a small int (option index / bitmask) — emitted as a bare JS
  /// NUMBER literal; the host's `runProof` does `Number(message)`. The verified
  /// single-question path; its emitted JS is byte-identical to before.
  Future<Map<String, dynamic>> generateProof({
    required String seed,
    required List<String> members,
    required int message,
    required String scope,
    ArtifactDelivery delivery = ArtifactDelivery.localhostHttp,
  }) async {
    // The int message is emitted as a bare JS numeric literal (e.g. `5`).
    return _runProof('runProof', '$message', seed, members, scope, delivery);
  }

  /// WIDE variant for the survey module: [message] is a DECIMAL STRING (a
  /// 248-bit `keccak256(abi.encode(answers)) >> 8` commitment). It is
  /// JSON-encoded into a QUOTED JS string literal and the host's `runProofWide`
  /// passes it to the bundle WITHOUT `Number()` (the bundle does
  /// `BigInt(message)`), so the full field element survives. [generateProof]
  /// above stays byte-identical.
  ///
  /// HONESTY: this JS/WebView path is NOT exercised by `flutter test` (it needs
  /// a device/emulator), same bound as the rest of the on-device proving path.
  Future<Map<String, dynamic>> generateProofWide({
    required String seed,
    required List<String> members,
    required String message,
    required String scope,
    ArtifactDelivery delivery = ArtifactDelivery.localhostHttp,
  }) async {
    // JSON-encode → a quoted JS string literal, so it is NOT lossily coerced to
    // a JS number on the Dart→JS string bridge.
    return _runProof(
      'runProofWide',
      jsonEncode(message),
      seed,
      members,
      scope,
      delivery,
    );
  }

  /// Shared driver for [generateProof]/[generateProofWide]. [jsFn] is the host
  /// page function to call (`runProof` or `runProofWide`); [messageLiteral] is
  /// the already-encoded JS literal for `message` (a bare number for the int
  /// path, a quoted string for the wide path).
  Future<Map<String, dynamic>> _runProof(
    String jsFn,
    String messageLiteral,
    String seed,
    List<String> members,
    String scope,
    ArtifactDelivery delivery,
  ) async {
    final id = _nextId++;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;

    final membersJs = jsonEncode(members);
    final scopeJs = jsonEncode(scope);
    final seedJs = jsonEncode(seed);

    if (delivery == ArtifactDelivery.localhostHttp) {
      await controller.runJavaScript(
        '$jsFn($id, $seedJs, $membersJs, $messageLiteral, $scopeJs, $_depth, '
        '{ wasm: ${jsonEncode(_httpWasm)}, zkey: ${jsonEncode(_httpZkey)} });',
      );
    } else {
      // Blob path: hand the bytes to JS as base64, build blob URLs there.
      final wasmB64 = base64Encode(_wasm!);
      final zkeyB64 = base64Encode(_zkey!);
      await controller.runJavaScript(
        '$jsFn($id, $seedJs, $membersJs, $messageLiteral, $scopeJs, $_depth, '
        '{ wasm: blobUrlFromBase64(${jsonEncode(wasmB64)}, "application/wasm"), '
        'zkey: blobUrlFromBase64(${jsonEncode(zkeyB64)}, "application/octet-stream") });',
      );
    }

    final res = await c.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('WebView prover timed out after $timeout');
      },
    );
    if (res['ok'] != true) {
      throw Exception('WebView prover failed: ${res['error']}');
    }
    return (res['proof'] as Map).cast<String, dynamic>();
  }

  /// Derive the Semaphore identity commitment (decimal string) for [seed] using
  /// the bundle's `window.zkCommitment` — pure identity math, no SNARK, no
  /// artifacts. Runs in the SAME ready WebView as proving.
  ///
  /// `runJavaScriptReturningResult` on Android returns the JS value re-encoded as
  /// a JSON string (a bare `"123…"` comes back quote-wrapped, sometimes
  /// backslash-escaped), so the result is JSON-decoded back to the raw decimal.
  Future<String> deriveCommitment(String seed) async {
    final seedJs = jsonEncode(seed);
    final raw = await controller.runJavaScriptReturningResult(
      'window.zkCommitment($seedJs)',
    );
    return _unwrapJsString(raw);
  }

  /// Normalise a `runJavaScriptReturningResult` payload to a plain Dart string.
  /// Android hands back the JS value JSON-encoded (quoted/escaped); iOS/others
  /// may return the bare value. Decode when it looks JSON-quoted, else trim.
  static String _unwrapJsString(Object? raw) {
    final s = raw?.toString() ?? '';
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      try {
        return jsonDecode(s) as String;
      } catch (_) {
        return s.substring(1, s.length - 1);
      }
    }
    return s;
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _controller = null;
  }
}
