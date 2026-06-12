import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:core_domain/models/pending_voter.dart';
import 'package:core_domain/models/relay_proof.dart';

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

  /// Sponsored-lifecycle discovery: the relayer's signer address (baked as the
  /// `owner` word inside initData so the relayer owns — and can register/start —
  /// the poll) + the PollRegistry address. Returns null on any error.
  Future<RelayerInfo?> getRelayerInfo() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/relay/info'))
          .timeout(timeout);
      if (!_is2xx(res.statusCode)) return null;
      final d = _decode(res.body);
      if (d['relayer'] is String) {
        return RelayerInfo(
          relayer: d['relayer'] as String,
          registry: d['registry'] is String ? d['registry'] as String : null,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Wallet-free, sponsored poll creation: the relayer clones + initializes the
  /// poll via `PollRegistry.createPoll`, paying gas, and returns the new poll
  /// address. [initDataHex] is the module's PRE-R4 `initialize(...)` calldata
  /// with the RELAYER as `owner` (see [getRelayerInfo]); the R4 privacy
  /// choices travel as the TOP-LEVEL [visibility] / [resultsPolicy] fields
  /// (0|1, both default 0 — unlisted + sealed-until-close) because the
  /// relayer appends `resultsPolicy` to the initData server-side (PR #108's
  /// shim — see `sponsored_poll_creator.dart` for the full wire contract).
  /// On failure, [CreatePollResult.ok] is false and `error` carries the
  /// relayer's client-facing message.
  Future<CreatePollResult> createPoll({
    required String moduleType,
    required String title,
    required String description,
    required String initDataHex,
    int visibility = 0,
    int resultsPolicy = 0,
  }) async {
    try {
      final r = await _postJson(
        '/api/relay/create-poll',
        {
          'moduleType': moduleType,
          'title': title,
          'description': description,
          'initData': initDataHex,
          // Always sent explicitly so the JSON mirrors what the chain will
          // store — the relayer treats omitted and 0 identically.
          'visibility': visibility,
          'resultsPolicy': resultsPolicy,
        },
        timeout: voteTimeout, // create includes an on-chain tx submission
      );
      if (r.ok && r.data['pollAddress'] is String) {
        return CreatePollResult(
          pollAddress: r.data['pollAddress'] as String,
          txHash: r.data['txHash'] is String ? r.data['txHash'] as String : null,
        );
      }
      return CreatePollResult(error: _err(r.data, 'Could not create the poll.'));
    } on TimeoutException {
      return const CreatePollResult(error: 'The relayer timed out. Try again.');
    } catch (e) {
      return CreatePollResult(error: e.toString());
    }
  }

  /// Wallet-free self-registration: the relayer (owner of a sponsored poll) adds
  /// the voter's [identityCommitment] to the poll's Semaphore group, paying gas.
  /// Idempotent (already-a-member returns ok). On failure [RegisterResult.ok] is
  /// false and `error` carries the relayer's message (e.g. "joining is closed").
  Future<RegisterResult> registerVoter(
    String pollAddress,
    String identityCommitment,
  ) async {
    try {
      final r = await _postJson(
        '/api/relay/register-voter',
        {'pollAddress': pollAddress, 'identityCommitment': identityCommitment},
        timeout: voteTimeout, // includes an on-chain tx
      );
      if (r.ok && r.data['success'] == true) {
        return RegisterResult(
          ok: true,
          txHash: r.data['txHash'] is String ? r.data['txHash'] as String : null,
          alreadyRegistered: r.data['alreadyRegistered'] == true,
        );
      }
      return RegisterResult(error: _err(r.data, 'Could not join this poll.'));
    } on TimeoutException {
      return const RegisterResult(error: 'The relayer timed out. Try again.');
    } catch (e) {
      return RegisterResult(error: e.toString());
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

/// `GET /api/relay/info` — the relayer's signer address + the registry address.
class RelayerInfo {
  final String relayer;
  final String? registry;
  const RelayerInfo({required this.relayer, this.registry});
}

/// `POST /api/relay/create-poll` result. [ok] when the relayer created the poll.
class CreatePollResult {
  final String? pollAddress;
  final String? txHash;
  final String? error;
  const CreatePollResult({this.pollAddress, this.txHash, this.error});
  bool get ok => pollAddress != null;
}

/// `POST /api/relay/register-voter` result.
class RegisterResult {
  final bool ok;
  final String? txHash;
  final bool alreadyRegistered;
  final String? error;
  const RegisterResult({
    this.ok = false,
    this.txHash,
    this.alreadyRegistered = false,
    this.error,
  });
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
