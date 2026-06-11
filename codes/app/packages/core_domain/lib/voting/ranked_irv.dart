/// Off-chain instant-runoff (IRV) tally for the M4 ranked-choice module
/// (`ranked-vote`), plus the packed-ranking encode/decode helpers.
///
/// This is the canonical, verifiable replay rule pinned by the design spec
/// (`docs/superpowers/specs/2026-06-02-ranked-choice-design.md`). The contract
/// is storage + a round-1 first-preference tally ONLY — it never runs IRV. Every
/// ballot's full packed ranking is emitted on-chain (`VoteCast(packedRanking)`),
/// so any verifier can decode every ballot and replay [runIrv] to a
/// deterministic winner. Without ONE pinned rule, "verifiable by replay" is
/// false; this module IS that rule, mirrored bit-for-bit in Dart with vector
/// tests.
///
/// NOTHING here treats the round-1 first-preference leader as the outcome — the
/// first-preference leader is frequently NOT the IRV winner (that is the entire
/// point of instant-runoff).
library;

/// Mirror of the contract's `MAX_OPTIONS` — up to 8 rank slots, 4 bits each, so
/// a packed ranking fits in the low 32 bits (`packedRanking < 2^32`). That keeps
/// `Number(message)` exact in the JS web prover (53-bit double precision).
const int kMaxRankedOptions = 8;

/// The exclusive upper bound on a valid packed ranking: `1 << 32`.
/// 8 slots × 4 bits = 32 bits.
const int kPackedRankingBound = 1 << (4 * kMaxRankedOptions);

/// Encode an ordered [ranking] (a list of option indices, most-preferred first)
/// into the packed `uint32` representation the contract / proof `message`
/// expects.
///
/// Encoding (matches the contract + spec table EXACTLY):
///   - slot `i` occupies bits `[4*i, 4*i+4)`,
///   - slot value `0` = empty,
///   - slot value `1..8` = `(option index + 1)` — option `0` encodes as `1`.
///
/// The caller supplies a *prefix of distinct in-range options*; this function
/// only packs. (Prefix / distinct / in-range / no-gap / no-high-bits VALIDATION
/// is the contract's job, deliberately not duplicated here — see the spec.)
///
/// Example (3-option poll `[A, B, C]`): `[2, 0, 1]` (C > A > B) → `0x213` = 531.
int packRanking(List<int> ranking) {
  if (ranking.length > kMaxRankedOptions) {
    throw ArgumentError(
      'ranking has ${ranking.length} entries; max is $kMaxRankedOptions',
    );
  }
  var packed = 0;
  for (var i = 0; i < ranking.length; i++) {
    final option = ranking[i];
    if (option < 0 || option >= kMaxRankedOptions) {
      throw ArgumentError('option index $option out of range [0, $kMaxRankedOptions)');
    }
    // slot value = option index + 1 (option 0 → 1).
    packed |= (option + 1) << (4 * i);
  }
  return packed;
}

/// Decode a packed ranking back into the ordered list of option indices.
///
/// Reads slots low-to-high (slot 0 = most preferred). Stops at the first empty
/// (`0`) slot — a valid ballot is a contiguous prefix, so once a slot is empty
/// the rest are too. Each nonzero slot value `v` decodes to option index
/// `v - 1`. Inverse of [packRanking] for any valid packed ranking.
///
/// Example: `531` (`0x213`) → `[2, 0, 1]` (C > A > B).
List<int> unpackRanking(int packed) {
  final ranking = <int>[];
  for (var i = 0; i < kMaxRankedOptions; i++) {
    final slot = (packed >> (4 * i)) & 0xF;
    if (slot == 0) break; // contiguous prefix — first empty slot ends the ballot
    ranking.add(slot - 1);
  }
  return ranking;
}

/// One round of the IRV trace: the per-option continuing-vote counts this round,
/// the count of continuing (non-exhausted) ballots `C`, and what the round
/// decided (a winner, or which option was eliminated).
class IrvRound {
  /// Per-option vote counts THIS round. Index = option index; an eliminated
  /// option (or one with no continuing first-choice this round) is `0`.
  final List<int> counts;

  /// `C` = number of continuing (non-exhausted) ballots this round. The
  /// strict-majority threshold is computed against THIS `C`, re-derived every
  /// round (never reused from round 1). A ballot all of whose ranked candidates
  /// are eliminated is exhausted and is NOT counted in `C`.
  final int continuingBallots;

  /// The option that won this round via strict majority (`2*votes > C`), or
  /// `null` if no one won and an elimination happened.
  final int? winner;

  /// The option eliminated this round (fewest votes; ties broken by lowest
  /// option index), or `null` if the round produced a winner.
  final int? eliminated;

  const IrvRound({
    required this.counts,
    required this.continuingBallots,
    this.winner,
    this.eliminated,
  });
}

/// The full result of an IRV tally: the winning option index plus the per-round
/// trace (so the UI can show the runoff and the vector tests can assert on
/// intermediate rounds, not just the final winner).
class IrvResult {
  /// The winning option index (the result of replaying the canonical rule), or
  /// `null` only for the degenerate empty-input case (no ballots / no options).
  final int? winner;

  /// The per-round trace, in order.
  final List<IrvRound> rounds;

  const IrvResult({required this.winner, required this.rounds});
}

/// Run the canonical off-chain IRV rule over the decoded [ballots] (each a
/// ranking = ordered list of option indices, most-preferred first) for a poll
/// with [optionCount] options. Returns the winner + per-round trace.
///
/// THE PINNED RULE (mirror this EXACTLY anywhere — the spec is load-bearing):
///   1. Each round, every NON-EXHAUSTED ballot counts for its highest-ranked
///      NOT-YET-ELIMINATED candidate. A ballot whose every ranked candidate is
///      eliminated is EXHAUSTED and drops out of the count.
///   2. `C` = number of continuing (non-exhausted) ballots THIS round —
///      RE-DERIVED every round (never the round-1 `C`).
///   3. WIN if some candidate has STRICTLY more than `C/2` votes. Implemented
///      strictly as `2 * votes > C` (integer-safe) — exactly-half must NOT win.
///   4. Else eliminate the candidate with the FEWEST votes this round;
///      tie-break = LOWEST option index among those tied for fewest. Repeat.
///   5. Terminate when one continuing candidate remains (winner) or a candidate
///      reaches a strict majority.
///
/// Recompute-from-scratch each round (no incremental transfer) for correctness.
/// The win-check runs BEFORE elimination every round, including round 1.
IrvResult runIrv(List<List<int>> ballots, int optionCount) {
  final rounds = <IrvRound>[];
  if (optionCount <= 0 || ballots.isEmpty) {
    return IrvResult(winner: null, rounds: rounds);
  }

  // Options still in the running. Eliminated ⇒ removed from this set.
  final continuing = <int>{for (var i = 0; i < optionCount; i++) i};
  final eliminated = <int>{};

  // Bounded by optionCount: at most optionCount-1 eliminations before one
  // option remains, plus the final win/remaining round.
  while (true) {
    // ── Step 1 & 2: recompute per-option counts + C from scratch ────────────
    final counts = List<int>.filled(optionCount, 0);
    var continuingBallots = 0; // C
    for (final ballot in ballots) {
      // Highest-ranked candidate on this ballot that is NOT eliminated.
      int? choice;
      for (final option in ballot) {
        // Skip any out-of-range index (e.g. from a malformed decoded ballot).
        // Valid on-chain ballots are always in [0, optionCount) — this guard
        // only fires for malformed input; it does NOT change behaviour for
        // valid input.
        if (option < 0 || option >= optionCount) continue;
        if (!eliminated.contains(option)) {
          choice = option;
          break;
        }
      }
      if (choice == null) continue; // exhausted — drops out, not counted in C
      counts[choice]++;
      continuingBallots++;
    }

    // ── Step 3: strict-majority win check (BEFORE any elimination) ───────────
    // `2 * votes > C` — strict majority of continuing ballots. NEVER `>=`.
    for (final option in continuing) {
      if (2 * counts[option] > continuingBallots) {
        rounds.add(IrvRound(
          counts: counts,
          continuingBallots: continuingBallots,
          winner: option,
        ));
        return IrvResult(winner: option, rounds: rounds);
      }
    }

    // ── Step 5 (terminal): one continuing candidate remains ⇒ winner ────────
    // Also rescues the degenerate C==0 case (every ballot exhausted) from an
    // infinite loop.
    if (continuing.length == 1) {
      final option = continuing.first;
      rounds.add(IrvRound(
        counts: counts,
        continuingBallots: continuingBallots,
        winner: option,
      ));
      return IrvResult(winner: option, rounds: rounds);
    }

    // ── Step 4: eliminate the fewest; tie-break = lowest option index ───────
    // Iterate option indices ascending so the FIRST option reaching the minimum
    // count wins the tie (lowest index), and a strictly-smaller count later
    // supersedes it.
    int? loser;
    var fewest = 0;
    for (final option in continuing) {
      final v = counts[option];
      if (loser == null || v < fewest || (v == fewest && option < loser)) {
        loser = option;
        fewest = v;
      }
    }
    eliminated.add(loser!);
    continuing.remove(loser);
    rounds.add(IrvRound(
      counts: counts,
      continuingBallots: continuingBallots,
      eliminated: loser,
    ));
  }
}
