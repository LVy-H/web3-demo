# Phase 11 M1 — WebView on-device proving spike — FINDINGS

> **Date:** 2026-06-02 · **Owner:** Hoang · **Branch:** `feat/mobile-proving-spike`
> **Spec:** `docs/superpowers/specs/2026-06-02-mobile-scan-and-native-proving-design.md`
> **Decision (2026-06-02, original session):** NO-GO (BLOCKED) — emulator never launched.
> **Decision (2026-06-03, re-verify session): ✅ GO — proof generated in an Android
> WebView on the emulator, passes the REAL Groth16 vkey.** See
> **[RE-VERIFY 2026-06-03 — GO](#re-verify-2026-06-03--go)** at the bottom; the
> original BLOCKED write-up below is preserved as-is for the record.

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

### Environmental at root — control test, with an important asymmetry

Running the repo's **known-good** `integration_test/app_test.dart` (the existing
e2e, a smaller APK with no zk artifacts) on the same emulator also failed — and
the same `Broken pipe (32)` instability on the emulator's `package`/`activity`
services is the shared root cause. But the two do **not** fail at the same stage,
and the difference matters:

- **Spike** (every attempt): `am start … MainActivity does not exist` — a
  **pre-launch** failure. The app process never started.
- **Control** (`app_test`): `WebSocketChannelException … /ws` — a **post-launch**
  failure. The VM-service ws URL only exists after the app process starts and the
  Dart VM comes up, so the control **did launch**; its failure was the
  VM-service handshake dying (Broken pipe on system services).

So the control launching where the spike never does means the larger (+5.2 MB)
spike APK is **not ruled out** as a contributing factor — if anything it mildly
implicates it: a heavier streamed install loses the post-install
package-registration race (the window before `am start`) more reliably, which is
why the spike always fails *pre-launch*. Honest root cause: emulator
`system_server` is unstable (`Broken pipe` — proven directly), **and** the bigger
APK plausibly compounds the install-commit race. Both feed the same outcome:
**blocked → spike question unanswered.** Note the manual `adb install -r` + ~3s
settle + `am start` **succeeds** (below), proving the activity/manifest/build are
correct and the app *is* launchable — the failure is the race, not a code or
manifest bug, so the spike test itself is sound and should run on a quiet host.

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

---

# RE-VERIFY 2026-06-03 — GO

> **Branch:** `mobile-proving-reverify` (off `feat/mobile-proving-spike`).
> **Decision: ✅ GO.** A Semaphore Groth16 vote proof generated **inside an Android
> `webview_flutter` WebView on the emulator**, from the BUNDLED depth-16 artifacts,
> **passes the REAL Groth16 vkey.** The one open M1 question is answered YES.

## What unblocked it — the known-good emulator recipe for THIS host

The original session was blocked because it ran on the flake's default **API-36**
playstore image under heavy host load: swiftshader's GL abort destabilised
`system_server` (`Broken pipe (32)` on the `package`/`activity` services), and the
`install → am start` race lost every time (`MainActivity does not exist`,
pre-launch). The fix was the documented recipe:

- **AVD:** `Pixelhi` — an **API-31 `google_apis` x86_64** AVD
  (`image.sysdir.1=system-images/android-31/google_apis/x86_64/`, RAM bumped
  2048→4096). API-31 has **no swiftshader GL abort**, so `system_server` stays
  stable and the install/launch race simply does not occur.
- **Renderer:** Skia, via a **debug-only** `EnableImpeller=false` meta-data in
  `android/app/src/debug/AndroidManifest.xml` (release/profile keep the Flutter
  default; web/desktop unaffected). WebView JS execution is independent of
  Flutter's renderer, so this is belt-and-suspenders, not the crux.
- **Boot:** headless cold boot `emulator -avd Pixelhi -no-window -no-snapshot
  -wipe-data -gpu swiftshader_indirect -memory 4096`. Reached
  `sys.boot_completed=1` in **~30 s**; `pm list packages` → 176 (package service
  responsive — the exact thing that broke on API-36).

### SDK note — the API-31 image had to be installed by hand

The Nix SDK ships **only** `android-36.1`; `~/asdk/system-images` is a symlink into
the read-only Nix store. `sdkmanager "system-images;android-31;google_apis;x86_64"`
failed (`Failed to read or create install properties file` — it can't write the
read-only target). Workaround that worked:

1. Replace the `system-images` symlink with a real writable dir, re-linking the
   existing `android-36.1` back in (mirrors how the flake overlays `platforms`/
   `ndk`/`cmake`).
2. Download the image zip directly from Google
   (`dl.google.com/android/repository/sys-img/google_apis/x86_64-31_r14.zip`,
   1.47 GB) and **verify sha1** (`9aedd3e85cad7a479146f6858f4a94840c2a3f29`, matched).
3. Unzip into `…/system-images/android-31/google_apis/` so `x86_64/system.img`
   lands at the path the AVD's `image.sysdir.1` expects. `source.properties` ships
   inside the zip, so no hand-written `package.xml` was needed; the emulator reads
   the files directly (sdkmanager's package index never lists it — irrelevant).

## Evidence — M1 (spike harness, WebViewProverHost directly)

`flutter test integration_test/mobile_prover_spike_test.dart -d emulator-5554`:

- APK built + **installed in 805 ms with no race**, app launched, test green
  (`All tests passed!`).
- `SPIKE httpError=null` → **localhost-HTTP** delivery proved in-WebView.
- `SPIKE_BLOB ok=true depth=16 error=null` → the **blob-URL** path (the spec's
  preferred production path, the ~4.5 MB-base64-over-the-bridge open risk) **also
  works** on the emulator.
- `SPIKE_PROOF_JSON` (depth 16, 8 points, golden 3-member group) → fed to the
  independent oracle `node web_prover/desktop_prover.mjs web/zkprover.js` (verify)
  → **`{"ok":true,"valid":true}`**. Tampered nullifier → `valid:false` (the oracle
  is not a rubber stamp). The proof's `points` differ from the host-side proof in
  the table above — Groth16 is randomised, so a *different* valid proof over the
  same public inputs is exactly expected; `merkleTreeRoot`/`nullifier`/`scope`
  match the golden vector.

## Evidence — M2 (production `ProofServiceMobile`, via the `ProofService` interface)

The spike proves the *engine*; M2 proves the *wiring*.
`flutter test integration_test/mobile_proof_service_test.dart -d emulator-5554`
constructs the `ProofServiceMobile` the factory returns on Android, mounts its
**own** `hostView` (the same 1×1 offstage WebView the app shell mounts via
`MaterialApp.builder`), and calls the public interface:

- `SVC_COMMITMENT value=3202130587…46353681 error=null` — `deriveCommitment` ran
  in the WebView (`window.zkCommitment`, Android's JSON-quoted result unwrapped)
  and returned **exactly the golden commitment**. This op was **never** exercised
  in the M1 spike; now verified.
- `SVC_PROOF_JSON` (depth 16, 8 points) → real-vkey oracle → **`{"ok":true,
  "valid":true}`**; tampered point → `valid:false`. Test green (`All tests passed!`).

So both the on-device prover AND the factory wiring that selects it are verified
end-to-end, not merely analyze-clean.

## Decision: GO → M2 wired

Per the M1 gate, M2 is now started and landed on this branch:

- `lib/data/services/proof_service_mobile.dart` — `ProofServiceMobile` wraps the
  (verified, untouched-engine) `WebViewProverHost`: lazy single-flight init,
  `generateVoteProof → RelayProof`, `deriveCommitment`, exposes `hostView`.
- `proof_service_stub.dart` — factory branch: **Android → `ProofServiceMobile`**;
  `platformProofServiceAvailable` true on Android. **iOS stays
  `ProofServiceUnsupported` (fenced)** — same WebView host, unverified-until-a-device
  per the design doc. Desktop sidecar + web js_interop paths **untouched**.
- `main.dart` — mounts the offstage host WebView once via `MaterialApp.builder`
  (`_ProofHostMount`; no-op cast on web/desktop, so `webview_flutter` stays off
  their UI path).
- `proof_webview_host.dart` — **additive only** (eager controller getter so a
  widget can mount before `init`; a `deriveCommitment` method). The M1 spike test
  still compiles and passes.
- `test/data/services/zkprover_bundle_parity_test.dart` — fails if
  `assets/zk/zkprover.js` drifts from `web/zkprover.js` (the APK ships only
  `assets/`), closing the FINDINGS step-5 drift gap.

`flutter analyze`: **clean**. Host tests (`proof_service_test` + parity): green.

## Honest bounds / fences (verified-or-fenced)

- **Verified on the emulator under Skia** (the debug Impeller-off flag). WebView JS
  runs in the Android **System WebView**, which is independent of Flutter's
  renderer, so a real device on Impeller exercises the same WebView — **expected to
  work, but not yet device-confirmed.** Not claiming an Impeller device run.
- **Android only.** iOS is fenced (`ProofServiceUnsupported`) until a device
  confirms; the camera/scanner half (M3) is out of scope here.
- **No on-chain vote was cast** in this session (M2's "cast a real vote from the
  emulator" sub-goal). What is proven is the cryptographic claim that mattered: an
  on-device proof that the **real vkey** accepts. On-chain casting + the QR scanner
  remain follow-ups (real-device gate for the camera per the design doc).
- **Host note:** the box was *not* fully solo — a leftover `flutter run -d linux`
  (desktop app, another session) ran throughout; it did not block (API-31 removed
  the race root cause), but RAM got tight (~3.5 GiB free with emulator up).
