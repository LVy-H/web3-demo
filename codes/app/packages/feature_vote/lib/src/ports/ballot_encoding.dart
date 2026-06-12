/// Wire encodings for the proof-module ballots — the exact packings the
/// contracts and relayer endpoints verify (mirrors the proven legacy helpers
/// `ranked_irv.packRanking` / `quadratic_alloc.packAlloc`).
library;

/// Ranked + quadratic share the 8-slot × 4-bit packing (`packed < 2^32`).
const int kMaxPackedOptions = 8;

/// Quadratic: a single option's 4-bit slot caps at 15 votes.
const int kMaxSlotVotes = 15;

/// Pack a preference-ordered prefix of option indices into the ranked-vote
/// message: slot `i` (bits `[4i, 4i+4)`) holds `option + 1` (0 = empty slot).
///
/// Example (3 options): `[2, 0, 1]` (C > A > B) → `0x213` = 531.
int packRanking(List<int> ordering) {
  if (ordering.length > kMaxPackedOptions) {
    throw ArgumentError(
      'ranking has ${ordering.length} entries; max is $kMaxPackedOptions',
    );
  }
  var packed = 0;
  for (var i = 0; i < ordering.length; i++) {
    final option = ordering[i];
    if (option < 0 || option >= kMaxPackedOptions) {
      throw ArgumentError(
        'option index $option out of range [0, $kMaxPackedOptions)',
      );
    }
    packed |= (option + 1) << (4 * i);
  }
  return packed;
}

/// Pack a quadratic allocation into the quadratic-vote message: slot `i`
/// holds option `i`'s votes DIRECTLY (no +1 — unlike [packRanking]).
int packAlloc(List<int> votes) {
  if (votes.length > kMaxPackedOptions) {
    throw ArgumentError(
      'allocation has ${votes.length} entries; max is $kMaxPackedOptions',
    );
  }
  var packed = 0;
  for (var i = 0; i < votes.length; i++) {
    final v = votes[i];
    if (v < 0 || v > kMaxSlotVotes) {
      throw ArgumentError('vote $v out of range [0, $kMaxSlotVotes] at $i');
    }
    packed |= (v & 0xF) << (4 * i);
  }
  return packed;
}
