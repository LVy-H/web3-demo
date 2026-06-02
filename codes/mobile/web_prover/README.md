# web_prover — Semaphore v4 proof bundle

Bundles Semaphore v4 into a single self-contained IIFE (`../web/zkprover.js`)
exposing `zkGenerateVoteProof`, `zkVerifyProof`, and `zkCommitment` on
`globalThis`. Used by:

- **web** — loaded via `web/index.html` `<script>`, called through
  `dart:js_interop` (`lib/data/services/proof_service_web.dart`).
- **desktop** — `desktop_prover.mjs` eval's the same bundle under Node;
  `lib/data/services/proof_service_desktop.dart` drives it over stdio.

**Self-contained** — its own `package.json` (no dependency on the deprecated
React frontend).

## Build / regenerate the bundle

```sh
cd codes/mobile/web_prover
npm install          # one-time (Semaphore + vite)
npm run build        # → ../web/zkprover.js
```

## Verify the bundle (crypto, against the real Groth16 vkey)

```sh
node verify.mjs   # generates a proof with the exact bundle → verifyProof == true
```

`../web/zkprover.js` is committed as a vendored build artifact so a checkout can
run the web/desktop prover without re-running this build.
