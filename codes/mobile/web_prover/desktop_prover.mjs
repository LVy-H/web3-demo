// Desktop ZK prover SIDECAR (SP4).
//
// Reuses the EXACT same self-contained Semaphore v4 bundle the Flutter web build
// uses (`../web/zkprover.js`, a vite IIFE) — eval'd in Node, no node_modules —
// and answers `prove`/`verify` requests over stdio (one JSON object per line).
// Flutter desktop (Linux/Windows/macOS) spawns this via `proof_service_desktop.dart`
// so it can cast Semaphore votes a phone-only webview prover can't reach.
//
//   node desktop_prover.mjs <path-to-zkprover.js>
//
// Protocol (line-delimited JSON):
//   → {"id":1,"op":"prove","seed":"...","members":["..."],"message":1,"scope":"0x.."}
//   ← {"id":1,"ok":true,"proof":{merkleTreeDepth,merkleTreeRoot,nullifier,message,scope,points}}
//   → {"id":2,"op":"verify","proof":{...}}
//   ← {"id":2,"ok":true,"valid":true}
import { readFileSync } from 'fs'
import { createInterface } from 'readline'

const bundlePath = process.argv[2]
if (!bundlePath) {
  console.error('usage: node desktop_prover.mjs <zkprover.js>')
  process.exit(2)
}
const code = readFileSync(bundlePath, 'utf8')
// The IIFE assigns globalThis.zkGenerateVoteProof / zkVerifyProof.
;(0, eval)(code)

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n')
}

const rl = createInterface({ input: process.stdin })
rl.on('line', async (raw) => {
  const line = raw.trim()
  if (!line) return
  let req
  try {
    req = JSON.parse(line)
  } catch {
    return
  }
  const { id, op } = req
  try {
    if (op === 'prove') {
      const proofJson = await globalThis.zkGenerateVoteProof(
        req.seed, req.members, req.message, req.scope)
      send({ id, ok: true, proof: JSON.parse(proofJson) })
    } else if (op === 'verify') {
      const valid = await globalThis.zkVerifyProof(JSON.stringify(req.proof))
      send({ id, ok: true, valid })
    } else if (op === 'commitment') {
      send({ id, ok: true, commitment: globalThis.zkCommitment(req.seed) })
    } else if (op === 'ping') {
      send({ id, ok: true, pong: true })
    } else {
      send({ id, ok: false, error: 'unknown op: ' + op })
    }
  } catch (e) {
    send({ id, ok: false, error: String((e && e.message) || e) })
  }
})
