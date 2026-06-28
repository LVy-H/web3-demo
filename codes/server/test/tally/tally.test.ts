import { describe, it, expect } from "vitest";
import { tally, creditsSpent } from "../../src/tally";
import type { BallotPayload } from "../../src/tally";

describe("tally — single (plurality counts)", () => {
  it("counts one vote per ballot for its chosen option", () => {
    const ballots: BallotPayload[] = [
      { kind: "single", choice: 0 },
      { kind: "single", choice: 1 },
      { kind: "single", choice: 0 },
      { kind: "single", choice: 2 },
    ];
    const t = tally("single", ballots, 3);
    expect(t.method).toBe("single");
    expect(t.optionScores).toEqual([2, 1, 1]);
    expect(t.abstain).toBe(0);
    expect(t.totalCast).toBe(4);
    expect(t.rounds).toBeUndefined();
  });

  it("skips abstain ballots in scoring but counts them", () => {
    const ballots: BallotPayload[] = [
      { kind: "single", choice: 0 },
      { kind: "abstain" },
      { kind: "single", choice: 1 },
      { kind: "abstain" },
    ];
    const t = tally("single", ballots, 2);
    expect(t.optionScores).toEqual([1, 1]);
    expect(t.abstain).toBe(2);
    // totalCast counts every ballot, abstain included
    expect(t.totalCast).toBe(4);
  });

  it("ignores out-of-range single choices in scoring", () => {
    const ballots: BallotPayload[] = [
      { kind: "single", choice: 5 }, // out of range for optionCount=2
      { kind: "single", choice: 0 },
    ];
    const t = tally("single", ballots, 2);
    expect(t.optionScores).toEqual([1, 0]);
    expect(t.totalCast).toBe(2);
  });
});

describe("tally — approval / survey (multi-select aggregate)", () => {
  it("counts one per approved option, multiple per ballot", () => {
    const ballots: BallotPayload[] = [
      { kind: "approval", choices: [0, 1] },
      { kind: "approval", choices: [1, 2] },
      { kind: "approval", choices: [1] },
    ];
    const t = tally("approval", ballots, 3);
    expect(t.optionScores).toEqual([1, 3, 1]);
    expect(t.totalCast).toBe(3);
    expect(t.abstain).toBe(0);
  });

  it("dedupes repeated approvals within one ballot", () => {
    const ballots: BallotPayload[] = [{ kind: "approval", choices: [0, 0, 1] }];
    const t = tally("approval", ballots, 2);
    expect(t.optionScores).toEqual([1, 1]);
  });

  it("survey aggregates exactly like approval", () => {
    const ballots: BallotPayload[] = [
      { kind: "survey", choices: [0, 2] },
      { kind: "survey", choices: [2] },
      { kind: "abstain" },
    ];
    const t = tally("survey", ballots, 3);
    expect(t.method).toBe("survey");
    expect(t.optionScores).toEqual([1, 0, 2]);
    expect(t.abstain).toBe(1);
    expect(t.totalCast).toBe(3);
  });

  it("an empty approval ballot scores nothing but still counts as cast", () => {
    const ballots: BallotPayload[] = [{ kind: "approval", choices: [] }];
    const t = tally("approval", ballots, 2);
    expect(t.optionScores).toEqual([0, 0]);
    expect(t.abstain).toBe(0);
    expect(t.totalCast).toBe(1);
  });
});

describe("tally — quadratic (votes vector, ported from quadratic_alloc.dart)", () => {
  // A quadratic ballot is the votes vector vᵢ directly; casting vᵢ votes for
  // option i costs vᵢ² credits (Σvᵢ² ≤ QUADRATIC_CREDITS, checked at cast time).
  // The tally simply SUMS votes per option.
  it("sums the votes vector per option", () => {
    const ballots: BallotPayload[] = [{ kind: "quadratic", votes: [3, 2, 1] }];
    const t = tally("quadratic", ballots, 3);
    expect(t.optionScores).toEqual([3, 2, 1]);
    expect(t.totalCast).toBe(1);
  });

  it("aggregates votes across many quadratic ballots", () => {
    const ballots: BallotPayload[] = [
      { kind: "quadratic", votes: [10, 0] },
      { kind: "quadratic", votes: [0, 10] },
      { kind: "quadratic", votes: [7, 7] },
      { kind: "abstain" },
    ];
    const t = tally("quadratic", ballots, 2);
    expect(t.optionScores).toEqual([17, 17]);
    expect(t.abstain).toBe(1);
    expect(t.totalCast).toBe(4);
  });

  it("ignores vote entries beyond optionCount", () => {
    const ballots: BallotPayload[] = [{ kind: "quadratic", votes: [2, 3, 9] }];
    const t = tally("quadratic", ballots, 2);
    expect(t.optionScores).toEqual([2, 3]);
  });

  it("creditsSpent computes Σvᵢ² for the cast-time budget check", () => {
    expect(creditsSpent([3, 2, 1])).toBe(14); // 9 + 4 + 1
    expect(creditsSpent([10, 0])).toBe(100);
    expect(creditsSpent([7, 7])).toBe(98);
  });
});

describe("tally — ranked IRV (ported from ranked_irv.dart)", () => {
  it("single round: strict majority on first preferences wins immediately", () => {
    const ballots: BallotPayload[] = [
      { kind: "ranked", ranking: [0, 1] },
      { kind: "ranked", ranking: [0, 2] },
      { kind: "ranked", ranking: [0] },
      { kind: "ranked", ranking: [1, 0] },
    ];
    // option0 has 3/4 → 2*3 > 4 → wins round 1
    const t = tally("ranked", ballots, 3);
    expect(t.winner).toBe(0);
    expect(t.rounds).toBeDefined();
    expect(t.rounds!.length).toBe(1);
    expect(t.rounds![0].winner).toBe(0);
    expect(t.rounds![0].counts).toEqual([3, 1, 0]);
    expect(t.rounds![0].continuingBallots).toBe(4);
  });

  it("multi-round: first-preference leader is NOT the IRV winner", () => {
    // Classic come-from-behind: A leads round 1 but loses after C is eliminated.
    // 5 ballots, 3 options A=0,B=1,C=2.
    //  2× A
    //  2× B > C  (so C transfers to B)
    //  1× C > B
    // Round1 counts: A=2 B=2 C=1, C=5 → no majority (2*2=4 !> 5). Eliminate C (fewest).
    // Round2: A=2, B = 2+1=3 → 2*3=6 > 5 → B wins.
    const ballots: BallotPayload[] = [
      { kind: "ranked", ranking: [0] },
      { kind: "ranked", ranking: [0] },
      { kind: "ranked", ranking: [1, 2] },
      { kind: "ranked", ranking: [1, 2] },
      { kind: "ranked", ranking: [2, 1] },
    ];
    const t = tally("ranked", ballots, 3);
    expect(t.winner).toBe(1);
    expect(t.rounds!.length).toBe(2);
    expect(t.rounds![0].counts).toEqual([2, 2, 1]);
    expect(t.rounds![0].continuingBallots).toBe(5);
    expect(t.rounds![0].eliminated).toBe(2);
    expect(t.rounds![0].winner).toBeUndefined();
    expect(t.rounds![1].counts).toEqual([2, 3, 0]);
    expect(t.rounds![1].winner).toBe(1);
  });

  it("elimination tie broken by lowest option index", () => {
    // Options 0,1,2. Round1: 0→1, 1→1, 2→2. Tie for fewest between 0 and 1 → eliminate 0.
    const ballots: BallotPayload[] = [
      { kind: "ranked", ranking: [0, 2] },
      { kind: "ranked", ranking: [1, 2] },
      { kind: "ranked", ranking: [2] },
      { kind: "ranked", ranking: [2] },
    ];
    const t = tally("ranked", ballots, 3);
    expect(t.rounds![0].counts).toEqual([1, 1, 2]);
    expect(t.rounds![0].eliminated).toBe(0); // lowest index among tied-fewest
    // Round2: ballot [0,2]→2, so 2 gets 3, 1 gets 1. 2*3=6 > 4 → 2 wins
    expect(t.winner).toBe(2);
  });

  it("strict majority: exactly half does NOT win (2*v > C, never >=)", () => {
    // 4 ballots: A=0 gets 2 first-prefs, B=1 gets 1, C=2 gets 1.
    // 2*2=4 is NOT > 4, so no round-1 win; eliminate C, then transfer.
    const ballots: BallotPayload[] = [
      { kind: "ranked", ranking: [0] },
      { kind: "ranked", ranking: [0] },
      { kind: "ranked", ranking: [1, 0] },
      { kind: "ranked", ranking: [2, 0] },
    ];
    const t = tally("ranked", ballots, 3);
    // round1: A=2 B=1 C=1, C=4. 2*2 !> 4. eliminate C(2) — wait fewest is tie B,C at 1 → eliminate B(1)? lowest index = 1
    // counts [2,1,1]; fewest=1 tied between 1 and 2 → eliminate option 1.
    expect(t.rounds![0].eliminated).toBe(1);
    // round2: ballot [1,0]→0, A=3, C=1 → 2*3=6>4 → A wins
    expect(t.winner).toBe(0);
  });

  it("exhausted ballots drop out of C", () => {
    // 3 ballots: [0], [1], [2] over 3 options. all tied at 1, C=3, no majority.
    // eliminate 0 (lowest). round2: ballot [0] exhausted (no continuing rank), C=2.
    const ballots: BallotPayload[] = [
      { kind: "ranked", ranking: [0] },
      { kind: "ranked", ranking: [1] },
      { kind: "ranked", ranking: [2] },
    ];
    const t = tally("ranked", ballots, 3);
    expect(t.rounds![0].eliminated).toBe(0);
    // round2: 1→1, 2→1, C=2 (ballot [0] exhausted). no strict majority (2*1 !> 2). eliminate 1.
    expect(t.rounds![1].continuingBallots).toBe(2);
    expect(t.rounds![1].eliminated).toBe(1);
    // round3: only 2 continuing, 2 has 1 vote → last-standing winner.
    expect(t.winner).toBe(2);
  });

  it("empty input yields null winner and no rounds", () => {
    const t = tally("ranked", [], 3);
    expect(t.winner).toBeNull();
    expect(t.rounds).toEqual([]);
    expect(t.totalCast).toBe(0);
  });

  it("ranked optionScores expose round-1 first-preference counts", () => {
    const ballots: BallotPayload[] = [
      { kind: "ranked", ranking: [0] },
      { kind: "ranked", ranking: [1, 0] },
      { kind: "ranked", ranking: [1] },
    ];
    const t = tally("ranked", ballots, 2);
    // first-preference tally: 0→1, 1→2
    expect(t.optionScores).toEqual([1, 2]);
  });

  it("counts abstain ballots and excludes them from IRV", () => {
    const ballots: BallotPayload[] = [
      { kind: "ranked", ranking: [0] },
      { kind: "abstain" },
      { kind: "ranked", ranking: [0, 1] },
    ];
    const t = tally("ranked", ballots, 2);
    expect(t.abstain).toBe(1);
    expect(t.totalCast).toBe(3);
    expect(t.winner).toBe(0);
  });
});
