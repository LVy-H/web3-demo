import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pending_voter.dart';
import '../models/relay_proof.dart';

/// Typed client for the relayer HTTP API — the cross-client boundary (spec
/// §2.5). Dart port of `codes/frontend/src/lib/liveRelay.ts` +
/// `codes/frontend/src/hooks/useRelay.ts`. Inject an [http.Client] for tests.
class RelayClient {
  final http.Client _client;
  final String baseUrl;

  /// Per-request timeout for ticket/status calls (parity with the web client's
  /// 8s) and the slower vote relay (30s — proof relay + tx submission).
  final Duration timeout;
  final Duration voteTimeout;

  RelayClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    this.voteTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  void close() => _client.close();

  // ── helpers ────────────────────────────────────────────────────────────
  Map<String, dynamic> _decode(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  bool _is2xx(int s) => s >= 200 && s < 300;

  String _err(Map<String, dynamic> data, String fallback) =>
      data['error'] is String ? data['error'] as String : fallback;

  Future<({bool ok, int status, Map<String, dynamic> data})> _postJson(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout ?? this.timeout);
    return (
      ok: _is2xx(res.statusCode),
      status: res.statusCode,
      data: _decode(res.body),
    );
  }

  // ── ticket endpoints ─────────────────────────────────────────────────────

  /// Register the organizer's per-poll ed25519 PUBLIC key (verification anchor).
  Future<void> issueOrgKey(String pollId, String orgPubKey) async {
    final r = await _postJson('/api/relay/tickets/issue', {
      'pollId': pollId,
      'orgPubKey': orgPubKey,
    });
    if (!r.ok) {
      throw RelayException(_err(r.data, 'issue failed (HTTP ${r.status})'));
    }
  }

  /// Voter announces itself with a fresh ticket + ephemeral commitment + code.
  Future<PostPendingResult> postPending(
    String pollId,
    String ticket,
    String ephemeralIdentityCommitment,
    String confirmationCode,
  ) async {
    try {
      final r = await _postJson('/api/relay/tickets/pending', {
        'pollId': pollId,
        'ticket': ticket,
        'ephemeralIdentityCommitment': ephemeralIdentityCommitment,
        'confirmationCode': confirmationCode,
      });
      return PostPendingResult(
        ok: r.ok,
        status: r.status,
        error: r.data['error'] is String ? r.data['error'] as String : null,
      );
    } catch (e) {
      return PostPendingResult(ok: false, status: 0, error: e.toString());
    }
  }

  /// Organizer dashboard reads the pending-voter queue for a poll.
  Future<List<PendingVoter>> fetchQueue(String pollId) async {
    final res = await _client
        .get(Uri.parse('$baseUrl/api/relay/tickets/queue?pollId=$pollId'))
        .timeout(timeout);
    if (!_is2xx(res.statusCode)) {
      throw RelayException('queue failed (HTTP ${res.statusCode})');
    }
    final voters = _decode(res.body)['voters'];
    if (voters is List) {
      return voters
          .whereType<Map<String, dynamic>>()
          .map(PendingVoter.fromJson)
          .toList();
    }
    return const [];
  }

  /// Mark a ticket consumed once the organizer has confirmed the voter.
  Future<void> redeemTicket(String pollId, String ticket) async {
    final r = await _postJson('/api/relay/tickets/redeem', {
      'pollId': pollId,
      'ticket': ticket,
    });
    if (!r.ok) {
      throw RelayException(_err(r.data, 'redeem failed (HTTP ${r.status})'));
    }
  }

  // ── vote + status ────────────────────────────────────────────────────────

  /// Relay a Semaphore vote (gasless). Never throws — returns a [RelayResult].
  Future<RelayResult> relayVote(
    String pollAddress,
    int vote,
    RelayProof proof,
  ) async {
    try {
      final r = await _postJson('/api/relay/vote', {
        'pollAddress': pollAddress,
        'vote': vote,
        'proof': proof.toJson(),
      }, timeout: voteTimeout);
      if (!r.ok) {
        return RelayResult(success: false, error: _err(r.data, 'HTTP ${r.status}'));
      }
      return RelayResult(
        success: true,
        txHash: r.data['txHash'] is String ? r.data['txHash'] as String : null,
      );
    } on TimeoutException {
      return const RelayResult(
          success: false, error: 'Relayer did not respond in time. Try again.');
    } catch (e) {
      return RelayResult(success: false, error: e.toString());
    }
  }

  /// Relay an APPROVAL ballot (gasless): the vote is a [bitmask] (bit i set ⇒
  /// option i approved), not a single index. POSTs to `/api/relay/approval-vote`,
  /// which rejects unless `proof.message == String(bitmask)` (ballot ↔ proof
  /// binding) and the scope matches the poll. Never throws — returns a
  /// [RelayResult]. Mirrors [relayVote]; the single-option `/vote` path is left
  /// untouched.
  Future<RelayResult> relayApprovalVote(
    String pollAddress,
    int bitmask,
    RelayProof proof,
  ) async {
    try {
      final r = await _postJson('/api/relay/approval-vote', {
        'pollAddress': pollAddress,
        'bitmask': bitmask,
        'proof': proof.toJson(),
      }, timeout: voteTimeout);
      if (!r.ok) {
        return RelayResult(success: false, error: _err(r.data, 'HTTP ${r.status}'));
      }
      return RelayResult(
        success: true,
        txHash: r.data['txHash'] is String ? r.data['txHash'] as String : null,
      );
    } on TimeoutException {
      return const RelayResult(
          success: false, error: 'Relayer did not respond in time. Try again.');
    } catch (e) {
      return RelayResult(success: false, error: e.toString());
    }
  }

  /// One-shot relayer health/balance probe. Returns null on any error.
  Future<RelayStatus?> fetchStatus() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/relay/status'))
          .timeout(timeout);
      if (!_is2xx(res.statusCode)) return null;
      final d = _decode(res.body);
      if (d['relayer'] is String && d['balance'] is String) {
        return RelayStatus(
          relayer: d['relayer'] as String,
          balance: d['balance'] as String,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// Thrown for relayer calls whose failure is exceptional (issue/redeem/queue).
class RelayException implements Exception {
  final String message;
  const RelayException(this.message);
  @override
  String toString() => message;
}

class RelayResult {
  final bool success;
  final String? txHash;
  final String? error;
  const RelayResult({required this.success, this.txHash, this.error});
}

class PostPendingResult {
  final bool ok;
  final int status;
  final String? error;
  const PostPendingResult({required this.ok, required this.status, this.error});
}

class RelayStatus {
  final String relayer;
  final String balance;
  const RelayStatus({required this.relayer, required this.balance});
}
