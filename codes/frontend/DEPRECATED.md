# ⚠️ DEPRECATED — React frontend (legacy)

As of 2026-06-02, the **Flutter app at `codes/mobile/` (Tessera) is the canonical
client across every platform — mobile, desktop, AND web.** This React/Vite app is
**legacy** and no longer the web target; new feature work goes into the Flutter
app, which has reached parity (browse, create, M1 anon-vote, M2 blind-vote,
verify/receipts, identity, and the live-meeting host + voter) and adds desktop +
native.

## Why it's still here (not deleted yet)

Two dev-toolchain couplings must be decoupled before `codes/frontend/` can be
removed without breaking a working path:

1. **`dev-stack.sh`** reads/writes the deployed-addresses fixture at
   `codes/frontend/src/deployed-addresses.json` (written by
   `codes/contracts/scripts/deploy.ts`). Move this to a neutral location (e.g.
   `codes/contracts/`) and repoint `dev-stack.sh` + the contracts deploy script.
2. **The web prover bundle** (`codes/mobile/web/zkprover.js`) is rebuilt by
   `codes/mobile/web_prover/` reusing the frontend's installed Semaphore deps via
   a `node_modules` symlink. Give `web_prover/` its own `package.json` with the
   `@semaphore-protocol/*` deps so it rebuilds standalone. (The bundle itself is
   committed, so a checkout already runs without this.)

Once both are decoupled, `codes/frontend/` can be deleted.

## Running the web app today

```sh
cd codes/mobile && flutter run -d chrome     # or: flutter build web
```
