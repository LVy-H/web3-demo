# Phase 11 M1 — WebView on-device proving spike — FINDINGS

> **Date:** 2026-06-02 · **Owner:** Hoang · **Branch:** `feat/mobile-proving-spike`
> **Spec:** `docs/superpowers/specs/2026-06-02-mobile-scan-and-native-proving-design.md`
> **Decision:** **NO-GO (BLOCKED) — spike question UNANSWERED, not answered-no.**

## The one question M1 had to answer

> Can an Android device generate a real Semaphore Groth16 vote proof inside a
> `webview_flutter` WebView, using BUNDLED artifacts, and does that proof pass
> the REAL Groth16 verification key?

**Status: undetermined.** The Flutter app **never launched on the emulator this
session** (install→launch race under heavy concurrent host load — details below),
so there is **zero on-device WebView evidence**. This is explicitly *not* a
finding that the WebView can't prove; it is that the emulator step could not be
run in reasonable time on this host. Everything that does NOT require the
emulator was completed and verified host-side.

## What was BUILT and VERIFIED (host-side, real Groth16 vkey)

| Item | Status | Evidence |
|---|---|---|
| `entry.js` additive `opts` arg (`{depth, wasm, zkey}`) | ✅ done, web/desktop unaffected | `node web_prover/verify.mjs` → `VERIFY = true`, `merkleTreeDepth = 1` (the no-opts path is byte-for-byte unchanged: CDN fetch, dynamic depth) |
| Rebuilt bundle `web/zkprover.js` (vite) | ✅ done | `npm i && npm run build` → 483 kB IIFE |
| Bundled depth-16 artifacts in `assets/zk/` | ✅ done | `semaphore-16.wasm` (1.8 MB, `\0asm` magic), `semaphore-16.zkey` (3.4 MB, `zkey` magic) — verified genuine binaries, not HTML error pages |
| Depth-16 proof via the `opts` branch verifies vs real vkey | ✅ done | `node web_prover/spike_bundled_artifacts.mjs` → `merkleTreeDepth = 16`, 8 points, `VERIFY = true` |
| **Independent trusted-oracle reach-back** | ✅ done | depth-16 proof generated via `opts` path → fed to the **separate** `desktop_prover.mjs` `verify` op (a distinct process eval'ing the same bundle) → `{"ok":true,"valid":true}` |
| `webview_flutter` promoted to direct dep | ✅ done | `pubspec.yaml` + `pubspec.lock` (4.13.1) |
| Headless WebView host (`assets/zk/prover_host.html`) | ✅ written | includes `zkprover.js`, `Prover` JS channel, blob + http delivery helpers |
| `WebViewProverHost` spike harness (`lib/data/services/proof_webview_host.dart`) | ✅ written | single loopback `HttpServer` serves page+bundle+artifacts same-origin; both `localhostHttp` and `blobUrl` delivery strategies |
| Spike integration test (`integration_test/mobile_prover_spike_test.dart`) | ✅ written, `flutter analyze` clean | mounts offstage `WebViewWidget`, runs HTTP path (GO-locking), prints `SPIKE_PROOF_JSON`, then opportunistically tries blob; **could not execute** (app never launched) |
| `flutter analyze` | ✅ clean | `No issues found!` |

### The proof JSON the WebView *would* emit (generated host-side, oracle-verified)

```json
{"merkleTreeDepth":16,"merkleTreeRoot":"13595059668242345249690395141353999022660372864385406352406340554685238205680","nullifier":"20559540126755879222057807050748194962891640475982220071686806770212688780786","message":"1","scope":"97433442488726861213578988847752201310395502865","points":["17187204112615299126348222725618499139905023797521123560316896502208113484232","1559657109013243361332623228136984762003571761361785530980471889206140206190","18023737455874954348647099434970348367946763216232015431972897387436107532608","451654930556019766623618876712524820819983551499005419995544798945215540713","20922157845098686639852741768756349139012601200826954583534134251586932207497","18245751794872071488045447127020306537099455714275678059950696485752966398834","796842745490689104144776033764748143099088219175730616077818159604802597284","15226782720868755968178376163485971513897511447511994369730024358948352664328"]}
```

`desktop_prover.mjs verify` (independent oracle) → `{"id":1,"ok":true,"valid":true}`.
Golden 3-member group; `members[0]` is the seed's commitment, same vector as
`web_prover/verify.mjs` and `desktop_prover_test`.

### Headless-Chromium browser-context datapoint — attempted, inconclusive here

`web_prover/spike_chrome_webview.mjs` loads the *actual* `prover_host.html` in real
headless Chromium (the engine the Android System WebView is built on) and runs
both delivery strategies — including the **blob** path Node's `undici` can't
represent — verifying each proof in-page against the real vkey. On this sandboxed
host Chromium's CDP `Page.navigate` issued no network request (the loopback server
saw zero hits), so the run was inconclusive **for environment reasons, not script
logic**. Left in the branch to run on a normal host; it is a fence-strengthening
datapoint only, never a substitute for emulator verification (it does not exercise
the Flutter↔WebView channel).

## What is BLOCKED — the emulator

The Flutter app could not be launched on the emulator. Every launch path failed
identically:

```
Installing build/app/outputs/flutter-apk/app-debug.apk...   968ms   <- install REPORTS success
...
Error type 3
Error: Activity class {com.zkvote.mobile/com.zkvote.mobile.MainActivity} does not exist.
  Command: adb -s emulator-5554 shell am start ... com.zkvote.mobile/com.zkvote.mobile.MainActivity
```

Root cause: the emulator's `package`/`activity` system services are intermittently
unresponsive (`Failure calling service package: Broken pipe (32)` /
`Failure calling service activity: Broken pipe (32)` seen directly). Flutter's
`install → immediately am start` sequence lands in a window where the just-installed
package has been dropped/not-yet-committed by a churning `system_server`, so the
launcher activity 404s. Under host monitoring, `PackageManager` was observed
re-scanning app dirs *after* the test ran — i.e. `system_server` cycled mid-session.

### This is environmental, proven by a control test

Running the repo's **known-good** `integration_test/app_test.dart` (the existing
e2e, a smaller APK with no zk artifacts) on the same emulator failed **identically**:
`Broken pipe (32)` on the activity + package services, and the VM-service WebSocket
never connected. So the blocker is the emulator/host, **not** the spike code and
**not** the larger (+5.2 MB) APK.

Likely trigger: heavy concurrent host load. At spike time the host was running
another agent's live `flutter run -d linux` session, a Gradle daemon (`-Xmx8G`), a
Kotlin compiler daemon, a second worktree's `flutter analyze`, and the emulator
qemu — saturating RAM/IO and starving the emulator's `system_server`.

### Remedies tried (all exhausted, none unblocked it)

1. `flutter test integration_test/...` (the dev-stack.sh e2e runner) — race.
2. Manual `adb install -r` + `am start` with a settle delay — **works** (proves the
   APK and activity are correct; the app *is* launchable when the package service
   is quiet). But `flutter test` always reinstalls, re-triggering the race.
3. `--use-application-binary` — not supported by `flutter test`.
4. `flutter drive --driver=test_driver/integration_test.dart` — same race.
5. `adb kill-server/start-server` + `emu-kill` + **cold boot with `ZK_EMU_WIPE=1`** —
   improved persistence (idle-poll mostly held) but the launch race recurred.
6. `adb uninstall` + disable install verifier
   (`verifier_verify_adb_installs 0`, `package_verifier_enable 0`) + clean run — race recurred.

## Decision: NO-GO (blocked), per the spec's gate

The spike could not be completed on the emulator in reasonable time. Per the M1
gate ("nothing else builds until this passes") and the honesty bar (verified-or-
fenced), **M2 is NOT started**: `ProofServiceMobile` is not wired behind the
factory; Android still resolves to `ProofServiceUnsupported`. The web/desktop
provers are untouched and remain green.

The spike code is preserved on this branch so the emulator run can be retried on a
**quiet host** (or a real device via `ZK_DEVICE=<serial>` per the e2e harness),
where the lone remaining unknown is the Flutter↔WebView channel + Android System
WebView running snarkjs — the proving math itself is already vkey-verified.

## To resume (when the host is quiet / on a real device)

1. Ensure no other heavy flutter/gradle/qemu/emulator sessions are running.
2. `./dev-stack.sh emu` (proving needs no chain/relayer).
3. `flutter test integration_test/mobile_prover_spike_test.dart -d emulator-5554`
   (retry the install if `am start` 404s — it is a transient race, not a code bug).
4. Capture the `SPIKE_PROOF_JSON ...` line from stdout; verify it independently:
   `echo '{"id":1,"op":"verify","proof":<paste>}' | node web_prover/desktop_prover.mjs web/zkprover.js`
   → `valid:true` is the GO. Note which delivery path worked (`SPIKE httpError=` /
   `SPIKE_BLOB ...` lines). `localhostHttp` is the known-good primary; `blobUrl` is
   the spec's preferred production path (the ~4.5 MB base64 zkey over the Dart→JS
   bridge is the open risk).
5. On GO → proceed to M2 (factory wiring) and add a build step that re-copies the
   rebuilt `web/zkprover.js` into `assets/zk/zkprover.js` so the bundle can't drift
   (the APK ships only `assets/`, not `web/`).

## Notes / follow-ups

- **Asset-bundling gotcha (resolved here):** `web/zkprover.js` is web-build-only and
  is NOT packaged into the APK; only `flutter: assets:` are. The spike copies the
  built bundle to `assets/zk/zkprover.js`. M2 must automate that copy.
- Android **debug** manifest already sets `usesCleartextTraffic="true"` + INTERNET,
  so the loopback-HTTP artifact path needs no manifest change for test/debug builds.
- `web_prover/spike_bundled_artifacts.mjs` is the host-side pre-flight; keep it as a
  fast regression check for the bundled artifacts + `opts` branch.
