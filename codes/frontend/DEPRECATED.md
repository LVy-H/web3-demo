# ⚠️ DEPRECATED — React frontend (legacy)

As of 2026-06-02, the **Flutter app at `codes/mobile/` (Tessera) is the canonical
client across every platform — mobile, desktop, AND web.** This React/Vite app is
**legacy** and no longer the web target; new feature work goes into the Flutter
app, which has reached parity (browse, create, M1 anon-vote, M2 blind-vote,
verify/receipts, identity, and the live-meeting host + voter) and adds desktop +
native.

## Why it's still here (not deleted yet)

One dev-toolchain coupling remains before `codes/frontend/` can be removed
without breaking a working path:

1. **`dev-stack.sh` + `codes/contracts/scripts/{deploy,demo-poll,copyAbis}.ts`**
   read/write the deployed-addresses fixture and ABIs under
   `codes/frontend/src/`. Move these to a neutral location (e.g.
   `codes/contracts/`) and repoint the scripts + `dev-stack.sh`'s `ADDRESSES`.

2. ~~The web prover bundle reused the frontend's `node_modules` via a symlink.~~
   **DONE** — `codes/mobile/web_prover/` now has its own `package.json`
   (`@semaphore-protocol/*` + vite) and rebuilds standalone (verified: the
   rebuilt bundle still produces a vkey-valid proof + correct commitment).

Once coupling 1 is decoupled, `codes/frontend/` can be deleted.

## Running the web app today

```sh
cd codes/mobile && flutter run -d chrome     # or: flutter build web
```
