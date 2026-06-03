// Phase 12d Gate 1 — 4-module prover-widening regression (REAL vkey).
//
// Loads the freshly-rebuilt WIDENED bundle (web/zkprover.js, entry.js:
// Number(message) -> BigInt(message)) and, for each of the four shipped
// SNARK-message voting modules, GENERATES a Groth16 proof for that module's
// representative `message` and VERIFIES it against the real Groth16 vkey via
// zkVerifyProof. GO requires VERIFY === true for all four.
//
// The four shipped modules differ ONLY in the small-integer `message` they bind:
//   anon (M1)      = an option index           -> 1
//   approval (M3)  = a bitmask (0b101)         -> 5
//   ranked (M2)    = a packed ranking (C>A>B)  -> 531
//   quadratic (QV) = a packed alloc [6,8,0]    -> 134
// all < 2^32, so they round-trip through BigInt unchanged.
//
// Plus an OPTIONAL wide message (a 200-bit value, passed as a DECIMAL STRING so
// it is not pre-narrowed by JS Number before reaching the bundle) to demonstrate
// the widening actually unblocks full field-element survey commitments.
import { readFileSync } from 'fs'

const code = readFileSync(new URL('../web/zkprover.js', import.meta.url), 'utf8')
;(0, eval)(code) // IIFE assigns globalThis.zkGenerateVoteProof / zkVerifyProof

// The SEED's commitment is the first member, so its membership proof is valid.
const SEED = 'zkvote-spike-deterministic-seed'
const MEMBERS = [
  '3202130587429391573947668392496818956012089007761520528168518742099046353681',
  '22222222222222222222',
]
const SCOPE = '0x1111111111111111111111111111111111111111'

// Invariants captured from the pre-widening committed bundle for MESSAGE=1.
const EXPECT_POINTS_LEN = 8
const EXPECT_DEPTH = 1

// The four shipped modules' representative messages. `wire` mirrors the
// production web path: small ints go through as JS numbers (the JSNumber path
// in proof_service_web.dart); see the wide case for the string path.
const MODULES = [
  { name: 'anon      (M1, option index)', message: 1, wire: 1 },
  { name: 'approval  (M3, bitmask 0b101)', message: 5, wire: 5 },
  { name: 'ranked    (M2, packed C>A>B)', message: 531, wire: 531 },
  { name: 'quadratic (QV, packed [6,8,0])', message: 134, wire: 134 },
]

let allOk = true
const results = []

for (const m of MODULES) {
  const proofJson = await globalThis.zkGenerateVoteProof(SEED, MEMBERS, m.wire, SCOPE)
  const proof = JSON.parse(proofJson)
  const verified = await globalThis.zkVerifyProof(proofJson)

  // Invariants: proof shape unchanged, message round-trips (the direct test of
  // the widening — under Number() a wide message would come back garbled).
  const pointsOk = proof.points.length === EXPECT_POINTS_LEN
  const depthOk = proof.merkleTreeDepth === EXPECT_DEPTH
  const msgRoundTrips = proof.message === String(m.message)
  const ok = verified && pointsOk && depthOk && msgRoundTrips

  results.push({ name: m.name, message: m.message, verified, pointsOk, depthOk, msgRoundTrips })
  console.log(
    `[${ok ? 'OK ' : 'FAIL'}] ${m.name}  message=${m.message}  ` +
      `VERIFY=${verified}  points.length=${proof.points.length}  ` +
      `depth=${proof.merkleTreeDepth}  message.roundTrip=${msgRoundTrips} (got ${proof.message})`,
  )
  if (!ok) allOk = false
}

// OPTIONAL extra signal: a 200-bit message proves the widening unblocks wide
// survey commitments. MUST be passed as a decimal STRING — a JS number can't
// hold 200 bits, so a numeric literal would silently narrow before the bundle.
const WIDE = (1n << 200n) + 12345n // 200-bit-class field element, < BN254 r (~2^254)
const wideJson = await globalThis.zkGenerateVoteProof(SEED, MEMBERS, WIDE.toString(), SCOPE)
const wideProof = JSON.parse(wideJson)
const wideVerified = await globalThis.zkVerifyProof(wideJson)
const wideRoundTrips = wideProof.message === WIDE.toString()
const wideOk = wideVerified && wideRoundTrips && wideProof.points.length === EXPECT_POINTS_LEN
console.log(
  `[${wideOk ? 'OK ' : 'FAIL'}] wide      (200-bit survey-style commitment)  ` +
    `VERIFY=${wideVerified}  message.roundTrip=${wideRoundTrips}  ` +
    `points.length=${wideProof.points.length}`,
)
// The wide case is informational (not part of the GO/NO-GO), but if it fails the
// widening didn't actually take effect — surface it loudly.
if (!wideOk) {
  console.error('WARNING: wide-message case did not verify/round-trip — widening may be ineffective')
}

console.log('---')
if (!allOk) {
  console.error('NO-GO: at least one of the four shipped modules failed the regression')
  process.exit(1)
}
console.log('GO: all four shipped modules (anon/approval/ranked/quadratic) produce real-vkey-valid proofs against the widened bundle')
