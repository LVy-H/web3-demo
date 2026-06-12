// M1 spike pre-flight (host-side): prove the BUNDLED depth-16 artifacts + the
// new entry.js `opts` branch produce a Groth16 proof that VERIFIES against the
// real vkey — under Node, before involving the emulator. This validates the
// artifacts and the opts code path in isolation; it is NOT the go/no-go signal
// (that requires the emulator WebView). snarkjs in Node fetches file:// URLs.
//
//   node spike_bundled_artifacts.mjs
import { readFileSync } from 'fs'
import { createServer } from 'http'

const code = readFileSync(new URL('../web/zkprover.js', import.meta.url), 'utf8')
;(0, eval)(code) // IIFE assigns globalThis.zkGenerateVoteProof / zkVerifyProof

// snarkjs uses fetch() for artifact URLs and Node's undici has no file:// scheme
// (the exact constraint the spec calls out), so serve the bundled bytes over a
// throwaway localhost HTTP server — mirroring the Dart HttpServer fallback path.
const wasmBytes = readFileSync(new URL('../../../packages/core_crypto/assets/zk/semaphore-16.wasm', import.meta.url))
const zkeyBytes = readFileSync(new URL('../../../packages/core_crypto/assets/zk/semaphore-16.zkey', import.meta.url))
const server = createServer((req, res) => {
  const body = req.url.endsWith('.zkey') ? zkeyBytes : wasmBytes
  res.writeHead(200, { 'content-type': 'application/octet-stream' })
  res.end(body)
})
await new Promise((r) => server.listen(0, '127.0.0.1', r))
const port = server.address().port
const wasm = `http://127.0.0.1:${port}/semaphore-16.wasm`
const zkey = `http://127.0.0.1:${port}/semaphore-16.zkey`

// Same golden seed as verify.mjs / desktop_prover_test: members[0] is the seed's
// commitment, so a correct membership proof must verify. 3-member test group.
const SEED = 'zkvote-spike-deterministic-seed'
const SEED_COMMITMENT = '3202130587429391573947668392496818956012089007761520528168518742099046353681'
const MEMBERS = [SEED_COMMITMENT, '22222222222222222222', '33333333333333333333']
const MESSAGE = 1
const SCOPE = '0x1111111111111111111111111111111111111111'

const proofJson = await globalThis.zkGenerateVoteProof(
  SEED, MEMBERS, MESSAGE, SCOPE, { depth: 16, wasm, zkey })
const proof = JSON.parse(proofJson)
console.log('proof.merkleTreeDepth =', proof.merkleTreeDepth, '(expect 16, from bundled artifact)')
console.log('proof.points.length  =', proof.points.length, '(expect 8)')
const ok = await globalThis.zkVerifyProof(proofJson)
console.log('VERIFY =', ok)
if (proof.merkleTreeDepth !== 16 || !ok) {
  console.error('FAIL: bundled depth-16 opts-path proof did not verify at depth 16')
  process.exit(1)
}
console.log('PASS: bundled depth-16 artifacts + opts branch produce a vkey-valid proof')
server.close()
