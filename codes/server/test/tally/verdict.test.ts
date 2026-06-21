import { describe, it, expect } from "vitest";
import { tally, verdict } from "../../src/tally";
import type { BallotPayload, Rule } from "../../src/tally";

function single(choices: number[], optionCount: number) {
  const ballots: BallotPayload[] = choices.map((c) => ({ kind: "single", choice: c }));
  return tally("single", ballots, optionCount);
}

describe("verdict — quorum (checked first, against the denominator)", () => {
  it("turnout below quorum → quorum-not-met regardless of threshold", () => {
    const t = single([0, 0, 0], 2); // 3 cast
    const rule: Rule = {
      threshold: { kind: "majority" },
      quorum: 5, // need 5 of the denominator
      tieBreak: "declare",
    };
    // denominator = eligible = 10 → turnout 3 < 5
    expect(verdict(t, rule, 10).outcome).toBe("quorum-not-met");
  });

  it("turnout exactly at quorum is met (>=)", () => {
    const t = single([0, 0, 0, 0, 0], 2); // 5 cast, all option0
    const rule: Rule = {
      threshold: { kind: "majority" },
      quorum: 5,
      tieBreak: "declare",
    };
    // 5 cast >= quorum 5 → proceeds; option0 has 5/5 > 50% → carried
    expect(verdict(t, rule, 10).outcome).toBe("carried");
  });

  it("no quorum set → never quorum-not-met", () => {
    const t = single([0], 2);
    const rule: Rule = { threshold: { kind: "plurality" }, tieBreak: "declare" };
    expect(verdict(t, rule, 1000).outcome).not.toBe("quorum-not-met");
  });
});

describe("verdict — majority threshold (> 50% of non-abstain cast)", () => {
  it("strictly more than half → carried", () => {
    const t = single([0, 0, 0, 1], 2); // 3 of 4 for option0
    const rule: Rule = { threshold: { kind: "majority" }, tieBreak: "declare" };
    const v = verdict(t, rule, 4);
    expect(v.outcome).toBe("carried");
    expect(v.winner).toBe(0);
  });

  it("exactly 50% does NOT carry (majority is strict)", () => {
    const t = single([0, 0, 1, 1], 2); // 2 of 4 → exactly 50%
    const rule: Rule = { threshold: { kind: "majority" }, tieBreak: "declare" };
    const v = verdict(t, rule, 4);
    // top two tied at 50% → not a strict majority → tie path → declare → tie
    expect(v.outcome).toBe("tie");
  });

  it("majority denominator excludes abstain ballots", () => {
    const ballots: BallotPayload[] = [
      { kind: "single", choice: 0 },
      { kind: "single", choice: 0 },
      { kind: "abstain" },
    ];
    const t = tally("single", ballots, 2);
    const rule: Rule = { threshold: { kind: "majority" }, tieBreak: "declare" };
    // non-abstain cast = 2; option0 = 2 → 2 > 1 → carried (abstain not in denominator)
    expect(verdict(t, rule, 3).outcome).toBe("carried");
  });
});

describe("verdict — supermajority threshold (>= percent% of non-abstain cast)", () => {
  it("at exactly the percent boundary → carried (>=)", () => {
    const t = single([0, 0, 1], 2); // option0 = 2/3 = 66.66%
    const rule: Rule = {
      threshold: { kind: "supermajority", percent: 66 },
      tieBreak: "declare",
    };
    // 2/3 = 66.66% >= 66% → carried
    expect(verdict(t, rule, 3).outcome).toBe("carried");
  });

  it("just below the percent boundary → failed", () => {
    const t = single([0, 0, 1], 2); // option0 = 66.66%
    const rule: Rule = {
      threshold: { kind: "supermajority", percent: 67 },
      tieBreak: "declare",
    };
    // 66.66% < 67% → failed
    expect(verdict(t, rule, 3).outcome).toBe("failed");
  });

  it("two-thirds supermajority boundary exact (4 of 6 = 66.66 < 66.67? use 66)", () => {
    const t = single([0, 0, 0, 0, 1, 1], 2); // 4/6 = 66.66%
    const rule: Rule = {
      threshold: { kind: "supermajority", percent: 66 },
      tieBreak: "declare",
    };
    expect(verdict(t, rule, 6).outcome).toBe("carried");
  });

  it("H1: unanimous (3/3) under a 60% rule → carried", () => {
    const t = single([0, 0, 0], 2); // option0 = 3/3 = 100%
    const rule: Rule = {
      threshold: { kind: "supermajority", percent: 60 },
      tieBreak: "declare",
    };
    expect(verdict(t, rule, 3).outcome).toBe("carried");
  });

  it("H1: a clear leader below the bar (2 of 4 = 50%) under a 60% rule → failed", () => {
    // scores [2,1,1] → option0 is the unique leader at 2/4 = 50% < 60% → failed.
    const t = single([0, 0, 1, 2], 3);
    const rule: Rule = {
      threshold: { kind: "supermajority", percent: 60 },
      tieBreak: "declare",
    };
    expect(verdict(t, rule, 4).outcome).toBe("failed");
  });

  it("H1: a supermajority rule with NO percent throws (fail loud, not silently false)", () => {
    const t = single([0, 0, 0], 2); // unanimous — would have to carry if percent existed
    // The oracle is reused by the Phase-3 verifier on arbitrary data, so an
    // ill-formed rule must fail loud instead of computing max*100 >= NaN (false)
    // and silently reporting 'failed' on a unanimous vote.
    const rule = {
      threshold: { kind: "supermajority" },
      tieBreak: "declare",
    } as unknown as Rule;
    expect(() => verdict(t, rule, 3)).toThrow(/supermajority/i);
  });
});

describe("verdict — plurality threshold (top option wins, ties → tieBreak)", () => {
  it("clear top option → carried even below 50%", () => {
    const t = single([0, 0, 1, 2], 3); // option0=2, others 1 each (40%)
    const rule: Rule = { threshold: { kind: "plurality" }, tieBreak: "declare" };
    const v = verdict(t, rule, 4);
    expect(v.outcome).toBe("carried");
    expect(v.winner).toBe(0);
  });

  it("tie at the top → resolved per tieBreak", () => {
    const t = single([0, 1], 2); // 1 each
    const rule: Rule = { threshold: { kind: "plurality" }, tieBreak: "declare" };
    expect(verdict(t, rule, 2).outcome).toBe("tie");
  });
});

describe("verdict — tie-break paths", () => {
  const tied = () => single([0, 1], 2); // perfect tie at top

  it("declare → tie", () => {
    const v = verdict(tied(), { threshold: { kind: "plurality" }, tieBreak: "declare" }, 2);
    expect(v.outcome).toBe("tie");
  });

  it("runoff → tie with a runoff signal and tied options", () => {
    const v = verdict(tied(), { threshold: { kind: "plurality" }, tieBreak: "runoff" }, 2);
    expect(v.outcome).toBe("tie");
    expect(v.runoff).toBe(true);
    expect(v.tiedOptions).toEqual([0, 1]);
  });

  it("casting → tie needing the convener casting vote", () => {
    const v = verdict(tied(), { threshold: { kind: "plurality" }, tieBreak: "casting" }, 2);
    expect(v.outcome).toBe("tie");
    expect(v.needsCastingVote).toBe(true);
    expect(v.tiedOptions).toEqual([0, 1]);
  });

  it("random-seed → deterministic carried pick from the seed", () => {
    const rule: Rule = {
      threshold: { kind: "plurality" },
      tieBreak: "random-seed",
      seed: "tessera-public-seed-xyz",
    };
    const v1 = verdict(tied(), rule, 2);
    const v2 = verdict(tied(), rule, 2);
    expect(v1.outcome).toBe("carried");
    expect([0, 1]).toContain(v1.winner);
    // deterministic: same seed + same tie → same winner
    expect(v2.winner).toBe(v1.winner);
    expect(v1.tiedOptions).toEqual([0, 1]);
  });

  it("random-seed with a different seed may pick the other tied option", () => {
    const mk = (seed: string): Rule => ({
      threshold: { kind: "plurality" },
      tieBreak: "random-seed",
      seed,
    });
    // both deterministic; assert each is a valid tied option and stable
    const a = verdict(tied(), mk("seed-A"), 2).winner;
    const b = verdict(tied(), mk("seed-A"), 2).winner;
    expect(a).toBe(b);
    expect([0, 1]).toContain(a);
  });
});

describe("verdict — abstain-only and empty edges", () => {
  it("all abstain → no non-abstain cast → failed (no winner) under majority", () => {
    const ballots: BallotPayload[] = [{ kind: "abstain" }, { kind: "abstain" }];
    const t = tally("single", ballots, 2);
    const rule: Rule = { threshold: { kind: "majority" }, tieBreak: "declare" };
    expect(verdict(t, rule, 2).outcome).toBe("failed");
  });

  it("all abstain but a quorum is set and unmet → quorum-not-met takes precedence", () => {
    const ballots: BallotPayload[] = [{ kind: "abstain" }];
    const t = tally("single", ballots, 2);
    const rule: Rule = { threshold: { kind: "majority" }, quorum: 2, tieBreak: "declare" };
    // turnout = totalCast = 1 (abstain counts toward turnout) < quorum 2
    expect(verdict(t, rule, 10).outcome).toBe("quorum-not-met");
  });
});

describe("verdict — ranked method uses IRV winner", () => {
  it("carries the IRV winner regardless of round-1 leader", () => {
    const ballots: BallotPayload[] = [
      { kind: "ranked", ranking: [0] },
      { kind: "ranked", ranking: [0] },
      { kind: "ranked", ranking: [1, 2] },
      { kind: "ranked", ranking: [1, 2] },
      { kind: "ranked", ranking: [2, 1] },
    ];
    const t = tally("ranked", ballots, 3);
    // IRV winner is option 1 (come-from-behind)
    const rule: Rule = { threshold: { kind: "majority" }, tieBreak: "declare" };
    const v = verdict(t, rule, 5);
    expect(v.outcome).toBe("carried");
    expect(v.winner).toBe(1);
  });
});
