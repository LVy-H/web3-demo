import { sha256hex } from "./hash";

/**
 * Receipt hash-chain (system-design §9 "Receipt" / §11.5).
 *
 * Each appended ballot advances a running head:
 *   head_0 = genesisHead(decisionId)
 *   head_n = chainNext(head_{n-1}, leafHash_n)
 *
 * Domain separation ('tessera:genesis:v1' / 'tessera:node:v1') plus the '\n'
 * delimiters make the construction unambiguous: an attacker cannot re-split the
 * two inputs to forge a colliding head (e.g. chainNext('aa','bb') must differ
 * from chainNext('a','abb')). The server signs head_n into each receipt, so the
 * receipt commits to the entire prefix of the log, not just one position.
 */

const GENESIS_PREFIX = "tessera:genesis:v1\n";
const NODE_PREFIX = "tessera:node:v1\n";

/** The chain head before any ballot is appended, bound to the decision. */
export function genesisHead(decisionId: string): string {
  return sha256hex(GENESIS_PREFIX + decisionId);
}

/** Fold one leaf (ballot) hash into the running head. */
export function chainNext(prevHead: string, leafHash: string): string {
  return sha256hex(NODE_PREFIX + prevHead + "\n" + leafHash);
}
