# Design — Android share/JOIN loop, honest device-fencing, UX niches, release readiness

- **Date:** 2026-06-13
- **Status:** Draft (autonomous round, post-Revolution R1–R4)
- **Scope owner:** continuation round after the R1–R4 Revolution cutover (PR #124 merged)
- **Branch:** `feat/android-share-loop`

## 1. Context

R1–R4 shipped the product-layer Revolution: pub workspace, journey engine, three-space
IA (VOTE / ORGANIZE / JOIN / You), privacy defaults. `codes/app/` is the sole client.
The next *planned* iteration (FOCUS.md) is R5 cryptographic sealing + Sepolia readiness —
a separate, design-first track. **This round is orthogonal**: it closes UX/feature gaps
that only bite *off the dev machine* — exactly the "things we can't test right now
(Android)" surface — without touching crypto or the on-chain layer.

### The core finding

The app's growth mechanic is **spread a poll → someone joins it**: SHARE sheets, QR,
NFC tap-to-open, `TES-XXXXXX` codes, and a typed deep-link grammar (`feature_join`).
On a real Android build that loop is **half-open at both ends**, and every break is
invisible on web/desktop where the team develops:

| # | Gap | Evidence | Impact on a real APK |
|---|-----|----------|----------------------|
| G1 | No deep-link intent-filter | `AndroidManifest.xml` has only `MAIN`/`LAUNCHER` | Tapping a `tessera://` link / scanning an NFC tag does **not** open the app |
| G2 | No incoming-link handler | no `app_links`/`uni_links` dep; `app.dart` builds router with fixed `initialLocation`, never listens | even if Android routed a link in, nothing consumes it |
| G3 | No INTERNET in release manifest | `INTERNET` only in `src/debug/AndroidManifest.xml` | release APK **cannot reach** relayer/RPC |
| G4 | Missing `network_security_config.xml` | CHANGELOG claims it shipped; **not in repo**, manifest doesn't reference it | release build regresses the on-device WebView-prover hang (cleartext loopback blocked) |
| G5 | NFC capability may be dishonest | `hasNfc = (platform==android)`; `organizer_journey` offers `ShareTarget.nfc`; **no `nfc_manager` dep** in `codes/app` | "NFC" tile promises a write the app can't perform |

The grammar (`parseJoinInput`), the target→route map (`locationForJoinTarget`), the
routes (`/poll/:address`, `/live/...`, `/join/resolve`, `/you/verify`), and the nav
helpers (`pushOnce`) **all already exist and are unit-tested**. G1/G2 are purely the
missing *bridge*; nothing in the grammar needs to change.

## 1b. Hard constraints (owner directive, 2026-06-13)

Two non-negotiable rules govern every change this round:

1. **Verifiable-only.** Ship a capability only if we can confirm it works *now* with the
   tools we have: deterministic unit/widget tests, `flutter analyze`, the Android
   emulator (`adb am start` / `dev-stack.sh e2e`), or an APK build. Anything whose
   correctness can only be confirmed on hardware we don't have is **not built** this
   round — it is honestly fenced with a reason the user can read.
2. **No ghost features.** Do not add (or keep) any affordance the user cannot actually
   use, or that conflicts with existing UX. A capability flag must reflect reality. Where
   a ghost already exists, **remove it**.

### Ghost inventory (to remove / make honest)

- **NFC "tap-to-share" (confirmed ghost).** `distribute_sheet` shows "hold the voter's
  phone to the back of this one" — that is Android Beam / NDEF push, **removed by Google
  in Android 10+**. There is no NFC code behind it, yet `hasNfc=true` lights the tile on
  every Android device. *Resolution: honest-disable* — `hasNfc=false` (with a reason key)
  and drop the NFC tile + `ShareTarget.nfc`. Writing to a physical tag is the only viable
  NFC path and is unverifiable without a phone + tag, so it stays out by rule (1).
- **Custom-scheme share link on web (UX-conflict guard).** `shareLinkForPoll` emits
  `tessera://poll/<addr>`. The *primary* share path is the QR scanned by a phone (works
  after Track 1). A `tessera://` link copied into a desktop browser opens nothing — we do
  **not** present it as a clickable universal link, and we do not claim web→web link
  opening (that needs an `https` mirror + hosted `assetlinks.json`, out of scope). The QR
  remains the honest, working affordance.

## 2. Tracks

### Track 1 — Close the share/JOIN loop (keystone)

**1a. Deep-link bridge.** Add `app_links`. New `DeepLinkService` (in the shell,
`lib/routing/`) with a constructor that takes:
- a `Stream<Uri>` of incoming links and a `Future<Uri?>` initial-link source
  (production: `AppLinks()`; tests: fakes — no platform channel),
- a `void Function(String location)` navigate callback (production: `router.go`).

For each URI: `parseJoinInput(uri.toString())` → `locationForJoinTarget(target)` →
navigate. `UnknownTarget` already maps to `/error` with a reason, so hostile/garbage
links degrade safely through the *same* tested path the QR scanner uses. Wired in
`app.dart` after the router is built; `main.dart` stays the one production wiring.

*Why app_links and not go_router's built-in deep linking:* the Tessera custom scheme
encodes the first segment as the URI **host** (`tessera://poll/<addr>` → host=`poll`),
which go_router's path parser mis-handles. Routing the raw URI through the existing
grammar is the correct, already-tested mapping. Custom-scheme launches don't populate
Flutter's `defaultRouteName`, so there's no double-navigation race with go_router's
`initialLocation`.

**1b. Android manifest + release network.**
- Add a `VIEW`/`BROWSABLE` `<intent-filter>` for `android:scheme="tessera"` on
  `MainActivity` (launchMode already `singleTop`, so re-entrant links land via the
  stream, not a new task).
- Add `<uses-permission android:name="android.permission.INTERNET"/>` to the **main**
  manifest.
- Create `res/xml/network_security_config.xml` permitting cleartext **only** for
  `127.0.0.1`, `localhost`, `10.0.2.2` (emulator host); everything else stays
  encrypted-only. Reference it via `android:networkSecurityConfig` +
  `android:usesCleartextTraffic="false"` on `<application>`.

**Verification:** unit/widget test the bridge (fake link stream + spy navigate);
`flutter analyze`; manifest correctness by inspection + APK build (CI `android` job /
local `devenv --profile android`); emulator `dev-stack.sh e2e` can `adb shell am start`
a `tessera://` intent to confirm cold/warm launch routing. Real-phone NFC-tag tap stays
device-fenced (documented).

### Track 2 — Honest device-fencing UX

The design principle (Revolution §4.3) is **capabilities never lie**. Fixes:
- **NFC:** decide between (a) wire a real `nfc_manager` NDEF writer for the distribute
  sheet (Android-only, logic unit-tested, hardware fenced) or (b) drop `hasNfc` to a
  reason-keyed "not in this build yet". Default to (b) for this round unless the writer
  is small and self-contained — an unimplemented promise is worse than an honest "not
  yet". Pick one; do not leave the half-state.
- **Camera-denied:** `mobile_scanner` permission-denied / no-camera path shows the paste
  fallback with a clear reason, not a blank/black scanner.
- **Messaging:** where a capability is false, the surface shows the mapped reason copy
  (the `CapabilityReasons` keys already exist) rather than hiding the affordance with no
  explanation.

**Verification:** capability-composition unit tests (already exist — extend), widget
tests for the denied/fenced states. Hardware success paths fenced + documented.

### Track 3 — UX niche polish (widget-tested)

A focused pass on the highest-traffic surfaces (VOTE browse, poll detail, JOIN,
results, voting pass). For each candidate: identify the *real* gap (empty vs error vs
loading conflation, ambiguous copy, missing semantics/tap-target, dead-end navigation),
then fix with a backing widget test. No mechanical churn; YAGNI. Concrete candidates to
confirm during implementation: distinct empty-vs-error states on browse; loading
skeleton vs spinner consistency; `Semantics`/label coverage for icon-only buttons;
back-navigation dead-ends on full-screen routes.

**Verification:** `flutter test` per touched package; analyze.

### Track 4 — Android release readiness

Groundwork toward a shippable APK (no mainnet, no real signing secrets committed):
- Remove the boilerplate `applicationId`/signing TODOs; confirm `com.zkvote.tessera`.
- Document the release-signing strategy (keystore via env/CI secret; debug-signing is
  fine for internal artifacts, flagged as such).
- Permissions audit (only INTERNET + camera-via-merge + NFC-if-kept); no over-ask.
- Version strategy note (the shell is `0.3.0+1`).
- Icon/splash sanity (already generated from the brand mark).

**Verification:** APK build; `aapt dump badging` permission/label check; analyze.

## 3. Sequencing

Track 1 first (keystone, unblocks honest verification of the share story), then 2, 3, 4.
Each track is a focused commit; PR(s) carry critic-agent review before merge to `main`.
Primary tree stays on `main`; all work in the `feat/android-share-loop` worktree.

## 4. Verification matrix (the "can't test" honesty)

| Capability | How verified this round | Stays device-fenced |
|------------|------------------------|---------------------|
| Deep-link parse→route | unit/widget tests (existing + new) | — |
| Cold/warm link launch | emulator `adb am start tessera://…` | — |
| Release network reach | APK build + emulator run | — |
| WebView prover cleartext | network_security_config + emulator | real-phone prover (already a gate) |
| Camera QR | paste fallback tested; emulator has no camera | real-phone camera |
| NFC write/read | logic unit-tested if kept; else honestly disabled | real-phone NFC |
| BLE beacon | already honestly `false` | needs nonexistent peripheral plugin |

## 5. Out of scope

R5 sealing implementation, Sepolia/mainnet deploy, iOS, browse pagination, short-code
*resolver* (grammar ships; lookup stays the open question), App Links (`https://`) with
domain verification (no verified domain yet — custom scheme only this round).

## 6. Open decisions (resolved inline during implementation, logged in CHANGELOG)

1. NFC: implement writer vs honest-disable — lean honest-disable unless writer is trivial.
2. Whether to also register the `https` mirror intent-filter now (deferred: needs
   `assetlinks.json` on a verified host; custom scheme covers QR/NFC/in-app share today).
