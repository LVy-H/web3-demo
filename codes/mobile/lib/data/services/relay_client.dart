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

  /// Relay a RANKED-CHOICE ballot (gasless): the vote is a [packedRanking] — up
  /// to 8 rank slots, 4 bits each (`packedRanking < 2^32`), most-preferred in
  /// slot 0 — not a single index and not a bitmask. POSTs to
  /// `/api/relay/ranked-vote`, which rejects unless `proof.message ==
  /// String(packedRanking)` (ballot ↔ proof binding) and the scope matches the
  /// poll. The contract stores the full ranking + tallies the ROUND-1 first
  /// preference; the instant-runoff winner is computed off-chain. Never throws —
  /// returns a [RelayResult]. Mirrors [relayApprovalVote]; the `/vote` and
  /// `/approval-vote` paths are left untouched.
  Future<RelayResult> relayRankedVote(
    String pollAddress,
    int packedRanking,
    RelayProof proof,
  ) async {
    try {
      final r = await _postJson('/api/relay/ranked-vote', {
        'pollAddress': pollAddress,
        'packedRanking': packedRanking,
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

  /// Relay a QUADRATIC ballot (gasless): the vote is a [packedAlloc] — up to 8
  /// allocation slots, 4 bits each (`packedAlloc < 2^32`), a DIRECT encoding
  /// where slot `i` ⇒ option `i` (NOT `optionIndex+1`) — not a single index, a
  /// bitmask, or a ranking. POSTs to `/api/relay/quadratic-vote`, whose
  /// `validateQuadraticVoteRequest` reads the body field named exactly
  /// `packedAlloc` and rejects unless `proof.message == String(packedAlloc)`
  /// (ballot ↔ proof binding) and the scope matches the poll. The contract owns
  /// the quadratic budget (`Σ vᵢ² ≤ CREDITS`); `getResults()` is then the
  /// authoritative per-option vote sum (no off-chain replay). Never throws —
  /// returns a [RelayResult]. Mirrors [relayRankedVote]; the `/vote`,
  /// `/approval-vote`, and `/ranked-vote` paths are left untouched.
  Future<RelayResult> relayQuadraticVote(
    String pollAddress,
    int packedAlloc,
    RelayProof proof,
  ) async {
    try {
      final r = await _postJson('/api/relay/quadratic-vote', {
        'pollAddress': pollAddress,
        'packedAlloc': packedAlloc,
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

  /// Relay a SURVEY ballot (gasless): the vote is the FULL answer VECTOR
  /// [answers] — one `uint256` word per question, in question order
  /// (SingleChoice ⇒ the chosen option index; MultiSelect ⇒ a bitmask, bit i ⇒
  /// option i) — NOT a single index, bitmask, ranking, or allocation. POSTs to
  /// `/api/relay/survey-vote`, whose `validateSurveyVoteRequest` reads the body
  /// field named exactly `answers` and accepts each word as a decimal string.
  ///
  /// CRITICAL difference from the sibling relays: the survey relayer does NOT
  /// bind `message` to the ballot — the Semaphore `message` is a keccak
  /// COMMITMENT (`keccak256(abi.encode(answers)) >> 8`, see
  /// `core/crypto/survey_commit.dart`) that the CONTRACT recomputes from
  /// calldata and binds (`TamperedVoteSignal` on mismatch). The relayer's
  /// message check is SHAPE-ONLY (a non-zero in-field element). The answers sent
  /// here MUST be the SAME vector the [RelayProof]'s wide `message` committed to,
  /// or the contract reverts every cast.
  ///
  /// The [BigInt] answer words are sent as DECIMAL STRINGS (`answers[q]` can be a
  /// multi-select bitmask up to 2^31, which is fine for `BigInt` but would not
  /// jsonEncode otherwise) — consistent with how `message`/`scope` travel.
  /// Never throws — returns a [RelayResult]. Mirrors [relayQuadraticVote]; the
  /// `/vote`, `/approval-vote`, `/ranked-vote`, and `/quadratic-vote` paths are
  /// left untouched.
  Future<RelayResult> relaySurveyVote(
    String pollAddress,
    List<BigInt> answers,
    RelayProof proof,
  ) async {
    try {
      final r = await _postJson('/api/relay/survey-vote', {
        'pollAddress': pollAddress,
        'answers': [for (final a in answers) a.toString()],
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
