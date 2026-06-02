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
  static const _wasmAsset = 'assets/zk/semaphore-16.wasm';
  static const _zkeyAsset = 'assets/zk/semaphore-16.zkey';
  static const _bundleAsset = 'assets/zk/zkprover.js';
  static const _pageAsset = 'assets/zk/prover_host.html';

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
  WebViewController get controller => _controller!;

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

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('Prover', onMessageReceived: _onMessage);
    _controller = controller;
    await controller.loadRequest(Uri.parse('http://127.0.0.1:$_port/prover_host.html'));

    final ready = await _ready.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => false,
    );
    if (!ready) {
      throw StateError('WebView prover host never reached readiness (zkprover.js '
          'failed to load / expose globals)');
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
  Future<Map<String, dynamic>> generateProof({
    required String seed,
    required List<String> members,
    required int message,
    required String scope,
    ArtifactDelivery delivery = ArtifactDelivery.localhostHttp,
  }) async {
    final id = _nextId++;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;

    final membersJs = jsonEncode(members);
    final scopeJs = jsonEncode(scope);
    final seedJs = jsonEncode(seed);

    if (delivery == ArtifactDelivery.localhostHttp) {
      await controller.runJavaScript(
        'runProof($id, $seedJs, $membersJs, $message, $scopeJs, $_depth, '
        '{ wasm: ${jsonEncode(_httpWasm)}, zkey: ${jsonEncode(_httpZkey)} });',
      );
    } else {
      // Blob path: hand the bytes to JS as base64, build blob URLs there.
      final wasmB64 = base64Encode(_wasm!);
      final zkeyB64 = base64Encode(_zkey!);
      await controller.runJavaScript(
        'runProof($id, $seedJs, $membersJs, $message, $scopeJs, $_depth, '
        '{ wasm: blobUrlFromBase64(${jsonEncode(wasmB64)}, "application/wasm"), '
        'zkey: blobUrlFromBase64(${jsonEncode(zkeyB64)}, "application/octet-stream") });',
      );
    }

    final res = await c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('WebView prover timed out after $timeout');
    });
    if (res['ok'] != true) {
      throw Exception('WebView prover failed: ${res['error']}');
    }
    return (res['proof'] as Map).cast<String, dynamic>();
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _controller = null;
  }
}
