import { createHash } from "node:crypto";

/**
 * SHA-256 of a UTF-8 string (or raw Buffer), as lowercase hex.
 * The single hashing primitive for commitments, leaf hashes, and the receipt
 * hash-chain (system-design §9/§11).
 */
export function sha256hex(s: string | Buffer): string {
  const h = createHash("sha256");
  h.update(typeof s === "string" ? Buffer.from(s, "utf8") : s);
  return h.digest("hex");
}
