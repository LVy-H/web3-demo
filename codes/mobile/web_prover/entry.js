// ZK vote-proof bridge for Flutter web (dart:js_interop loads this bundle and
// calls the globals). Reuses the SAME Semaphore v4 prover the React app uses, so
// proofs are byte-compatible and verify against the real Groth16 vkey.
//
// Built with vite into codes/mobile/web/zkprover.js (IIFE). The Flutter web app
// references it from web/index.html; tests load it in headless Chrome.
import { Identity } from '@semaphore-protocol/identity'
import { Group } from '@semaphore-protocol/group'
import { generateProof, verifyProof } from '@semaphore-protocol/proof'

/**
 * Generate a Semaphore vote proof.
 * @param {string} identitySeed   member's Semaphore identity seed
 * @param {string[]} memberCommitments  decimal-string commitments (the group)
 * @param {number|string} message  option index
 * @param {string} scope           poll address (0x-hex)
 * @param {{depth?: number, wasm?: string, zkey?: string}} [opts]
 *   OPTIONAL, mobile-only. When present, fixes the circuit tree `depth` and
 *   loads the Groth16 `wasm`/`zkey` from the given URLs (blob: or http://
 *   localhost) instead of fetching them from the PSE CDN. Web/desktop callers
 *   pass nothing → behaviour is byte-identical to before (CDN fetch, dynamic
 *   depth). Purely additive: this is the only prover-bundle change for the
 *   mobile WebView prover (see 2026-06-02-mobile-scan-and-native-proving-design).
 * @returns {Promise<string>} JSON matching Dart RelayProof
 */
async function zkGenerateVoteProof(identitySeed, memberCommitments, message, scope, opts) {
  const id = new Identity(identitySeed)
  const group = new Group(memberCommitments.map((c) => BigInt(c)))
  // undefined (never null) so generateProof's own defaults kick in for web/desktop.
  const depth = opts?.depth
  const artifacts = (opts?.wasm && opts?.zkey)
    ? { wasm: opts.wasm, zkey: opts.zkey }
    : undefined
  const proof = await generateProof(id, group, Number(message), scope, depth, artifacts)
  return JSON.stringify({
    merkleTreeDepth: proof.merkleTreeDepth,
    merkleTreeRoot: proof.merkleTreeRoot.toString(),
    nullifier: proof.nullifier.toString(),
    message: proof.message.toString(),
    scope: proof.scope.toString(),
    points: proof.points.map(String),
  })
}

/** Verify a proof JSON against the real vkey. Returns boolean. */
async function zkVerifyProof(proofJson) {
  const p = JSON.parse(proofJson)
  return await verifyProof({
    merkleTreeDepth: Number(p.merkleTreeDepth),
    merkleTreeRoot: p.merkleTreeRoot,
    nullifier: p.nullifier,
    message: p.message,
    scope: p.scope,
    points: p.points,
  })
}

/**
 * Derive a Semaphore identity commitment from a seed. Pure identity math
 * (EdDSA-Poseidon over Baby Jubjub) — NOT the SNARK — so it's cheap and runs
 * anywhere the bundle does. It's the recurring member's public id the organizer
 * registers, and the input to the live-meeting confirmation code.
 * @param {string} seed
 * @returns {string} decimal commitment
 */
function zkCommitment(seed) {
  return new Identity(seed).commitment.toString()
}

// Expose on window for dart:js_interop.
globalThis.zkGenerateVoteProof = zkGenerateVoteProof
globalThis.zkVerifyProof = zkVerifyProof
globalThis.zkCommitment = zkCommitment
