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
 * @returns {Promise<string>} JSON matching Dart RelayProof
 */
async function zkGenerateVoteProof(identitySeed, memberCommitments, message, scope) {
  const id = new Identity(identitySeed)
  const group = new Group(memberCommitments.map((c) => BigInt(c)))
  const proof = await generateProof(id, group, Number(message), scope)
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
