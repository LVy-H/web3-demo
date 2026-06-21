import { describe, it, expect } from "vitest";
import {
  canTransition,
  assertTransition,
  IllegalTransitionError,
  DECISION_STATES,
  type DecisionState,
} from "../../src/domain";

// The legal transitions per the contract.
//   OPEN mode:    draft → open
//   SECRET mode:  draft → registration → open   (registration-before-voting, §11.0)
//   open → closed
//   closed → challenge
//   challenge → published
//   closed → published          (challenge optional)
//   {draft,registration,open,closed,challenge} → cancelled (pre-publish cancel)
// Everything else is illegal — especially anything OUT of a terminal
// state ('published' | 'cancelled') and lifecycle skips.
//
// C1 FIX: open → open is NOT a state transition. 'extend' is an AMENDMENT
// (state stays 'open'; it appends a signed lifecycle event and never calls
// assertTransition). Keeping open → open in the machine let a 2nd /open reset
// the running hash-chain head to genesis/leafCount-0 after ballots existed
// (§11.5 root-binding fork), so the self-loop is now rejected.
const LEGAL: ReadonlyArray<[DecisionState, DecisionState]> = [
  ["draft", "open"],
  ["draft", "registration"],
  ["registration", "open"],
  ["open", "closed"],
  ["closed", "challenge"],
  ["challenge", "published"],
  ["closed", "published"],
  ["draft", "cancelled"],
  ["registration", "cancelled"],
  ["open", "cancelled"],
  ["closed", "cancelled"],
  ["challenge", "cancelled"],
];

const LEGAL_SET = new Set(LEGAL.map(([f, t]) => `${f}->${t}`));

describe("DECISION_STATES", () => {
  it("enumerates exactly the seven lifecycle states (incl. secret-mode 'registration')", () => {
    expect([...DECISION_STATES].sort()).toEqual(
      ["cancelled", "challenge", "closed", "draft", "open", "published", "registration"].sort(),
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
    ["registration", "closed"],
    ["registration", "challenge"],
    ["registration", "published"],
    // backwards
    ["closed", "open"],
    ["challenge", "closed"],
    ["closed", "draft"],
    ["open", "registration"],
    ["registration", "draft"],
    // self-loops are all illegal (C1: 'extend' is an amendment, not a
    // state transition, so open → open must NOT be a legal edge).
    ["open", "open"],
    ["draft", "draft"],
    ["registration", "registration"],
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
    expect(() => assertTransition("open", "closed")).not.toThrow();
    expect(() => assertTransition("closed", "published")).not.toThrow();
  });

  it("does not throw on the secret-mode registration edges", () => {
    expect(() => assertTransition("draft", "registration")).not.toThrow();
    expect(() => assertTransition("registration", "open")).not.toThrow();
    expect(() => assertTransition("registration", "cancelled")).not.toThrow();
  });

  it("throws on open → open (C1: extend is an amendment, not a transition)", () => {
    expect(() => assertTransition("open", "open")).toThrow(
      IllegalTransitionError,
    );
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
