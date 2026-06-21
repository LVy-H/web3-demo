import { createHash } from "node:crypto";

/**
 * RFC 6962 binary Merkle tree over SHA-256, domain-separated.
 *
 * This is the verifier foundation for Tessera's verifiable bulletin board
 * (system-design §11.5 / §17 finding L3): the published ballot set is hashed
 * into an RFC 6962 Merkle tree, the root is anchored, and a verifier recomputes
 * the root from the served ballots and asserts it equals the anchored root
 * (root-binding, §11 step 5). Each receipt then yields an inclusion proof.
 *
 * Domain separation (RFC 6962 §2.1):
 *   leaf hash  = SHA256(0x00 || leaf)
 *   node hash  = SHA256(0x01 || left || right)
 * The 0x00/0x01 prefixes prevent second-preimage attacks (a leaf can never be
 * mistaken for an interior node).
 *
 * Split rule (RFC 6962): for n > 1 the left subtree holds the largest power of
 * two strictly less than n; the right subtree holds the remainder. This makes
 * proofs interoperate with standard Certificate-Transparency verifiers.
 *
 * Leaves are hex strings (the per-ballot `ballotHash`). They are decoded to raw
 * bytes before hashing, so the tree is over the ballot-hash *bytes*, exactly as
 * a CT log would treat opaque leaf data.
 *
 * Pure module: depends only on `node:crypto`. No db/express/io.
 */

const LEAF_PREFIX = Buffer.from([0x00]);
const NODE_PREFIX = Buffer.from([0x01]);

function sha256(buf: Buffer): Buffer {
  return createHash("sha256").update(buf).digest();
}

/** Whole-byte lowercase/uppercase hex string. */
function isHex(s: unknown): s is string {
  return typeof s === "string" && s.length % 2 === 0 && /^[0-9a-fA-F]*$/.test(s);
}

/** Decode a whole-byte hex string to a Buffer; throws on malformed input. */
function hexToBuf(hex: string): Buffer {
  if (!isHex(hex)) {
    throw new TypeError(`merkle: expected whole-byte hex string, got ${hex}`);
  }
  return Buffer.from(hex, "hex");
}

/** RFC 6962 leaf hash: SHA256(0x00 || leaf). `leaf` is a hex string. */
export function leafHash(leaf: string): string {
  return sha256(Buffer.concat([LEAF_PREFIX, hexToBuf(leaf)])).toString("hex");
}

/** RFC 6962 interior node hash: SHA256(0x01 || left || right). Buffers in/out. */
function nodeHash(left: Buffer, right: Buffer): Buffer {
  return sha256(Buffer.concat([NODE_PREFIX, left, right]));
}

/** Largest power of two strictly less than n (n >= 2). */
function largestPowerOfTwoBelow(n: number): number {
  let k = 1;
  while (k << 1 < n) k <<= 1;
  return k;
}

/** RFC 6962 Merkle Tree Hash over a slice of leaf buffers. Returns a Buffer. */
function mth(leaves: Buffer[]): Buffer {
  const n = leaves.length;
  if (n === 0) return sha256(Buffer.alloc(0)); // MTH({}) = SHA256()
  if (n === 1) return sha256(Buffer.concat([LEAF_PREFIX, leaves[0]]));
  const k = largestPowerOfTwoBelow(n);
  return nodeHash(mth(leaves.slice(0, k)), mth(leaves.slice(k)));
}

/**
 * RFC 6962 Merkle root over `leaves` (hex strings, e.g. per-ballot ballotHashes).
 * Empty tree returns SHA256() of the empty input. Returns a lowercase hex root.
 */
export function merkleRoot(leaves: string[]): string {
  const bufs = leaves.map(hexToBuf);
  return mth(bufs).toString("hex");
}

export interface InclusionProof {
  index: number;
  treeSize: number;
  /** Audit path: sibling node hashes, leaf-to-root order, lowercase hex. */
  audit: string[];
}

/**
 * RFC 6962 audit path (PATH(m, D[n])) for the leaf at `index`, as Buffers,
 * accumulated leaf→root. Mirrors the MTH split rule exactly.
 */
function pathBufs(index: number, leaves: Buffer[]): Buffer[] {
  const n = leaves.length;
  if (n === 1) return []; // PATH(0, {d0}) = {}
  const k = largestPowerOfTwoBelow(n);
  if (index < k) {
    // leaf in the left subtree; sibling = MTH(right subtree)
    return [...pathBufs(index, leaves.slice(0, k)), mth(leaves.slice(k))];
  }
  // leaf in the right subtree; sibling = MTH(left subtree)
  return [...pathBufs(index - k, leaves.slice(k)), mth(leaves.slice(0, k))];
}

/**
 * Inclusion (audit) proof for the leaf at `index` in the tree over `leaves`.
 * Throws on an empty tree or an out-of-range index.
 */
export function inclusionProof(leaves: string[], index: number): InclusionProof {
  const treeSize = leaves.length;
  if (!Number.isInteger(index) || index < 0 || index >= treeSize) {
    throw new RangeError(
      `merkle: index ${index} out of range for tree size ${treeSize}`,
    );
  }
  const bufs = leaves.map(hexToBuf);
  return {
    index,
    treeSize,
    audit: pathBufs(index, bufs).map((b) => b.toString("hex")),
  };
}

/**
 * Recompute the RFC 6962 root from a leaf hash + audit path and compare to
 * `root`. Returns true iff the leaf is proven included at `index` in a tree of
 * `treeSize`. Never throws — any malformed input yields false (verifier-safe).
 *
 * `leafHashHex` is the already-domain-separated leaf hash SHA256(0x00 || leaf)
 * — i.e. the output of `leafHash()` — not the raw ballotHash.
 */
export function verifyInclusion(
  leafHashHex: string,
  index: number,
  audit: string[],
  treeSize: number,
  root: string,
): boolean {
  try {
    if (!Number.isInteger(index) || !Number.isInteger(treeSize)) return false;
    if (treeSize <= 0 || index < 0 || index >= treeSize) return false;
    if (!Array.isArray(audit)) return false;
    if (!isHex(leafHashHex) || !isHex(root)) return false;

    // The audit path length is fully determined by (index, treeSize) per
    // RFC 6962 §2.1.1; a mismatched length is a malformed/tampered proof.
    let hash = hexToBuf(leafHashHex);
    let fn = index; // position within the current subtree
    let sn = treeSize - 1; // last index within the current subtree
    let consumed = 0;

    while (sn > 0) {
      if (consumed >= audit.length) return false;
      const sibling = hexToBuf(audit[consumed++]);
      if (fn % 2 === 1 || fn === sn) {
        // node is a right child (or last node promoted up): sibling on the left
        hash = nodeHash(sibling, hash);
        // skip any further duplicate-promotion levels
        while (fn % 2 === 0) {
          fn >>= 1;
          sn >>= 1;
        }
      } else {
        // node is a left child: sibling on the right
        hash = nodeHash(hash, sibling);
      }
      fn >>= 1;
      sn >>= 1;
    }

    // Every audit entry must be consumed (reject padded/trailing nodes).
    if (consumed !== audit.length) return false;

    return hash.toString("hex") === root.toLowerCase();
  } catch {
    return false;
  }
}
