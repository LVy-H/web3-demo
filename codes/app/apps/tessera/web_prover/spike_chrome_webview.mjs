// Browser-context datapoint for the M1 spike (NOT emulator verification).
//
// Loads the SAME assets/zk/prover_host.html in real headless Chromium — the
// browser engine the Android System WebView is built on — and exercises the
// genuine fetch()/Blob/WASM/snarkjs path the WebView would, for BOTH artifact
// delivery strategies the mobile harness supports:
//   - localhostHttp: snarkjs fetch()es http://127.0.0.1 URLs (known-good)
//   - blobUrl:       bytes handed to JS as base64 → URL.createObjectURL(Blob)
//                    (the path Node's undici can't represent; the spec's
//                     preferred production path)
// Each proof is verified in-process against the real Groth16 vkey via the
// bundle's zkVerifyProof. This does NOT cover the Flutter↔WebView channel, so
// it is not a GO — it only narrows where the remaining risk lives.
//
//   node spike_chrome_webview.mjs        (needs CHROME_EXECUTABLE or chromium on PATH)
import { readFileSync } from 'fs'
import { createServer } from 'http'
import { spawn } from 'child_process'
import { WebSocket } from 'ws'

const here = (p) => new URL(p, import.meta.url)
const bundle = readFileSync(here('../web/zkprover.js'))
const page = readFileSync(here('../../../packages/core_crypto/assets/zk/prover_host.html'))
const wasm = readFileSync(here('../../../packages/core_crypto/assets/zk/semaphore-16.wasm'))
const zkey = readFileSync(here('../../../packages/core_crypto/assets/zk/semaphore-16.zkey'))

// Single-origin loopback server (mirrors WebViewProverHost).
const server = createServer((req, res) => {
  const u = req.url
  const send = (b, t) => { res.writeHead(200, { 'content-type': t, 'access-control-allow-origin': '*' }); res.end(b) }
  if (u.endsWith('semaphore-16.wasm')) send(wasm, 'application/wasm')
  else if (u.endsWith('semaphore-16.zkey')) send(zkey, 'application/octet-stream')
  else if (u.endsWith('zkprover.js')) send(bundle, 'text/javascript')
  else send(page, 'text/html')
})
await new Promise((r) => server.listen(0, '127.0.0.1', r))
const port = server.address().port
const base = `http://127.0.0.1:${port}`

const chrome = process.env.CHROME_EXECUTABLE || 'chromium'
const proc = spawn(chrome, [
  '--headless=new', '--disable-gpu', '--no-sandbox',
  '--remote-debugging-port=0', '--user-data-dir=/tmp/zk-chrome-spike',
], { stdio: ['ignore', 'ignore', 'pipe'] })

// Chrome prints "DevTools listening on ws://..." to stderr.
const wsUrl = await new Promise((resolve, reject) => {
  let buf = ''
  const t = setTimeout(() => reject(new Error('no DevTools endpoint in 20s')), 20000)
  proc.stderr.on('data', (d) => {
    buf += d
    const m = buf.match(/ws:\/\/[^\s]+/)
    if (m) { clearTimeout(t); resolve(m[0]) }
  })
})

const ws = new WebSocket(wsUrl)
await new Promise((r) => ws.on('open', r))
let msgId = 0
const pend = new Map()
ws.on('message', (raw) => {
  const m = JSON.parse(raw)
  if (m.id && pend.has(m.id)) pend.get(m.id)(m)
})
const cmd = (method, params = {}) => new Promise((resolve) => {
  const id = ++msgId
  pend.set(id, resolve)
  ws.send(JSON.stringify({ id, method, params }))
})

await cmd('Page.enable')
await cmd('Runtime.enable')
await cmd('Page.navigate', { url: `${base}/prover_host.html` })
// Wait for the bundle global to appear.
async function waitReady() {
  for (let i = 0; i < 60; i++) {
    const r = await cmd('Runtime.evaluate', { expression: 'typeof window.zkGenerateVoteProof', returnByValue: true })
    if (r.result?.result?.value === 'function') return true
    await new Promise((r) => setTimeout(r, 500))
  }
  return false
}
const ready = await waitReady()
console.log('browser ready (zkGenerateVoteProof present):', ready)
if (!ready) { proc.kill(); server.close(); process.exit(1) }

const SEED = 'zkvote-spike-deterministic-seed'
const MEMBERS = ['3202130587429391573947668392496818956012089007761520528168518742099046353681', '22222222222222222222', '33333333333333333333']

// Run a proof + verify entirely inside the page, return {depth, valid}.
async function proveInPage(artifactsExpr) {
  const expr = `(async () => {
    const json = await window.zkGenerateVoteProof(
      ${JSON.stringify(SEED)}, ${JSON.stringify(MEMBERS)}, 1,
      "0x1111111111111111111111111111111111111111",
      ${artifactsExpr});
    const valid = await window.zkVerifyProof(json);
    const p = JSON.parse(json);
    return JSON.stringify({ depth: p.merkleTreeDepth, points: p.points.length, valid });
  })()`
  const r = await cmd('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })
  if (r.result?.exceptionDetails) {
    return { error: JSON.stringify(r.result.exceptionDetails).slice(0, 300) }
  }
  return JSON.parse(r.result.result.value)
}

console.log('--- localhostHttp delivery ---')
const httpRes = await proveInPage(
  `{ depth: 16, wasm: ${JSON.stringify(base + '/semaphore-16.wasm')}, zkey: ${JSON.stringify(base + '/semaphore-16.zkey')} }`)
console.log('localhostHttp:', JSON.stringify(httpRes))

console.log('--- blobUrl delivery (base64 -> Blob in-page) ---')
const wasmB64 = wasm.toString('base64')
const zkeyB64 = zkey.toString('base64')
const blobRes = await proveInPage(
  `{ depth: 16, wasm: blobUrlFromBase64(${JSON.stringify(wasmB64)}, "application/wasm"), zkey: blobUrlFromBase64(${JSON.stringify(zkeyB64)}, "application/octet-stream") }`)
console.log('blobUrl:', JSON.stringify(blobRes))

proc.kill()
server.close()
ws.close()

const httpOk = httpRes.valid === true && httpRes.depth === 16
const blobOk = blobRes.valid === true && blobRes.depth === 16
console.log(`SUMMARY httpOk=${httpOk} blobOk=${blobOk}`)
process.exit(httpOk ? 0 : 1)
