import 'join_target.dart';

/// Parse any scanned / pasted / typed JOIN input into a typed [JoinTarget].
///
/// Lifted from the proven `codes/mobile` `routeForScannedValue` grammar and
/// refactored from route strings to typed results (the route mapping moves to
/// the R3 router layer). The recognized link grammar is unchanged:
///
/// ```text
/// tessera://live/<addr>/vote?t=<wire>   → LiveVoteTarget
/// tessera://live/<addr>/host            → LiveHostTarget
/// tessera://verify?poll=…&nullifier=…   → VerifyTarget
/// tessera://poll/<addr>?module=<id>     → PollTarget
/// http(s)://<any-host>/<same paths>     → same targets (web-share mirror)
/// ```
///
/// New for the JOIN surface (spec §4.1), the short join-code:
///
/// ```text
/// TES-XXXXXX  (6 Crockford-base32 symbols, case-insensitive,
///              hyphen optional)                  → CodeTarget
/// ```
///
/// Pure and total: never throws, never returns null — anything else comes
/// back as an [UnknownTarget] with a short reason, so the JOIN surface can
/// show "unrecognized" feedback without try/catch.
JoinTarget parseJoinInput(String raw) {
  // Totality guard: `Uri.tryParse` accepts some inputs whose component
  // getters (`pathSegments`, `queryParameters`) still throw lazily on
  // malformed percent-encoding. Those SDK internals are not under this
  // grammar's control, so the never-throws contract is enforced here.
  try {
    return _parseJoinInput(raw);
  } on FormatException {
    return const UnknownTarget('malformed link encoding');
  }
}

JoinTarget _parseJoinInput(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return const UnknownTarget('empty input');

  // The short code first: it is not URI-shaped (no scheme), so the two
  // grammars cannot collide, and the cheap check keeps the common typed-code
  // path fast.
  final code = tryParseJoinCode(s);
  if (code != null) return code;

  final uri = Uri.tryParse(s);
  if (uri == null) return const UnknownTarget('not a parseable link');
  if (uri.scheme != 'tessera' &&
      uri.scheme != 'https' &&
      uri.scheme != 'http') {
    return const UnknownTarget('not a Tessera link or join code');
  }

  // For the custom `tessera://<seg0>/<seg1>/…` scheme, Dart parses <seg0> as
  // the authority/host; for http(s) the logical segments are just the path.
  // Flatten both into one ordered list of non-empty segments — exactly the
  // legacy grammar's behavior, so every link in the wild keeps working.
  final segs = <String>[
    if (uri.scheme == 'tessera' && uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments,
  ].where((e) => e.isNotEmpty).toList();
  if (segs.isEmpty) return const UnknownTarget('link has no path');

  final params = uri.queryParameters;
  String? param(String key) {
    final v = params[key];
    return (v == null || v.isEmpty) ? null : v;
  }

  if (segs.length >= 3 && segs[0] == 'live' && segs[2] == 'vote') {
    return LiveVoteTarget(segs[1], ticket: param('t'));
  }
  if (segs.length >= 3 && segs[0] == 'live' && segs[2] == 'host') {
    return LiveHostTarget(segs[1]);
  }
  if (segs[0] == 'verify') {
    return VerifyTarget(poll: param('poll'), nullifier: param('nullifier'));
  }
  if (segs.length >= 2 && segs[0] == 'poll') {
    return PollTarget(segs[1], module: param('module'));
  }
  return const UnknownTarget('unrecognized Tessera link');
}

/// Crockford base32 symbol set (RFC-less, Douglas Crockford 2008): digits and
/// uppercase letters minus the confusable I, L, O and the profanity-prone U.
const String _crockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Try to read [input] as a short join-code: `TES-XXXXXX` — the `TES-` prefix
/// (hyphen optional) followed by exactly 6 Crockford-base32 symbols,
/// case-insensitive. Returns the normalized [CodeTarget], or `null` when the
/// input is not in join-code form (callers fall through to the link grammar).
///
/// Normalization follows Crockford decoding: uppercase, strip the optional
/// hyphen, fold the standard aliases `O`→`0` and `I`/`L`→`1` (so a code read
/// aloud or retyped from paper still resolves). `U` stays invalid.
///
/// v1 codes are deliberately **checksum-free**: every code is resolved
/// server-side (spec §8 open question #2 — relayer-hosted code→address
/// table), so the resolver is already an authoritative validity check, and a
/// mistyped-but-well-formed code simply fails to resolve. A Crockford check
/// symbol would buy earlier feedback at the cost of a 7th character on every
/// shared code; if it is ever wanted, it can be added behind the same `TES-`
/// prefix without breaking this grammar.
CodeTarget? tryParseJoinCode(String input) {
  final s = input.trim().toUpperCase();
  if (!s.startsWith('TES')) return null;
  var body = s.substring(3);
  if (body.startsWith('-')) body = body.substring(1);
  if (body.length != 6) return null;
  final buf = StringBuffer();
  for (final ch in body.split('')) {
    final folded = switch (ch) {
      'O' => '0',
      'I' || 'L' => '1',
      _ => ch,
    };
    if (!_crockfordAlphabet.contains(folded)) return null;
    buf.write(folded);
  }
  return CodeTarget(buf.toString());
}

/// Build the canonical Tessera deep-link for a poll — the inverse of
/// [parseJoinInput] for the poll case. The link encodes into a share QR that
/// the grammar reads back to the same typed target:
/// `parseJoinInput(shareLinkForPoll(a, module: m)) == PollTarget(a, module: m)`.
/// Keeping the writer next to the reader makes that round-trip invariant
/// local (lifted as-is from `codes/mobile`).
String shareLinkForPoll(String address, {String? module}) {
  final q = (module != null && module.isNotEmpty) ? '?module=$module' : '';
  return 'tessera://poll/$address$q';
}
