/// Typed client for the Phase-2 self-hosted bulletin-board REST server — the
/// open-ballot path's cross-client boundary (server `codes/server`). Same
/// shape as [RelayClient] (injected [http.Client], per-request [timeout], a
/// typed exception on non-2xx), but it speaks the Decision/Ballot JSON API
/// instead of the relayer's chain-sponsorship endpoints.
///
/// Convener (organizer) routes need `Authorization: Bearer <token>` — the
/// admin token the server prints on startup, pasted by the operator for the
/// demo. Set it with [token]; public read + ballot-cast routes need none.
///
/// Every method returns the decoded JSON body (a `Map`/`List`); on any non-2xx
/// it throws a [ServerException] that carries the server's `{code}` so the UI
/// can react to `DECISION_CLOSED` / `MAX_PARTICIPANTS` etc. The server also
/// returns a `signature` on signed refusals (§10 exhibitable) — surfaced via
/// [ServerException.signature].
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ServerClient {
  final http.Client _client;
  final String baseUrl;

  /// Per-request timeout. Reads are quick; create/cast include a server-side
  /// transaction (sign + append + persist) but stay well under this.
  final Duration timeout;

  /// Convener Bearer token (admin token the server prints on startup). When
  /// set, it is sent on every request as `Authorization: Bearer <token>` —
  /// public routes ignore it, convener routes require it. Mutable so the demo
  /// can paste it after the client is built.
  String? token;

  ServerClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.token,
  }) : _client = client ?? http.Client();

  void close() => _client.close();

  // ── helpers ────────────────────────────────────────────────────────────

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  bool _is2xx(int s) => s >= 200 && s < 300;

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Never _throwFor(http.Response res) {
    final data = _decodeObject(res.body);
    final code = data['code'] is String ? data['code'] as String : null;
    final message = data['error'] is String
        ? data['error'] as String
        : 'request failed (HTTP ${res.statusCode})';
    final signature =
        data['signature'] is String ? data['signature'] as String : null;
    throw ServerException(
      message,
      status: res.statusCode,
      code: code,
      signature: signature,
      data: data,
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    late http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ServerException('The server did not respond in time.');
    } on Object catch (e) {
      throw ServerException(e.toString());
    }
    if (!_is2xx(res.statusCode)) _throwFor(res);
    return _decodeObject(res.body);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    late http.Response res;
    try {
      res = await _client
          .get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(timeout);
    } on TimeoutException {
      throw const ServerException('The server did not respond in time.');
    } on Object catch (e) {
      throw ServerException(e.toString());
    }
    if (!_is2xx(res.statusCode)) _throwFor(res);
    return _decodeObject(res.body);
  }

  // ── convener (organizer) lifecycle ───────────────────────────────────────

  /// `POST /decisions` → `201 {id, state:'draft', setupCommitment}`. [body] is
  /// the full create payload (title/options/method/ballotMode/resultsPolicy/
  /// eligibility/rule/schedule/visibility/anchorMode[/maxParticipants]); the
  /// caller assembles it (see ServerOrganizerPortAdapter). Needs the token.
  Future<Map<String, dynamic>> createDecision(Map<String, dynamic> body) =>
      _post('/decisions', body);

  /// `POST /decisions/:id/open` → `200 {id, state:'open'}`. Needs the token.
  Future<Map<String, dynamic>> openDecision(String id) =>
      _post('/decisions/$id/open', const {});

  /// `POST /decisions/:id/close` → `200 {id, state:'closed'}`. Needs the token.
  Future<Map<String, dynamic>> closeDecision(String id) =>
      _post('/decisions/$id/close', const {});

  /// `POST /decisions/:id/publish` → `200 {id, state:'published'}`. Token.
  Future<Map<String, dynamic>> publishDecision(String id) =>
      _post('/decisions/$id/publish', const {});

  /// `POST /decisions/:id/cancel` → `200 {id, state:'cancelled'}`. Token.
  Future<Map<String, dynamic>> cancelDecision(String id) =>
      _post('/decisions/$id/cancel', const {});

  /// `POST /decisions/:id/extend {closesAt}` → `200 {id, state:'open',
  /// closesAt}`. [closesAt] is a unix-seconds integer. Needs the token.
  Future<Map<String, dynamic>> extendDecision(String id, int closesAt) =>
      _post('/decisions/$id/extend', {'closesAt': closesAt});

  /// `GET /decisions/:id/turnout` → `{count}`. Convener-only. Needs the token.
  Future<Map<String, dynamic>> getTurnout(String id) =>
      _get('/decisions/$id/turnout');

  // ── public reads ─────────────────────────────────────────────────────────

  /// `GET /decisions/:id` → the public decision view (no token needed).
  Future<Map<String, dynamic>> getDecision(String id) => _get('/decisions/$id');

  /// `GET /decisions/:id/issuer` → `{issuerPublicKeyPem, issuerPubKeyHash}` for
  /// a SECRET-mode decision (no token needed). The per-decision RSABSSA issuer
  /// SPKI public key a registering voter blinds their credential under; the
  /// client MUST verify `sha256hex(issuerPublicKeyPem) == issuerPubKeyHash`
  /// (the anchored hash) before trusting it. `404 NOT_SECRET` in open mode.
  Future<Map<String, dynamic>> getIssuer(String id) =>
      _get('/decisions/$id/issuer');

  // ── secret-ballot registration ───────────────────────────────────────────

  /// `POST /register {decisionId, blindedMessage}` → `200 {decisionId,
  /// blindSignature}` (SECRET mode only; no token needed). The voter has
  /// locally blinded a credential message under the issuer pubkey; the server
  /// blind-signs the opaque token (never seeing the final credential). The
  /// caller `finalize()`s [blindSignature] into a credential signature. A
  /// non-2xx throws a [ServerException] (`REGISTRATION_CLOSED` once voting is
  /// open, `MAX_PARTICIPANTS`, `NOT_SECRET_MODE`, `INELIGIBLE`).
  Future<Map<String, dynamic>> register(
    String decisionId,
    String blindedMessage,
  ) =>
      _post('/register', {
        'decisionId': decisionId,
        'blindedMessage': blindedMessage,
      });

  /// `GET /ballots?decisionId=&after=&limit=` → `{ballots[], leafCount,
  /// nextCursor, complete?}`.
  Future<Map<String, dynamic>> getBallots(
    String decisionId, {
    int? after,
    int? limit,
  }) {
    final q = <String>['decisionId=${Uri.encodeQueryComponent(decisionId)}'];
    if (after != null) q.add('after=$after');
    if (limit != null) q.add('limit=$limit');
    return _get('/ballots?${q.join('&')}');
  }

  /// `GET /root?decisionId=` → `{head, leafCount}`.
  Future<Map<String, dynamic>> getRoot(String decisionId) =>
      _get('/root?decisionId=${Uri.encodeQueryComponent(decisionId)}');

  /// `GET /results?decisionId=` → `{tally:{optionScores[], abstain, totalCast,
  /// ...}, verdict:{outcome, winner?}, authoritative:false}`.
  Future<Map<String, dynamic>> getResults(String decisionId) =>
      _get('/results?decisionId=${Uri.encodeQueryComponent(decisionId)}');

  /// `GET /anchor?decisionId=` → `{mode, head, leafCount, status}`.
  Future<Map<String, dynamic>> getAnchor(String decisionId) =>
      _get('/anchor?decisionId=${Uri.encodeQueryComponent(decisionId)}');

  /// `GET /verify/:id` → `{report:{ok, checks[...]}, authoritative:false}` —
  /// the server-side convenience that rebuilds the public bundle and runs the
  /// independent verifier (the §11 checks). Non-authoritative; anyone can run
  /// the same verifier over the public endpoints.
  Future<Map<String, dynamic>> getVerify(String id) => _get('/verify/$id');

  // ── ballot cast ──────────────────────────────────────────────────────────

  /// `POST /ballots {decisionId, payload, idempotencyKey}` →
  /// `201 {receipt:{ballotHash, logPosition, runningRoot, serverSig},
  /// decisionId}`; `200` (same receipt) on an identical retry. A non-2xx
  /// throws a [ServerException] whose [ServerException.code] is one of
  /// `DECISION_CLOSED` / `MAX_PARTICIPANTS` / `VALIDATION` / `INELIGIBLE` /
  /// `SERIAL_USED` / `IDEMPOTENCY_CONFLICT`, carrying the server `signature`
  /// for signed refusals. No token needed (participant route).
  ///
  /// SECRET mode: pass the anonymous blind-sig credential as [serial] +
  /// [credentialSig] (from the register→finalize flow). The server verifies
  /// the credential against the per-decision issuer pubkey over the bound
  /// message `"$decisionId|$serial"` and records [serial] as the no-double-vote
  /// key (a reused serial → `409 SERIAL_USED`). Open-mode callers omit both;
  /// open-mode eligibility uses [passcode] / [email] instead.
  Future<Map<String, dynamic>> castBallot({
    required String decisionId,
    required Map<String, dynamic> payload,
    required String idempotencyKey,
    String? passcode,
    String? email,
    String? serial,
    String? credentialSig,
  }) =>
      _post('/ballots', {
        'decisionId': decisionId,
        'payload': payload,
        'idempotencyKey': idempotencyKey,
        'passcode': ?passcode,
        'email': ?email,
        'serial': ?serial,
        'credentialSig': ?credentialSig,
      });
}

/// Thrown for any non-2xx from the server. [code] is the server's machine
/// code (`DECISION_CLOSED`, `MAX_PARTICIPANTS`, `VALIDATION`, `INELIGIBLE`,
/// `NOT_FOUND`, `FORBIDDEN`, `ILLEGAL_TRANSITION`, `IDEMPOTENCY_CONFLICT`, …)
/// so callers can branch on it; [signature] is the server's signed-refusal
/// proof when present (§10).
class ServerException implements Exception {
  final String message;
  final int? status;
  final String? code;
  final String? signature;
  final Map<String, dynamic> data;

  const ServerException(
    this.message, {
    this.status,
    this.code,
    this.signature,
    this.data = const {},
  });

  /// The server signed the cast refusal because the decision is closed.
  bool get isDecisionClosed => code == 'DECISION_CLOSED';

  /// The decision hit its participant cap.
  bool get isMaxParticipants => code == 'MAX_PARTICIPANTS';

  /// SECRET mode: this credential serial already cast a ballot (no double-vote).
  bool get isSerialUsed => code == 'SERIAL_USED';

  /// The presented credential / eligibility was rejected at cast or register.
  bool get isIneligible => code == 'INELIGIBLE';

  /// Registration closed (the decision moved past 'registration' to voting).
  bool get isRegistrationClosed => code == 'REGISTRATION_CLOSED';

  @override
  String toString() =>
      'ServerException(${code ?? status ?? '?'}): $message';
}
