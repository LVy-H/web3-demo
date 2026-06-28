import { describe, it, expect, expectTypeOf } from "vitest";
import type {
  Decision,
  Ballot,
  Receipt,
  Account,
  LifecycleEvent,
  EligibilityRecord,
  Checkpoint,
  DecisionState,
  Method,
  BallotMode,
  ResultsPolicy,
  AnchorMode,
  EligibilityMethod,
  BallotPayload,
} from "../../src/domain";

// These are compile-time assertions; the runtime body only exists so vitest
// counts the file. If the public type surface drifts from the contract,
// `npm run typecheck` fails.

describe("domain types — §9 entities are constructible", () => {
  it("builds a Decision", () => {
    const d: Decision = {
      id: "dec_1",
      convener: "acc_1",
      title: "Adopt?",
      options: ["Yes", "No"],
      method: "single",
      ballotMode: "open",
      resultsPolicy: "sealed",
      eligibility: { method: "open" },
      rule: { threshold: { kind: "majority" }, tieBreak: "declare" },
      schedule: {},
      visibility: "listed",
      anchorMode: "broadcast",
      setupCommitment: "deadbeef",
      state: "draft",
      createdAt: 0,
    };
    expect(d.state).toBe("draft");
    expectTypeOf(d.state).toEqualTypeOf<DecisionState>();
  });

  it("builds a Ballot with a payload", () => {
    const payload: BallotPayload = { kind: "single", choice: 0 };
    const b: Ballot = {
      decisionId: "dec_1",
      payload,
      idempotencyKey: "idem_1",
      logSeq: 0,
      prevHead: "genesis",
      ballotHash: "abc",
    };
    expect(b.payload.kind).toBe("single");
  });

  it("builds a Receipt", () => {
    const r: Receipt = {
      ballotHash: "abc",
      logPosition: 0,
      runningRoot: "root0",
      serverSig: "sig0",
    };
    expect(r.logPosition).toBe(0);
  });

  it("builds an Account", () => {
    const a: Account = {
      id: "acc_1",
      displayName: "Convener",
      authCredentialHash: "hash",
      createdAt: 0,
    };
    expect(a.id).toBe("acc_1");
  });

  it("builds a LifecycleEvent", () => {
    const e: LifecycleEvent = {
      decisionId: "dec_1",
      from: "draft",
      to: "open",
      actor: "acc_1",
      timestamp: 1,
      signature: "sig",
    };
    expect(e.to).toBe("open");
  });

  it("builds an EligibilityRecord", () => {
    const rec: EligibilityRecord = {
      decisionId: "dec_1",
      method: "passcode",
      identifier: "hash-of-passcode",
      status: "issued",
    };
    expect(rec.status).toBe("issued");
  });

  it("builds a Checkpoint", () => {
    const c: Checkpoint = {
      prevRoot: "r0",
      root: "r1",
      seqRange: [0, 5],
      status: "interim",
    };
    expect(c.seqRange[1]).toBe(5);
  });
});

describe("domain unions — values are assignable", () => {
  it("DecisionState union", () => {
    const states: DecisionState[] = [
      "draft",
      "open",
      "closed",
      "challenge",
      "published",
      "cancelled",
    ];
    expect(states).toHaveLength(6);
  });

  it("Method union", () => {
    const methods: Method[] = [
      "single",
      "approval",
      "ranked",
      "quadratic",
      "survey",
    ];
    expect(methods).toHaveLength(5);
  });

  it("BallotMode / ResultsPolicy / AnchorMode / EligibilityMethod", () => {
    const bm: BallotMode[] = ["open", "secret"];
    const rp: ResultsPolicy[] = ["sealed", "live"];
    const am: AnchorMode[] = ["casual", "broadcast", "chain"];
    const em: EligibilityMethod[] = ["open", "passcode", "domain", "invite"];
    expect([bm, rp, am, em].every((x) => x.length >= 2)).toBe(true);
  });
});
