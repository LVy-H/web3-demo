# NFC tap-to-open polls — design

**Date:** 2026-06-04
**Status:** approved (autonomous build; user asked for NFC/BLE)

## Problem / UX reasoning

The user asked for NFC/BLE. Reasoning about *where* a radio actually helps in
Tessera's journey (not just "add NFC"): every in-person moment today runs on
**QR** — share a poll (#84), scan to open (#76), live-meeting tickets — and there's
a `ProximityService` **seam** already built for radios but shipping as a no-op.

NFC's clearest, most universally-understood fit is **"tap to open a poll"**: a
poll's `tessera://poll/<addr>?module=<m>` link — the *same* payload the QR encodes
— written to an NFC tag. A venue/booth puts a tap-to-vote sticker; a voter taps
instead of aiming a camera. It **reuses** `shareLinkForPoll` (the payload) and the
existing `routeForScannedValue` (the read), so NFC is a faster *transport*, not a
new format.

*(BLE is a separate increment — it fills the `ProximityService` anti-remote
attestation seam, a background "✓ nearby" UX, not tap-to-share. Sequenced next.)*

*(Note: modern Android removed phone-to-phone Beam, so the clean, supported
pattern is NFC **tags**, not a phone-bump.)*

## Approach — capability-gated, exactly like `ProximityService`

### Seam (`nfc_service.dart`)
`NfcService`: `Future<bool> isAvailable()` (async — the platform check is), `Future<NfcWriteResult> writeUrl(url)`, `Future<void> cancel()`. `UnsupportedNfcService` is the no-op default — never throws, never blocks sharing.

### Web-safe factory (mirrors `proof_service_factory`)
`nfc_service_factory.dart` conditionally imports `nfc_service_stub.dart` (web → no-op) `if (dart.library.io)` `nfc_service_native.dart` (mobile/desktop). Native uses `dart:io` `Platform.isAndroid` → `AndroidNfcService` (`nfc_manager`), else no-op. **Keeps `nfc_manager` + `dart:io` out of the web compile** — verified by a green `flutter build web`.

### UI
Provided app-wide (`Provider<NfcService>`). The share sheet (#84) probes
`isAvailable()` on open and, only where a radio is present, shows a **WRITE TO NFC
TAG** button → `writeUrl(link)` with inline status ("Hold a tag…", "Written ✓",
or the error). Per the UX rule, the button never appears on a device without NFC;
the **QR stays the baseline**.

### Android
`uses-permission NFC` + `uses-feature nfc required="false"` (NFC-less devices stay
installable).

## Verification

- `flutter analyze` clean; `flutter test` green (300) — incl. a share-sheet test
  proving the NFC button appears only when a fake reports available and writes the
  **same** `tessera://` payload the QR encodes, and the `UnsupportedNfcService`
  no-op contract.
- `flutter build web` green — confirms the web compile is NFC-free (web-safe).
- `flutter build apk --debug` green — confirms `nfc_manager` + the manifest
  integrate on Android.

## Device-fenced (honest bound)

The **radio write itself** needs a real NFC phone + a writable tag — no
emulator/CI box has NFC — so the actual tap is verified on a device, exactly the
bar the on-device prover and `ProximityService` already sit behind. Everything
else (seam, web-safe factory, capability-gated UI, payload parity, the Android
build) is verified here.

## Out of scope (follow-ups)

- **NFC read-to-open** via an Android NDEF intent-filter (OS launches the app on a
  Tessera tag) — needs deep-link routing wiring.
- **BLE proximity** — the `ProximityService` anti-remote attestation impl.
