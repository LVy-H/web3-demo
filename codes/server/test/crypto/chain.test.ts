import { describe, it, expect } from "vitest";
import { chainNext, genesisHead, sha256hex } from "../../src/crypto";

const H1 = "1".repeat(64);
const H2 = "2".repeat(64);

describe("genesisHead", () => {
  it("matches the domain-separated formula", () => {
    expect(genesisHead("dec-123")).toBe(
      sha256hex("tessera:genesis:v1\n" + "dec-123"),
    );
  });

  it("is deterministic for the same decisionId", () => {
    expect(genesisHead("dec-abc")).toBe(genesisHead("dec-abc"));
  });

  it("differs for different decisionIds", () => {
    expect(genesisHead("dec-a")).not.toBe(genesisHead("dec-b"));
  });

  it("returns a 64-char lowercase hex digest", () => {
    expect(genesisHead("dec-1")).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("chainNext", () => {
  it("matches the domain-separated formula", () => {
    expect(chainNext(H1, H2)).toBe(
      sha256hex("tessera:node:v1\n" + H1 + "\n" + H2),
    );
  });

  it("is deterministic", () => {
    expect(chainNext(H1, H2)).toBe(chainNext(H1, H2));
  });

  it("is order-sensitive in its two arguments", () => {
    expect(chainNext(H1, H2)).not.toBe(chainNext(H2, H1));
  });

  it("changes when the previous head changes", () => {
    expect(chainNext(H1, H2)).not.toBe(chainNext("3".repeat(64), H2));
  });

  it("changes when the leaf hash changes", () => {
    expect(chainNext(H1, H2)).not.toBe(chainNext(H1, "3".repeat(64)));
  });

  it("returns a 64-char lowercase hex digest", () => {
    expect(chainNext(H1, H2)).toMatch(/^[0-9a-f]{64}$/);
  });

  it("is collision-resistant against concatenation ambiguity (delimiter matters)", () => {
    // Without the '\n' delimiter, chainNext('aa','bb') would collide with
    // chainNext('a','abb'). The domain separator must prevent that.
    expect(chainNext("aa", "bb")).not.toBe(chainNext("a", "abb"));
  });

  it("builds a deterministic chain from a genesis head", () => {
    const g = genesisHead("dec-chain");
    const leafA = sha256hex("ballot-A");
    const leafB = sha256hex("ballot-B");
    const headA = chainNext(g, leafA);
    const headB = chainNext(headA, leafB);
    // Recomputing the same sequence yields the same head.
    const g2 = genesisHead("dec-chain");
    const headA2 = chainNext(g2, leafA);
    const headB2 = chainNext(headA2, leafB);
    expect(headB).toBe(headB2);
    // Reordering the leaves changes the final head.
    const headBAlt = chainNext(chainNext(g, leafB), leafA);
    expect(headBAlt).not.toBe(headB);
  });
});
