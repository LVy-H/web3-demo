# web_prover — Semaphore v4 proof bundle for Flutter web

Bundles the SAME Semaphore v4 prover the React app uses into a single
self-contained IIFE (`../web/zkprover.js`) that the Flutter **web** build loads
(`web/index.html` `<script>`) and calls via `dart:js_interop`
(`lib/data/services/proof_service_web.dart`).

This is the **web** leg of the ZK vote path. Native (mobile/desktop) proving is
deferred (plan D2 / Open-Q6) — `proof_service_stub.dart` throws until scoped.

## Build / regenerate the bundle

Reuses the frontend's installed Semaphore deps via a `node_modules` symlink
(ext4 worktree, so symlinks work):

```sh
cd codes/mobile/web_prover
ln -sfn ../../../frontend/node_modules node_modules   # one-time
npx vite build                                        # → ../web/zkprover.js
```

## Verify the bundle (crypto, against the real Groth16 vkey)

```sh
node verify.mjs   # generate a proof with the exact bundle → verifyProof == true
```

`../web/zkprover.js` is committed as a vendored build artifact so a checkout can
run the web app without re-running this build.
