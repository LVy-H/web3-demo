import { describe, it, expect } from "vitest";
import {
  DecisionCreateSchema,
  ballotPayloadSchema,
  type Method,
  type BallotPayload,
  type DecisionCreateInput,
} from "../../src/domain";

// A minimal valid create input we mutate per-case.
function validCreate(): DecisionCreateInput {
  return {
    title: "Adopt the new bylaws?",
    options: ["Yes", "No"],
    method: "single",
    ballotMode: "open",
    resultsPolicy: "sealed",
    eligibility: { method: "open" },
    rule: {
      threshold: { kind: "majority" },
      quorum: 0,
      tieBreak: "declare",
    },
    schedule: {},
    visibility: "listed",
    anchorMode: "broadcast",
  };
}

describe("DecisionCreateSchema — accepts well-formed input", () => {
  it("accepts a minimal valid object", () => {
    const r = DecisionCreateSchema.safeParse(validCreate());
    expect(r.success).toBe(true);
  });

  it("accepts a fully-specified object (passcode eligibility, schedule, maxParticipants)", () => {
    const input = {
      ...validCreate(),
      method: "approval" as Method,
      ballotMode: "secret" as const,
      resultsPolicy: "live" as const,
      options: ["A", "B", "C"],
      eligibility: { method: "passcode", passcode: "hunter2" },
      rule: {
        threshold: { kind: "supermajority", percent: 66.7 },
        quorum: 10,
        tieBreak: "runoff",
      },
      schedule: { opensAt: 1000, closesAt: 2000 },
      visibility: "link-only" as const,
      anchorMode: "chain" as const,
      maxParticipants: 500,
    };
    const r = DecisionCreateSchema.safeParse(input);
    expect(r.success).toBe(true);
  });

  it("defaults / tolerates an omitted optional quorum", () => {
    const input = validCreate();
    delete (input.rule as { quorum?: number }).quorum;
    const r = DecisionCreateSchema.safeParse(input);
    expect(r.success).toBe(true);
  });
});

describe("DecisionCreateSchema — rejects malformed input", () => {
  it("rejects an empty title", () => {
    const r = DecisionCreateSchema.safeParse({ ...validCreate(), title: "" });
    expect(r.success).toBe(false);
  });

  it("rejects fewer than 2 options", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      options: ["only-one"],
    });
    expect(r.success).toBe(false);
  });

  it("rejects an unknown method", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      method: "borda",
    });
    expect(r.success).toBe(false);
  });

  it("rejects an unknown ballotMode", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      ballotMode: "public",
    });
    expect(r.success).toBe(false);
  });

  it("rejects an unknown resultsPolicy", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      resultsPolicy: "open",
    });
    expect(r.success).toBe(false);
  });

  it("rejects an unknown eligibility method", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      eligibility: { method: "biometric" },
    });
    expect(r.success).toBe(false);
  });

  it("L2: rejects stray keys on an eligibility config (strict, no passthrough)", () => {
    // A stray key must NOT be tolerated — otherwise two semantically identical
    // eligibilities could commit different rosterCommitments.
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      eligibility: { method: "open", surprise: "stowaway" },
    });
    expect(r.success).toBe(false);
  });

  it("L2: rejects a passcode eligibility missing its passcode field", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      eligibility: { method: "passcode" },
    });
    expect(r.success).toBe(false);
  });

  it("L2: rejects a domain eligibility carrying a passcode field", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      eligibility: { method: "domain", domain: "example.org", passcode: "x" },
    });
    expect(r.success).toBe(false);
  });

  it("rejects an unknown anchorMode", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      anchorMode: "ipfs",
    });
    expect(r.success).toBe(false);
  });

  it("rejects an unknown visibility", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      visibility: "secret",
    });
    expect(r.success).toBe(false);
  });

  it("rejects a negative quorum", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      rule: { threshold: { kind: "majority" }, quorum: -1, tieBreak: "declare" },
    });
    expect(r.success).toBe(false);
  });

  it("rejects a non-integer quorum", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      rule: { threshold: { kind: "majority" }, quorum: 1.5, tieBreak: "declare" },
    });
    expect(r.success).toBe(false);
  });

  it("rejects an unknown threshold kind", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      rule: { threshold: { kind: "consensus" }, tieBreak: "declare" },
    });
    expect(r.success).toBe(false);
  });

  it("H1: rejects a supermajority threshold missing percent", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      rule: { threshold: { kind: "supermajority" }, tieBreak: "declare" },
    });
    expect(r.success).toBe(false);
    if (!r.success) {
      expect(
        r.error.issues.some(
          (i) => i.path.join(".") === "rule.threshold.percent",
        ),
      ).toBe(true);
    }
  });

  it("H1: accepts a supermajority threshold WITH a valid percent", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      rule: {
        threshold: { kind: "supermajority", percent: 66.7 },
        tieBreak: "declare",
      },
    });
    expect(r.success).toBe(true);
  });

  it("H1: rejects a supermajority percent of 0 (must be in (0, 100])", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      rule: {
        threshold: { kind: "supermajority", percent: 0 },
        tieBreak: "declare",
      },
    });
    expect(r.success).toBe(false);
  });

  it("H1: rejects a supermajority percent above 100", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      rule: {
        threshold: { kind: "supermajority", percent: 100.1 },
        tieBreak: "declare",
      },
    });
    expect(r.success).toBe(false);
  });

  it("rejects an unknown tieBreak", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      rule: { threshold: { kind: "majority" }, tieBreak: "coin-flip" },
    });
    expect(r.success).toBe(false);
  });

  it("rejects maxParticipants <= 0", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      maxParticipants: 0,
    });
    expect(r.success).toBe(false);
  });

  it("rejects a non-integer maxParticipants", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      maxParticipants: 3.5,
    });
    expect(r.success).toBe(false);
  });

  it("rejects a non-integer schedule.opensAt", () => {
    const r = DecisionCreateSchema.safeParse({
      ...validCreate(),
      schedule: { opensAt: 1.2 },
    });
    expect(r.success).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// ballotPayloadSchema(method)
// ---------------------------------------------------------------------------

const ALL_METHODS: Method[] = [
  "single",
  "approval",
  "ranked",
  "quadratic",
  "survey",
];

describe("ballotPayloadSchema — well-formed payloads accepted per method", () => {
  const wellFormed: Record<Method, BallotPayload> = {
    single: { kind: "single", choice: 0 },
    approval: { kind: "approval", choices: [0, 2] },
    ranked: { kind: "ranked", ranking: [2, 0, 1] },
    quadratic: { kind: "quadratic", votes: [1, 4, 0] },
    survey: { kind: "survey", choices: [1] },
  };

  for (const method of ALL_METHODS) {
    it(`${method} accepts its canonical payload`, () => {
      const r = ballotPayloadSchema(method).safeParse(wellFormed[method]);
      expect(r.success).toBe(true);
    });
  }
});

describe("ballotPayloadSchema — 'abstain' accepted for every method", () => {
  for (const method of ALL_METHODS) {
    it(`${method} accepts { kind: 'abstain' }`, () => {
      const r = ballotPayloadSchema(method).safeParse({ kind: "abstain" });
      expect(r.success).toBe(true);
    });
  }
});

describe("ballotPayloadSchema — wrong kind for the method is rejected", () => {
  it("single rejects an approval payload", () => {
    const r = ballotPayloadSchema("single").safeParse({
      kind: "approval",
      choices: [0],
    });
    expect(r.success).toBe(false);
  });

  it("approval rejects a single payload", () => {
    const r = ballotPayloadSchema("approval").safeParse({
      kind: "single",
      choice: 0,
    });
    expect(r.success).toBe(false);
  });

  it("ranked rejects a quadratic payload", () => {
    const r = ballotPayloadSchema("ranked").safeParse({
      kind: "quadratic",
      votes: [1],
    });
    expect(r.success).toBe(false);
  });

  it("quadratic rejects a survey payload", () => {
    const r = ballotPayloadSchema("quadratic").safeParse({
      kind: "survey",
      choices: [0],
    });
    expect(r.success).toBe(false);
  });

  it("survey rejects a ranked payload", () => {
    const r = ballotPayloadSchema("survey").safeParse({
      kind: "ranked",
      ranking: [0],
    });
    expect(r.success).toBe(false);
  });
});

describe("ballotPayloadSchema — malformed payloads rejected", () => {
  it("single rejects a missing choice", () => {
    const r = ballotPayloadSchema("single").safeParse({ kind: "single" });
    expect(r.success).toBe(false);
  });

  it("single rejects a negative choice", () => {
    const r = ballotPayloadSchema("single").safeParse({
      kind: "single",
      choice: -1,
    });
    expect(r.success).toBe(false);
  });

  it("single rejects a non-integer choice", () => {
    const r = ballotPayloadSchema("single").safeParse({
      kind: "single",
      choice: 1.5,
    });
    expect(r.success).toBe(false);
  });

  it("approval rejects a non-array choices", () => {
    const r = ballotPayloadSchema("approval").safeParse({
      kind: "approval",
      choices: 0,
    });
    expect(r.success).toBe(false);
  });

  it("approval rejects a negative index in choices", () => {
    const r = ballotPayloadSchema("approval").safeParse({
      kind: "approval",
      choices: [0, -2],
    });
    expect(r.success).toBe(false);
  });

  it("ranked rejects a non-integer index in ranking", () => {
    const r = ballotPayloadSchema("ranked").safeParse({
      kind: "ranked",
      ranking: [0, 1.5],
    });
    expect(r.success).toBe(false);
  });

  it("quadratic rejects a negative credit", () => {
    const r = ballotPayloadSchema("quadratic").safeParse({
      kind: "quadratic",
      votes: [1, -4],
    });
    expect(r.success).toBe(false);
  });

  it("rejects an unknown kind entirely", () => {
    const r = ballotPayloadSchema("single").safeParse({
      kind: "telepathy",
      choice: 0,
    });
    expect(r.success).toBe(false);
  });

  it("rejects a payload with no kind", () => {
    const r = ballotPayloadSchema("single").safeParse({ choice: 0 });
    expect(r.success).toBe(false);
  });
});

describe("ballotPayloadSchema — optional optionCount range check", () => {
  it("accepts indices within [0, optionCount) when optionCount is given", () => {
    const r = ballotPayloadSchema("single", 3).safeParse({
      kind: "single",
      choice: 2,
    });
    expect(r.success).toBe(true);
  });

  it("rejects a single choice >= optionCount", () => {
    const r = ballotPayloadSchema("single", 3).safeParse({
      kind: "single",
      choice: 3,
    });
    expect(r.success).toBe(false);
  });

  it("rejects an approval index >= optionCount", () => {
    const r = ballotPayloadSchema("approval", 2).safeParse({
      kind: "approval",
      choices: [0, 2],
    });
    expect(r.success).toBe(false);
  });

  it("rejects a ranked index >= optionCount", () => {
    const r = ballotPayloadSchema("ranked", 2).safeParse({
      kind: "ranked",
      ranking: [0, 1, 2],
    });
    expect(r.success).toBe(false);
  });

  it("still accepts abstain when optionCount is given", () => {
    const r = ballotPayloadSchema("single", 2).safeParse({ kind: "abstain" });
    expect(r.success).toBe(true);
  });

  it("does not range-check when optionCount is omitted", () => {
    const r = ballotPayloadSchema("single").safeParse({
      kind: "single",
      choice: 99,
    });
    expect(r.success).toBe(true);
  });

  it("quadratic votes length must equal optionCount when given", () => {
    const ok = ballotPayloadSchema("quadratic", 3).safeParse({
      kind: "quadratic",
      votes: [1, 0, 4],
    });
    expect(ok.success).toBe(true);
    const bad = ballotPayloadSchema("quadratic", 3).safeParse({
      kind: "quadratic",
      votes: [1, 0],
    });
    expect(bad.success).toBe(false);
  });
});
