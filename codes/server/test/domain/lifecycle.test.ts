import { describe, it, expect } from "vitest";
import {
  canTransition,
  assertTransition,
  IllegalTransitionError,
  DECISION_STATES,
  type DecisionState,
} from "../../src/domain";

// The legal transitions per the Phase-2 contract (open mode skips 'registration').
//   draft → open
//   open → closed
//   closed → challenge
//   challenge → published
//   closed → published          (challenge optional)
//   {draft,open,closed,challenge} → cancelled
//   open → open                  (the 'extend' amendment)
// Everything else is illegal — especially anything OUT of a terminal
// state ('published' | 'cancelled') and lifecycle skips.
const LEGAL: ReadonlyArray<[DecisionState, DecisionState]> = [
  ["draft", "open"],
  ["open", "closed"],
  ["closed", "challenge"],
  ["challenge", "published"],
  ["closed", "published"],
  ["draft", "cancelled"],
  ["open", "cancelled"],
  ["closed", "cancelled"],
  ["challenge", "cancelled"],
  ["open", "open"],
];

const LEGAL_SET = new Set(LEGAL.map(([f, t]) => `${f}->${t}`));

describe("DECISION_STATES", () => {
  it("enumerates exactly the six lifecycle states", () => {
    expect([...DECISION_STATES].sort()).toEqual(
      ["cancelled", "challenge", "closed", "draft", "open", "published"].sort(),
    );
  });
});

describe("canTransition — every legal transition is allowed", () => {
  for (const [from, to] of LEGAL) {
    it(`${from} → ${to} is legal`, () => {
      expect(canTransition(from, to)).toBe(true);
    });
  }
});

describe("canTransition — representative illegal transitions are rejected", () => {
  const ILLEGAL: ReadonlyArray<[DecisionState, DecisionState]> = [
    // out of terminal states (published is terminal)
    ["published", "open"],
    ["published", "closed"],
    ["published", "challenge"],
    ["published", "cancelled"],
    ["published", "draft"],
    // out of terminal states (cancelled is terminal)
    ["cancelled", "open"],
    ["cancelled", "draft"],
    ["cancelled", "closed"],
    ["cancelled", "published"],
    // lifecycle skips
    ["draft", "closed"],
    ["draft", "challenge"],
    ["draft", "published"],
    ["open", "challenge"],
    ["open", "published"],
    // backwards
    ["closed", "open"],
    ["challenge", "closed"],
    ["closed", "draft"],
    // self-loops that are NOT the extend amendment
    ["draft", "draft"],
    ["closed", "closed"],
    ["challenge", "challenge"],
    ["published", "published"],
    ["cancelled", "cancelled"],
  ];
  for (const [from, to] of ILLEGAL) {
    it(`${from} → ${to} is illegal`, () => {
      expect(canTransition(from, to)).toBe(false);
    });
  }
});

describe("canTransition — exhaustive cross-product matches the legal set", () => {
  it("only the contracted edges are legal", () => {
    for (const from of DECISION_STATES) {
      for (const to of DECISION_STATES) {
        const expected = LEGAL_SET.has(`${from}->${to}`);
        expect(canTransition(from, to)).toBe(expected);
      }
    }
  });
});

describe("assertTransition", () => {
  it("does not throw on a legal transition", () => {
    expect(() => assertTransition("draft", "open")).not.toThrow();
    expect(() => assertTransition("open", "open")).not.toThrow();
    expect(() => assertTransition("closed", "published")).not.toThrow();
  });

  it("throws IllegalTransitionError on an illegal transition", () => {
    expect(() => assertTransition("published", "open")).toThrow(
      IllegalTransitionError,
    );
    expect(() => assertTransition("draft", "closed")).toThrow(
      IllegalTransitionError,
    );
  });

  it("the thrown error names the from/to states", () => {
    try {
      assertTransition("cancelled", "open");
      throw new Error("expected assertTransition to throw");
    } catch (err) {
      expect(err).toBeInstanceOf(IllegalTransitionError);
      const e = err as IllegalTransitionError;
      expect(e.from).toBe("cancelled");
      expect(e.to).toBe("open");
      expect(e.message).toContain("cancelled");
      expect(e.message).toContain("open");
    }
  });
});
