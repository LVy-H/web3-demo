import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/relay_proof.dart';
import 'proof_service.dart';
import 'proof_webview_host.dart';

/// Mobile (Android) [ProofService]: generates Semaphore v4 vote proofs ON-DEVICE
/// inside a headless `webview_flutter` WebView running the SAME `web/zkprover.js`
/// bundle the web build uses, with the depth-16 Groth16 artifacts BUNDLED as
/// Flutter assets (no CDN, offline). Verified on an API-31 x86_64 emulator: the
/// in-WebView proof passes the real Groth16 vkey (see
/// `docs/superpowers/specs/2026-06-02-mobile-proving-spike-FINDINGS.md`).
///
/// IMPORTANT — the WebView must be ATTACHED to the widget tree for JS to run on
/// Android. This service does NOT mount itself; the app shell renders [hostView]
/// (a 1×1 offstage `WebViewWidget`) once via `MaterialApp.builder`. Construction
/// is synchronous (builds the controller so the widget can mount it at app
/// start); the page-load + readiness handshake runs lazily/single-flight on the
/// first proving call (mirrors `ProofServiceDesktop._ensure`).
class ProofServiceMobile implements ProofService {
  final WebViewProverHost _host;
  Future<void>? _initing;
  bool _ready = false;

  ProofServiceMobile({WebViewProverHost? host})
      : _host = host ?? WebViewProverHost();

  /// The offstage host WebView the app shell must mount (once) so on-device JS
  /// can execute. Touching [WebViewProverHost.controller] eagerly builds the
  /// controller, so this is safe to call before [_ensureReady].
  Widget get hostView => Offstage(
        offstage: true,
        child: SizedBox(
          width: 1,
          height: 1,
          child: WebViewWidget(controller: _host.controller),
        ),
      );

  /// Single-flight: the first caller drives the loopback server + page load +
  /// readiness handshake; concurrent callers await the same future. By the time
  /// a user can vote, [hostView] has been mounted since app start, so the
  /// handshake can actually complete.
  Future<void> _ensureReady() {
    if (_ready) return Future<void>.value();
    return _initing ??= () async {
      try {
        await _host.init();
        _ready = true;
      } finally {
        _initing = null;
      }
    }();
  }

  @override
  Future<RelayProof> generateVoteProof({
    required String identitySeed,
    required List<String> memberCommitments,
    required int message,
    required String scope,
  }) async {
    await _ensureReady();
    final proof = await _host.generateProof(
      seed: identitySeed,
      members: memberCommitments,
      message: message,
      scope: scope,
      // localhost-HTTP delivery is the GO-locking, known-good path; the bundled
      // artifacts are served same-origin from the loopback server.
      delivery: ArtifactDelivery.localhostHttp,
    );
    return RelayProof.fromJson(proof);
  }

  @override
  Future<RelayProof> generateVoteProofWide({
    required String identitySeed,
    required List<String> memberCommitments,
    required String message,
    required String scope,
  }) async {
    await _ensureReady();
    // Mirrors generateVoteProof but routes the WIDE decimal-string [message]
    // through the host's wide path ([WebViewProverHost.generateProofWide] →
    // `runProofWide` in prover_host.html), which quotes the message as a JS
    // string and skips `Number()` so a 248-bit survey commitment isn't
    // narrowed. The int path above is untouched.
    final proof = await _host.generateProofWide(
      seed: identitySeed,
      members: memberCommitments,
      message: message,
      scope: scope,
      delivery: ArtifactDelivery.localhostHttp,
    );
    return RelayProof.fromJson(proof);
  }

  @override
  Future<String> deriveCommitment(String identitySeed) async {
    await _ensureReady();
    return _host.deriveCommitment(identitySeed);
  }

  @override
  void dispose() {
    // Fire-and-forget: tears down the loopback server + drops the controller.
    unawaited(_host.dispose());
  }
}
