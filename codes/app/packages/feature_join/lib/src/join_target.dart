/// The typed result of parsing a JOIN input (scanned QR, pasted link, typed
/// code). Spec §4.1: JOIN is the universal entry — every value a user brings
/// to the app resolves to exactly one of these.
///
/// This is deliberately *not* a route: mapping a [JoinTarget] to a navigation
/// location belongs to the app shell's router layer (R3). Keeping the grammar
/// output typed lets the router, the journey engine, and tests all consume
/// the same parse without string-splitting route fragments.
///
/// All subtypes are immutable value types with structural equality, so tests
/// and reducers can compare them directly.
sealed class JoinTarget {
  const JoinTarget();
}

/// A poll deep-link: `tessera://poll/<address>[?module=<id>]` (or the
/// https mirror). [module] is the legacy `?module=` hint carried for
/// backward compatibility with QR codes already in the wild; the R2/R3
/// single-route resolver re-derives the module on-chain and may ignore it.
final class PollTarget extends JoinTarget {
  const PollTarget(this.address, {this.module});

  /// The poll contract address, exactly as it appeared in the link.
  final String address;

  /// Optional module hint (`anon-vote`, `ranked-vote`, …); `null` when the
  /// link carried none (an empty `?module=` is treated as none).
  final String? module;

  @override
  bool operator ==(Object other) =>
      other is PollTarget && other.address == address && other.module == module;

  @override
  int get hashCode => Object.hash(PollTarget, address, module);

  @override
  String toString() => 'PollTarget($address, module: $module)';
}

/// A live-meeting voter ticket: `tessera://live/<address>/vote[?t=<wire>]`.
/// [ticket] is the host-issued wire ticket (`?t=`); it can be absent when a
/// voter follows a bare live link and will authenticate in-session.
final class LiveVoteTarget extends JoinTarget {
  const LiveVoteTarget(this.address, {this.ticket});

  /// The live poll contract address.
  final String address;

  /// The host-issued ticket payload (`?t=`), or `null` when not present.
  final String? ticket;

  @override
  bool operator ==(Object other) =>
      other is LiveVoteTarget &&
      other.address == address &&
      other.ticket == ticket;

  @override
  int get hashCode => Object.hash(LiveVoteTarget, address, ticket);

  @override
  String toString() => 'LiveVoteTarget($address, ticket: $ticket)';
}

/// The live-meeting host console: `tessera://live/<address>/host`.
final class LiveHostTarget extends JoinTarget {
  const LiveHostTarget(this.address);

  /// The live poll contract address.
  final String address;

  @override
  bool operator ==(Object other) =>
      other is LiveHostTarget && other.address == address;

  @override
  int get hashCode => Object.hash(LiveHostTarget, address);

  @override
  String toString() => 'LiveHostTarget($address)';
}

/// A receipt-verification link: `tessera://verify?poll=<addr>&nullifier=<n>`.
/// Both fields are nullable because shared links may carry either half (the
/// verify surface prompts for whatever is missing) — the legacy grammar
/// likewise passed partial queries through.
final class VerifyTarget extends JoinTarget {
  const VerifyTarget({this.poll, this.nullifier});

  /// The poll contract address (`?poll=`), if present.
  final String? poll;

  /// The receipt nullifier (`?nullifier=`), if present.
  final String? nullifier;

  @override
  bool operator ==(Object other) =>
      other is VerifyTarget &&
      other.poll == poll &&
      other.nullifier == nullifier;

  @override
  int get hashCode => Object.hash(VerifyTarget, poll, nullifier);

  @override
  String toString() => 'VerifyTarget(poll: $poll, nullifier: $nullifier)';
}

/// A short join-code (`TES-XXXXXX`, spec §4.1 "type a short code").
///
/// [code] is the *normalized* 6-symbol Crockford-base32 body: uppercase,
/// hyphen stripped, decode aliases folded (`O`→`0`, `I`/`L`→`1`). Resolution
/// of a code to a poll address is server-side (spec §8 open question #2 —
/// relayer-hosted table is the pragmatic v1); this package only validates
/// and normalizes the format.
final class CodeTarget extends JoinTarget {
  const CodeTarget(this.code);

  /// The normalized 6-character code body (no `TES-` prefix).
  final String code;

  /// The canonical display/share form, e.g. `TES-7Q4MZ2`.
  String get canonical => 'TES-$code';

  @override
  bool operator ==(Object other) => other is CodeTarget && other.code == code;

  @override
  int get hashCode => Object.hash(CodeTarget, code);

  @override
  String toString() => 'CodeTarget($canonical)';
}

/// Anything the grammar could not understand. The parser is total — it never
/// throws — so unrecognized, malformed, or hostile input always lands here
/// with a short human-readable [reason] the JOIN surface can show.
final class UnknownTarget extends JoinTarget {
  const UnknownTarget(this.reason);

  /// Why the input was rejected (stable enough for logging; UI copy is the
  /// JOIN surface's job).
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is UnknownTarget && other.reason == reason;

  @override
  int get hashCode => Object.hash(UnknownTarget, reason);

  @override
  String toString() => 'UnknownTarget($reason)';
}
