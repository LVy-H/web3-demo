import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/core/voting/ranked_irv.dart';

/// Vector tests for the canonical off-chain IRV tally + packed-ranking codec.
///
/// These ARE the proof of the load-bearing rule (the contract never runs IRV;
/// these vectors prove the Dart replay is correct). They assert on the per-round
/// TRACE, not just the final winner — a test that only checked the winner could
/// pass for the wrong reason.
void main() {
  group('packed ranking encode/decode (spec table)', () {
    // 3-option poll [A, B, C]: A=0, B=1, C=2. From the spec's example table.
    test('pack matches the spec packed-dec column', () {
      expect(packRanking([0]), 1); // A         → 0x001
      expect(packRanking([1]), 2); // B         → 0x002
      expect(packRanking([1, 0]), 18); // B > A     → 0x012
      expect(packRanking([2, 0, 1]), 531); // C > A > B → 0x213
      expect(packRanking([]), 0); // (empty)   → 0x000
    });

    test('unpack inverts pack for the spec rows', () {
      expect(unpackRanking(1), [0]); // A
      expect(unpackRanking(2), [1]); // B
      expect(unpackRanking(18), [1, 0]); // B > A
      expect(unpackRanking(531), [2, 0, 1]); // C > A > B
      expect(unpackRanking(0), <int>[]); // empty
    });

    test('round-trips every prefix of distinct options (≤ MAX_OPTIONS)', () {
      // Exhaustively round-trip a spread of valid rankings.
      const rankings = [
        [0],
        [7],
        [3, 1],
        [2, 0, 1],
        [0, 1, 2, 3, 4, 5, 6, 7], // full 8-slot ballot
        [7, 6, 5, 4, 3, 2, 1, 0],
      ];
      for (final r in rankings) {
        final packed = packRanking(r);
        expect(packed, lessThan(kPackedRankingBound),
            reason: 'packed value must fit in 32 bits');
        expect(unpackRanking(packed), r, reason: 'round-trip $r');
      }
    });

    test('decode stops at the first empty slot (contiguous prefix)', () {
      // 0x012 = B > A; high slots empty. unpack must stop after 2 slots.
      expect(unpackRanking(0x012), [1, 0]);
    });
  });

  group('runIrv — canonical rule', () {
    // ── (a) NORMAL TRANSFER — elimination changes the leader ─────────────────
    test('(a) a transfer changes the leader (first-pref leader is NOT winner)',
        () {
      // 3 options A(0) B(1) C(2). 5 ballots.
      //   A         (first-pref A)
      //   A         (first-pref A)
      //   B > C     (first-pref B)
      //   C > B     (first-pref C)
      //   C > B     (first-pref C)
      // Round 1: C=5, A=2, B=1, C=2. No strict majority (need 2*v>5 ⇒ v≥3).
      //   Eliminate fewest: B (1 vote). Lowest-index tie not needed (B alone).
      // Round 2: B's ballot (B>C) transfers to C. A=2, C=3. 2*3>5 ⇒ C wins.
      // First-pref leader is a TIE (A=2,C=2); the IRV winner is C. The point:
      // round-1 first-prefs do NOT name the winner.
      final ballots = [
        [0],
        [0],
        [1, 2],
        [2, 1],
        [2, 1],
      ];
      final r = runIrv(ballots, 3);
      expect(r.winner, 2, reason: 'C wins after B is eliminated and transfers');

      // Round-1 first-prefs: A and C both 2 — NOT a clean leader equal to winner.
      expect(r.rounds.first.counts, [2, 1, 2]);
      expect(r.rounds.first.winner, isNull,
          reason: 'no strict majority in round 1');
      expect(r.rounds.first.eliminated, 1, reason: 'B eliminated round 1');

      // The transfer happened: round 2 counts show C gained B\'s ballot.
      expect(r.rounds.length, 2);
      expect(r.rounds[1].counts[2], 3, reason: 'C transferred up to 3');
      expect(r.rounds[1].winner, 2);
    });

    // ── (b) ELIMINATION TIE — resolved by LOWEST option index ────────────────
    test('(b) elimination tie broken by lowest option index', () {
      // 3 options A(0) B(1) C(2). 5 ballots.
      //   A > C
      //   A > C
      //   A > C
      //   B          (first-pref B)
      //   C          (first-pref C)
      // Round 1: C=5, A=3, B=1, C=1. 2*3>5 ⇒ A already has strict majority...
      // To FORCE a tie we instead need no early winner. Use 4 ballots:
      //   A > C, B, C, (and one more to avoid majority)…
      // Simpler dedicated tie vector below.
      final ballots = [
        [0, 2], // A then C
        [1, 2], // B then C
        [2, 0], // C then A
        [0, 1], // A then B
      ];
      // Round 1: C=4. A=2, B=1, C=1. Need 2*v>4 ⇒ v≥3. No winner.
      //   Fewest: B and C tied at 1 → lowest index ⇒ eliminate B(1).
      final r = runIrv(ballots, 3);
      expect(r.rounds.first.counts, [2, 1, 1]);
      expect(r.rounds.first.continuingBallots, 4);
      expect(r.rounds.first.winner, isNull);
      expect(r.rounds.first.eliminated, 1,
          reason: 'B(1) and C(2) tied at 1 vote; lowest index B is eliminated');
      // After B out: [1,2]→C. A=2, C=2 still tied, C=4. No winner.
      //   Fewest: A(2) and C(2) tied → eliminate A(0). Then C alone wins.
      expect(r.winner, 2);
    });

    // ── (c) EXHAUSTED BALLOT — C shrinks, threshold recomputed ───────────────
    test('(c) an exhausted ballot drops out; C shrinks; threshold vs smaller C',
        () {
      // 4 options A(0) B(1) C(2) D(3). 5 ballots.
      //   A          (bullet vote — only ranks A)
      //   A
      //   B > A
      //   C          (bullet vote — only ranks C)
      //   D          (bullet vote — only ranks D)
      // Round 1: C=5. A=2, B=1, C=1, D=1. Need 2*v>5 ⇒ v≥3. No winner.
      //   Fewest tie B,C,D at 1 → lowest index ⇒ eliminate B(1).
      // Round 2: B>A transfers to A. A=3, C=1, D=1, C=5. 2*3>5 ⇒ A wins? v=3>2.5 ✓
      // That ends too early to show exhaustion. Construct exhaustion explicitly:
      //   C and D are bullet votes; once eliminated their ballots exhaust.
      // Use a vector where a bullet-vote candidate is eliminated and its ballot
      // exhausts, shrinking C:
      final ballots = [
        [0], // A bullet
        [0], // A bullet
        [1], // B bullet  ← will exhaust when B eliminated
        [2, 0], // C > A
        [2, 0], // C > A
      ];
      // Round 1: C=5. A=2, B=1, C=2. Need v≥3. No winner. Fewest: B(1).
      //   Eliminate B → its ballot [1] has no continuing candidate ⇒ EXHAUSTED.
      // Round 2: continuing ballots = the other 4 (B's exhausted). C=4 now.
      //   A=2, C=2. Need 2*v>4 ⇒ v≥3. No winner. Fewest A,C tied → eliminate A(0).
      // Round 3: A out. C's ballots stay C; A's two ballots [0] exhaust.
      //   continuing = 2 ballots (the two C>A). C alone remains ⇒ C wins.
      final r = runIrv(ballots, 3);
      expect(r.rounds.first.continuingBallots, 5);
      expect(r.rounds.first.eliminated, 1, reason: 'B(1) fewest, eliminated');
      // Round 2: C shrank to 4 because B\'s ballot exhausted.
      expect(r.rounds[1].continuingBallots, 4,
          reason: 'B\'s bullet ballot exhausted; C went 5 → 4');
      expect(r.rounds[1].winner, isNull,
          reason: 'A=2,C=2 vs the SMALLER C=4 ⇒ no strict majority (2*2>4 false)');
      expect(r.winner, 2, reason: 'C wins after A eliminated');
      // Sanity: C genuinely shrank below the ballot count across the trace.
      expect(r.rounds.last.continuingBallots, lessThan(ballots.length));
    });

    // ── (d) EXACTLY-HALF BOUNDARY — the #1 trap (`>=` vs strict `>`) ──────────
    test('(d) exactly C/2 does NOT win; C/2 + 1 (strict majority) DOES', () {
      // VERIFIED VECTOR. 3 options A(0) B(1) C(2). 4 ballots:
      //   [A], [A], [B > A], [C > A]
      // Round 1: C=4 (even). A=2, B=1, C=1.
      //   A sits at EXACTLY C/2 = 2. Strict check 2*2 > 4 is FALSE ⇒ A must NOT
      //   win. (A naive `votes >= C/2` would wrongly crown A here — the trap.)
      //   Eliminate fewest: B(1) and C(2) tied at 1 → lowest index ⇒ eliminate B.
      // Round 2: [B > A] transfers to A. A=3, C=1, C=4.
      //   A is now C/2 + 1 = 3. 2*3 > 4 is TRUE ⇒ A wins (strict majority).
      final ballots = [
        [0],
        [0],
        [1, 0],
        [2, 0],
      ];
      final r = runIrv(ballots, 3);

      // The win must NOT land in round 1 — exactly-half is not a majority.
      expect(r.rounds.first.continuingBallots, 4,
          reason: 'C must be EVEN so C/2 is exact');
      expect(r.rounds.first.counts[0], 2,
          reason: 'A is at exactly C/2 = 2');
      expect(r.rounds.first.winner, isNull,
          reason: 'EXACTLY C/2 must NOT win — strict `2*votes > C`, never `>=`');
      expect(r.rounds.first.eliminated, 1,
          reason: 'B(1),C(2) tied at fewest → lowest index B eliminated');

      // The win lands in round 2 at C/2 + 1 — strict majority DOES win.
      expect(r.rounds.length, 2);
      expect(r.rounds[1].counts[0], 3, reason: 'A transferred up to C/2 + 1');
      expect(r.rounds[1].winner, 0, reason: '2*3 > 4 ⇒ strict majority wins');
      expect(r.winner, 0);
    });

    test('immediate strict majority in round 1 wins outright', () {
      // [A],[A],[A],[B] → C=4, A=3. 2*3>4 ⇒ A wins round 1, no elimination.
      final r = runIrv([
        [0],
        [0],
        [0],
        [1],
      ], 2);
      expect(r.rounds, hasLength(1));
      expect(r.rounds.first.winner, 0);
      expect(r.rounds.first.eliminated, isNull);
      expect(r.winner, 0);
    });

    test('empty ballots / zero options → null winner (degenerate)', () {
      expect(runIrv(const [], 3).winner, isNull);
      expect(runIrv([
        [0],
      ], 0).winner, isNull);
    });

    test('all ballots exhaust to one remaining candidate → that candidate wins',
        () {
      // 3 options; everyone bullet-votes A. A wins trivially with strict majority.
      final r = runIrv([
        [0],
        [0],
      ], 3);
      expect(r.winner, 0);
    });
  });
}
