import { describe, it, expect } from "vitest";
import { createHash } from "node:crypto";
import {
  merkleRoot,
  inclusionProof,
  verifyInclusion,
  leafHash,
} from "../../src/merkle";

/**
 * RFC 6962 known-answer vectors.
 *
 * The reference inputs below are the canonical Certificate Transparency test
 * leaves from RFC 6962 §2.1.3 (raw leaf bytes, hex-encoded). Feeding their
 * hex strings into `merkleRoot` must reproduce the published reference roots
 * for the empty tree, n=1, and n=7 (and we cover 1..8 in the round-trip block).
 *
 * Roots were independently re-derived from a from-scratch RFC 6962 MTH() and
 * agree with the well-known CT/Trillian reference vectors.
 */
const REF_LEAVES_HEX = [
  "", // d0  (empty leaf — distinct from empty tree)
  "00", // d1
  "10", // d2
  "2021", // d3
  "3031", // d4
  "40414243", // d5
  "5051525354555657", // d6
  "606162636465666768696a6b6c6d6e6f", // d7
];

// Published RFC 6962 reference roots for the first n reference leaves.
const REF_ROOTS = [
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", // n=0 (empty tree = SHA256())
  "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d", // n=1
  "fac54203e7cc696cf0dfcb42c92a1d9dbaf70ad9e621f4bd8d98662f00e3c125", // n=2
  "aeb6bcfe274b70a14fb067a5e5578264db0fa9b51af5e0ba159158f329e06e77", // n=3
  "d37ee418976dd95753c1c73862b9398fa2a2cf9b4ff0fdfe8b30cd95209614b7", // n=4
  "4e3bbb1f7b478dcfe71fb631631519a3bca12c9aefca1612bfce4c13a86264d4", // n=5
  "76e67dadbcdf1e10e1b74ddc608abd2f98dfb16fbce75277b5232a127f2087ef", // n=6
  "ddb89be403809e325750d3d263cd78929c2942b7942a34b77e122c9594a74c8c", // n=7
  "5dc9da79a70659a9ad559cb701ded9a2ab9d823aad2f4960cfe370eff4604328", // n=8
];

// Deterministic Tessera-shaped leaves: 32-byte ballotHashes as hex strings.
function ballotHash(i: number): string {
  return createHash("sha256").update(`ballot-${i}`, "utf8").digest("hex");
}
const BALLOTS = Array.from({ length: 7 }, (_, i) => ballotHash(i));

describe("merkleRoot — RFC 6962 known-answer vectors", () => {
  it("empty tree root is SHA256 of the empty input (RFC 6962 MTH({}))", () => {
    expect(merkleRoot([])).toBe(REF_ROOTS[0]);
  });

  it("single-leaf root equals SHA256(0x00 || leaf) (RFC 6962 leaf hash)", () => {
    expect(merkleRoot([REF_LEAVES_HEX[0]])).toBe(REF_ROOTS[1]);
  });

  it("7-leaf reference tree matches the published RFC 6962 root", () => {
    expect(merkleRoot(REF_LEAVES_HEX.slice(0, 7))).toBe(REF_ROOTS[7]);
  });

  it("reproduces every published reference root for n = 1..8", () => {
    for (let n = 1; n <= 8; n++) {
      expect(merkleRoot(REF_LEAVES_HEX.slice(0, n))).toBe(REF_ROOTS[n]);
    }
  });

  it("single-leaf root equals leafHash() of that leaf", () => {
    const leaf = BALLOTS[0];
    expect(merkleRoot([leaf])).toBe(leafHash(leaf));
  });
});

describe("merkleRoot — determinism & normalization", () => {
  it("same leaves yield the same root", () => {
    expect(merkleRoot(BALLOTS)).toBe(merkleRoot([...BALLOTS]));
  });

  it("a different leaf order yields a different root", () => {
    const swapped = [...BALLOTS];
    [swapped[0], swapped[1]] = [swapped[1], swapped[0]];
    expect(merkleRoot(swapped)).not.toBe(merkleRoot(BALLOTS));
  });

  it("is case-insensitive in hex input (normalizes to lowercase bytes)", () => {
    const upper = BALLOTS.map((h) => h.toUpperCase());
    expect(merkleRoot(upper)).toBe(merkleRoot(BALLOTS));
  });

  it("returns 64-char lowercase hex", () => {
    expect(merkleRoot(BALLOTS)).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("inclusionProof / verifyInclusion — round-trips for sizes 1..8", () => {
  for (let size = 1; size <= 8; size++) {
    const leaves = Array.from({ length: size }, (_, i) => ballotHash(i));
    const root = merkleRoot(leaves);

    for (let index = 0; index < size; index++) {
      it(`size=${size} index=${index} verifies under the root`, () => {
        const proof = inclusionProof(leaves, index);
        expect(proof.index).toBe(index);
        expect(proof.treeSize).toBe(size);

        const lh = leafHash(leaves[index]);
        expect(
          verifyInclusion(lh, proof.index, proof.audit, proof.treeSize, root),
        ).toBe(true);
      });
    }
  }

  it("single-leaf proof has an empty audit path", () => {
    const proof = inclusionProof([BALLOTS[0]], 0);
    expect(proof.audit).toEqual([]);
    expect(
      verifyInclusion(leafHash(BALLOTS[0]), 0, [], 1, merkleRoot([BALLOTS[0]])),
    ).toBe(true);
  });

  it("audit path length follows the RFC 6962 unbalanced split", () => {
    // 7 leaves split as left{0..3} (k=4) and right{4,5,6}; the right subtree
    // splits as {4,5} and {6}. The right-most leaf (index 6) therefore has a
    // path of length 2: [ MTH({4,5}), MTH({0..3}) ] — *not* ceil(log2(7))=3.
    expect(inclusionProof(BALLOTS, 6).audit.length).toBe(2);
    // A leaf in the full left subtree has the full depth-3 path.
    expect(inclusionProof(BALLOTS, 0).audit.length).toBe(3);
  });
});

describe("verifyInclusion — tamper detection", () => {
  const leaves = BALLOTS; // 7 leaves
  const root = merkleRoot(leaves);
  const index = 3;
  const lh = leafHash(leaves[index]);
  const good = inclusionProof(leaves, index);

  it("accepts the honest proof", () => {
    expect(verifyInclusion(lh, index, good.audit, good.treeSize, root)).toBe(
      true,
    );
  });

  it("rejects a tampered leaf hash", () => {
    const badLeaf = leafHash(ballotHash(99));
    expect(
      verifyInclusion(badLeaf, index, good.audit, good.treeSize, root),
    ).toBe(false);
  });

  it("rejects a tampered root", () => {
    const badRoot = "0".repeat(64);
    expect(verifyInclusion(lh, index, good.audit, good.treeSize, badRoot)).toBe(
      false,
    );
  });

  it("rejects a tampered audit node", () => {
    const badAudit = [...good.audit];
    const last = badAudit.length - 1;
    badAudit[last] =
      badAudit[last].slice(0, -1) + (badAudit[last].endsWith("0") ? "1" : "0");
    expect(verifyInclusion(lh, index, badAudit, good.treeSize, root)).toBe(
      false,
    );
  });

  it("rejects a wrong index (same audit, shifted position)", () => {
    expect(
      verifyInclusion(lh, index + 1, good.audit, good.treeSize, root),
    ).toBe(false);
  });

  it("rejects a truncated audit path", () => {
    expect(
      verifyInclusion(lh, index, good.audit.slice(0, -1), good.treeSize, root),
    ).toBe(false);
  });
});

describe("verifyInclusion — never throws on bad input (returns false)", () => {
  const root = merkleRoot(BALLOTS);
  const good = inclusionProof(BALLOTS, 0);
  const lh = leafHash(BALLOTS[0]);

  it("false on non-hex leaf hash", () => {
    expect(verifyInclusion("zzzz", 0, good.audit, 7, root)).toBe(false);
  });

  it("false on non-hex audit entry", () => {
    expect(verifyInclusion(lh, 0, ["nothex"], 7, root)).toBe(false);
  });

  it("false on negative index", () => {
    expect(verifyInclusion(lh, -1, good.audit, 7, root)).toBe(false);
  });

  it("false when index >= treeSize", () => {
    expect(verifyInclusion(lh, 7, good.audit, 7, root)).toBe(false);
  });

  it("false on zero/negative treeSize", () => {
    expect(verifyInclusion(lh, 0, [], 0, root)).toBe(false);
    expect(verifyInclusion(lh, 0, [], -1, root)).toBe(false);
  });

  it("false on non-integer index/treeSize", () => {
    expect(verifyInclusion(lh, 0.5, good.audit, 7, root)).toBe(false);
    expect(verifyInclusion(lh, 0, good.audit, 7.5, root)).toBe(false);
  });

  it("false on null/undefined-ish audit", () => {
    // @ts-expect-error deliberately bad input
    expect(verifyInclusion(lh, 0, null, 7, root)).toBe(false);
    // @ts-expect-error deliberately bad input
    expect(verifyInclusion(lh, 0, undefined, 7, root)).toBe(false);
  });

  it("false on odd-length hex (not whole bytes)", () => {
    expect(verifyInclusion("abc", 0, [], 1, root)).toBe(false);
  });
});

describe("inclusionProof — input validation", () => {
  it("throws on out-of-range index", () => {
    expect(() => inclusionProof(BALLOTS, 7)).toThrow();
    expect(() => inclusionProof(BALLOTS, -1)).toThrow();
  });

  it("throws on empty tree", () => {
    expect(() => inclusionProof([], 0)).toThrow();
  });
});
