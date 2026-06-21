import { describe, it, expect } from "vitest";
import {
  computeSetupCommitment,
  canonicalize,
  sha256hex,
  type SetupParts,
} from "../../src/crypto";

function baseParts(): SetupParts {
  return {
    options: ["yes", "no", "abstain"],
    method: "single",
    rule: {
      threshold: { kind: "majority" },
      quorum: 10,
      tieBreak: "runoff",
    },
    ballotMode: "open",
    resultsPolicy: "sealed",
    rosterCommitment: "a".repeat(64),
    issuerPubKeyHash: null,
    schedule: { opensAt: "2026-07-01T00:00:00Z", closesAt: "2026-07-08T00:00:00Z" },
  };
}

describe("computeSetupCommitment", () => {
  it("returns a 64-char lowercase hex digest", () => {
    expect(computeSetupCommitment(baseParts())).toMatch(/^[0-9a-f]{64}$/);
  });

  it("equals sha256hex(canonicalize([...])) in the §9 field order", () => {
    const p = baseParts();
    const expected = sha256hex(
      canonicalize([
        p.options,
        p.method,
        p.rule,
        p.ballotMode,
        p.resultsPolicy,
        p.rosterCommitment,
        p.issuerPubKeyHash ?? null,
        p.schedule,
      ]),
    );
    expect(computeSetupCommitment(p)).toBe(expected);
  });

  it("is stable when object fields are reordered (rule/schedule keys)", () => {
    const p1 = baseParts();
    const p2: SetupParts = {
      // top-level fields reordered
      schedule: { closesAt: "2026-07-08T00:00:00Z", opensAt: "2026-07-01T00:00:00Z" },
      issuerPubKeyHash: null,
      rosterCommitment: "a".repeat(64),
      resultsPolicy: "sealed",
      ballotMode: "open",
      // nested rule keys reordered
      rule: { tieBreak: "runoff", quorum: 10, threshold: { kind: "majority" } },
      method: "single",
      options: ["yes", "no", "abstain"],
    };
    expect(computeSetupCommitment(p2)).toBe(computeSetupCommitment(p1));
  });

  it("treats issuerPubKeyHash undefined and null identically (Phase 2 has no issuer)", () => {
    const withNull = baseParts();
    const withUndefined = baseParts();
    delete (withUndefined as { issuerPubKeyHash?: string | null }).issuerPubKeyHash;
    expect(computeSetupCommitment(withUndefined)).toBe(
      computeSetupCommitment(withNull),
    );
  });

  it("changes when options change", () => {
    const p = baseParts();
    p.options = ["yes", "no"];
    expect(computeSetupCommitment(p)).not.toBe(computeSetupCommitment(baseParts()));
  });

  it("is order-sensitive in options (array order is significant)", () => {
    const p = baseParts();
    p.options = ["no", "yes", "abstain"];
    expect(computeSetupCommitment(p)).not.toBe(computeSetupCommitment(baseParts()));
  });

  it("changes when method changes", () => {
    const p = baseParts();
    p.method = "approval";
    expect(computeSetupCommitment(p)).not.toBe(computeSetupCommitment(baseParts()));
  });

  it("changes when rule changes", () => {
    const p = baseParts();
    p.rule = { threshold: { kind: "supermajority", percent: 66 }, tieBreak: "runoff" };
    expect(computeSetupCommitment(p)).not.toBe(computeSetupCommitment(baseParts()));
  });

  it("changes when ballotMode changes", () => {
    const p = baseParts();
    p.ballotMode = "secret";
    expect(computeSetupCommitment(p)).not.toBe(computeSetupCommitment(baseParts()));
  });

  it("changes when resultsPolicy changes", () => {
    const p = baseParts();
    p.resultsPolicy = "live";
    expect(computeSetupCommitment(p)).not.toBe(computeSetupCommitment(baseParts()));
  });

  it("changes when rosterCommitment changes", () => {
    const p = baseParts();
    p.rosterCommitment = "b".repeat(64);
    expect(computeSetupCommitment(p)).not.toBe(computeSetupCommitment(baseParts()));
  });

  it("changes when issuerPubKeyHash is set (vs null)", () => {
    const p = baseParts();
    p.issuerPubKeyHash = "c".repeat(64);
    expect(computeSetupCommitment(p)).not.toBe(computeSetupCommitment(baseParts()));
  });

  it("changes when schedule changes", () => {
    const p = baseParts();
    p.schedule = { opensAt: "2026-07-02T00:00:00Z", closesAt: "2026-07-08T00:00:00Z" };
    expect(computeSetupCommitment(p)).not.toBe(computeSetupCommitment(baseParts()));
  });
});
