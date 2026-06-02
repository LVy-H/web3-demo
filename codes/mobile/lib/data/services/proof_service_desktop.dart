import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/relay_proof.dart';
import 'proof_service.dart';

/// Desktop (Linux/Windows/macOS) [ProofService] that generates Semaphore proofs
/// by spawning a Node SIDECAR (`web_prover/desktop_prover.mjs`) which eval's the
/// SAME self-contained `web/zkprover.js` bundle the web build uses. A phone-only
/// webview prover can't run on Linux; desktop can spawn a subprocess, so this is
/// the path that lets the desktop app actually cast a vote.
///
/// Opt-in: only constructed when `DEV…`-style paths are configured (see
/// proof_service_stub.dart); off by default so it never regresses web/mobile.
/// Proven against the real Groth16 vkey in `proof_service_desktop_test`.
class ProofServiceDesktop implements ProofService {
  final String nodePath;
  final String sidecarPath;
  final String bundlePath;
  final Duration timeout;

  Process? _proc;
  Future<void>? _starting;
  int _nextId = 1;
  final _pending = <int, Completer<Map<String, dynamic>>>{};

  ProofServiceDesktop({
    required this.nodePath,
    required this.sidecarPath,
    required this.bundlePath,
    this.timeout = const Duration(seconds: 120),
  });

  // Single-flight: concurrent first-callers share one spawn instead of racing
  // two Node processes (one would be orphaned).
  Future<void> _ensure() {
    if (_proc != null) return Future<void>.value();
    return _starting ??= () async {
      try {
        await _start();
      } finally {
        _starting = null;
      }
    }();
  }

  Future<void> _start() async {
    final p = await Process.start(nodePath, [sidecarPath, bundlePath]);
    _proc = p;
    // If the sidecar dies, drop the handle (so the next call re-spawns) and fail
    // any in-flight requests instead of letting their Completers hang to timeout.
    unawaited(p.exitCode.then((_) {
      _proc = null;
      final inflight = List.of(_pending.values);
      _pending.clear();
      for (final c in inflight) {
        if (!c.isCompleted) {
          c.completeError(Exception('desktop prover process exited'));
        }
      }
    }));
    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final t = line.trim();
      if (t.isEmpty) return;
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(t) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      final id = msg['id'] as int?;
      if (id != null) _pending.remove(id)?.complete(msg);
    });
    // Drain stderr so the pipe can't fill and stall the process.
    p.stderr.transform(utf8.decoder).listen((_) {});
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> req) async {
    await _ensure();
    final proc = _proc;
    if (proc == null) {
      throw Exception('desktop prover exited during start');
    }
    final id = _nextId++;
    req['id'] = id;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    proc.stdin.writeln(jsonEncode(req));
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('desktop prover timed out after $timeout');
    });
  }

  @override
  Future<RelayProof> generateVoteProof({
    required String identitySeed,
    required List<String> memberCommitments,
    required int message,
    required String scope,
  }) async {
    final res = await _send({
      'op': 'prove',
      'seed': identitySeed,
      'members': memberCommitments,
      'message': message,
      'scope': scope,
    });
    if (res['ok'] != true) {
      throw Exception('desktop prover failed: ${res['error']}');
    }
    return RelayProof.fromJson(res['proof'] as Map<String, dynamic>);
  }

  @override
  Future<String> deriveCommitment(String identitySeed) async {
    final res = await _send({'op': 'commitment', 'seed': identitySeed});
    if (res['ok'] != true) {
      throw Exception('desktop prover commitment failed: ${res['error']}');
    }
    return res['commitment'] as String;
  }

  /// Verify a proof against the real Groth16 vkey via the sidecar. Beyond the
  /// [ProofService] interface — used by the self-test to prove the proof is real
  /// (the local MockSemaphoreVerifier would accept anything).
  Future<bool> verifyProof(RelayProof proof) async {
    final res = await _send({'op': 'verify', 'proof': proof.toJson()});
    if (res['ok'] != true) {
      throw Exception('desktop prover verify failed: ${res['error']}');
    }
    return res['valid'] == true;
  }

  @override
  void dispose() {
    _proc?.kill();
    _proc = null;
  }
}
