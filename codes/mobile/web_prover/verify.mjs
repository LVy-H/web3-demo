// Load the EXACT built bundle and prove it generates a proof that verifies
// against the real Groth16 vkey (not just "the bundle exists"). The identity
// seed's commitment must be in the group for the proof to be valid.
import { readFileSync } from 'fs'

const code = readFileSync(new URL('../web/zkprover.js', import.meta.url), 'utf8')
;(0, eval)(code) // IIFE assigns globalThis.zkGenerateVoteProof / zkVerifyProof

const SEED = 'zkvote-spike-deterministic-seed' // commitment below is its identity
const MEMBERS = [
  '3202130587429391573947668392496818956012089007761520528168518742099046353681',
  '22222222222222222222',
]
const MESSAGE = 1
const SCOPE = '0x1111111111111111111111111111111111111111'

const proofJson = await globalThis.zkGenerateVoteProof(SEED, MEMBERS, MESSAGE, SCOPE)
const proof = JSON.parse(proofJson)
const ok = await globalThis.zkVerifyProof(proofJson)
console.log('proof.points.length =', proof.points.length)
console.log('proof.merkleTreeDepth =', proof.merkleTreeDepth)
console.log('VERIFY =', ok)
if (!ok) {
  console.error('FAIL: bundle proof did not verify')
  process.exit(1)
}
console.log('PASS: bundled web prover produces a vkey-valid proof')
