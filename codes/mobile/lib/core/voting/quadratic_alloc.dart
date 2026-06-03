/// Packed-allocation encode/decode + credit-cost helpers for the M5 quadratic
/// voting module (`quadratic-vote`).
///
/// Mirror of `ZkQuadraticVoting.sol` (Phase 12c). A quadratic ballot is an
/// allocation vector `v` packed into 4-bit slots: `vᵢ` is the number of VOTES
/// the voter casts for option `i`, and slot `i` is bits `[4*i, 4*i+4)`, so
/// `vᵢ = (packedAlloc >> (4*i)) & 0xF` (range `[0,15]`). Casting `vᵢ` votes for
/// option `i` costs `vᵢ²`; the ballot is valid iff `Σ vᵢ² ≤ CREDITS`.
///
/// CRITICAL — this is a DIRECT encoding (slot `i` ⇒ option `i`), NOT the
/// ranked module's `optionIndex + 1`. Here `0` is a perfectly valid allocation
/// (spend nothing on option `i`); a ballot is empty only when EVERY slot is `0`
/// (the contract's `EmptyBallot`). So [unpackAlloc] reads ALL `optionCount`
/// slots — it MUST NOT break on the first zero the way the ranked codec does
/// for its contiguous prefix.
///
/// 8 slots × 4 bits = 32 bits ⇒ `packedAlloc < 2^32`, which keeps
/// `Number(message)` exact in the JS web prover (IEEE-754 double, 53-bit
/// integer precision). The caller passes the packed allocation through as the
/// proof `message`; the contract/relayer reject unless `message == packedAlloc`.
library;

/// Mirror of the contract's `MAX_OPTIONS` — up to 8 allocation slots, 4 bits
/// each, so a packed allocation fits in the low 32 bits (`packedAlloc < 2^32`).
const int kMaxQuadraticOptions = 8;

/// Mirror of the contract's `CREDITS` — the uniform vote-credit budget every
/// voter receives. Valid iff `Σ vᵢ² ≤ CREDITS`. 100 caps a single option at
/// `v = 10` (10² = 100), well under the 4-bit field max of 15.
const int kQuadraticCredits = 100;

/// The inclusive upper bound on a single 4-bit allocation slot (`vᵢ ∈ [0,15]`).
const int kMaxSlotVotes = 15;

/// The exclusive upper bound on a valid packed allocation: `1 << 32`.
/// 8 slots × 4 bits = 32 bits.
const int kPackedAllocBound = 1 << (4 * kMaxQuadraticOptions);

/// Pack an allocation vector [votes] (direct slots: `votes[i]` = votes for
/// option `i`) into the packed `uint32` the contract / proof `message` expects.
///
/// Encoding (matches the contract EXACTLY): slot `i` occupies bits
/// `[4*i, 4*i+4)`, slot value = `votes[i]` (NO `+1` — this is a direct
/// encoding, unlike the ranked codec). `votes[i] == 0` is a valid allocation.
///
/// Throws if there are more than [kMaxQuadraticOptions] entries or any entry is
/// outside `[0, 15]` (the 4-bit field). Budget validity (`Σ vᵢ² ≤ CREDITS`) is
/// NOT checked here — that is [creditsSpent]'s domain and the contract's job.
int packAlloc(List<int> votes) {
  if (votes.length > kMaxQuadraticOptions) {
    throw ArgumentError(
      'allocation has ${votes.length} entries; max is $kMaxQuadraticOptions',
    );
  }
  var packed = 0;
  for (var i = 0; i < votes.length; i++) {
    final v = votes[i];
    if (v < 0 || v > kMaxSlotVotes) {
      throw ArgumentError('vote $v out of range [0, $kMaxSlotVotes] at slot $i');
    }
    packed |= (v & 0xF) << (4 * i);
  }
  return packed;
}

/// Decode a packed allocation back into the allocation vector for a poll with
/// [optionCount] options.
///
/// Reads EVERY one of the `optionCount` slots low-to-high — it does NOT stop at
/// the first zero (a zero allocation is valid and an internal zero, e.g.
/// `[6,0,8]`, must round-trip). Each slot value `v` decodes to `votes[i] = v`.
/// Inverse of [packAlloc] for any in-range allocation.
List<int> unpackAlloc(int packed, int optionCount) {
  final votes = <int>[];
  for (var i = 0; i < optionCount; i++) {
    votes.add((packed >> (4 * i)) & 0xF);
  }
  return votes;
}

/// The quadratic credit cost of an allocation vector [votes]: `Σ vᵢ²`. This is
/// the value compared against [kQuadraticCredits] (`CREDITS`) — a ballot is
/// valid iff `creditsSpent(votes) ≤ kQuadraticCredits`. Mirrors the contract's
/// `sumSq` exactly.
int creditsSpent(List<int> votes) {
  var sum = 0;
  for (final v in votes) {
    sum += v * v;
  }
  return sum;
}

/// Total VOTES allocated across an allocation vector [votes]: `Σ vᵢ`. A ballot
/// is empty (the contract's `EmptyBallot`) iff this is `0` — i.e. every slot is
/// `0`. Mirrors the contract's `sumV`.
int totalVotes(List<int> votes) {
  var sum = 0;
  for (final v in votes) {
    sum += v;
  }
  return sum;
}
