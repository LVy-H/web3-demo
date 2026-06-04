# BLE proximity attestation for live meetings — design

**Date:** 2026-06-04
**Status:** approved (autonomous build; user asked for NFC/BLE — this is the BLE half)

## Problem / UX reasoning

The live-meeting flow registers in-person voters: scan the organizer's ticket →
mint an ephemeral identity → show a 4-digit code → organizer confirms
face-to-face → on-chain register → vote. The code proves *a* person is present,
but a remote attacker holding a leaked ticket could still relay a code.

`ProximityService` is a **built-but-no-op seam** (`supported` + `attest(orgBeacon)`)
designed exactly for this — prove the voter's device is physically near the
organizer via a short-range radio. BLE's fit is the *voter* scanning for the
organizer's beacon while pending: a background **"✓ in the room"** signal that
*adds trust* without ever gating the baseline face-to-face code.

## Approach — same pattern as NFC + the existing seam

### Web-safe seam (refactor)
`proximity_service.dart` previously imported `dart:io` directly (fine while
unwired, but it would break the web build once consumed). Refactored to the
conditional-import factory (mirrors `proof_service_factory` / `nfc_service`):
`proximity_service_factory.dart` pulls `proximity_service_stub.dart` (web → no-op)
`if (dart.library.io)` `proximity_service_native.dart` (mobile/desktop) — keeping
`flutter_blue_plus` + `dart:io` **out of the web compile**.

### `bleBeaconUuid(pollAddress)` — pure, unit-tested
Both sides derive the same 128-bit beacon UUID from the public poll address (first
128 bits, formatted 8-4-4-4-12), so there's **no extra handshake** — the org
advertises it, the voter scans for it.

### Android scan (`AndroidProximityService`, flutter_blue_plus)
`attest(uuid)`: check `isSupported` + adapter on → `startScan(withServices:
[Guid(uuid)], timeout: 6s)` → if a result advertises the beacon at a usable RSSI
(> −85 dBm), `verified: true, method: 'ble'`; otherwise `none`. Every failure
resolves to `none` — never throws, never blocks voting.

### Live-vote wiring
`LiveVoteViewModel` takes a `ProximityService` (default `UnsupportedProximityService`,
so existing callers/tests are unaffected). On entering the **pending** stage it
fires `_attestProximity()` (fire-and-forget): `proximityChecking` → scan →
`proximityNearby`. The screen shows a **silent** chip — nothing unless a radio is
checking ("Checking you're in the room…") or confirmed ("✓ Verified in the room
(BLE)"). Provided app-wide; `BLUETOOTH_SCAN` (`neverForLocation`) in the manifest,
optional (`required=false`).

## Verification

- `flutter analyze` clean; `flutter test` green — incl. `bleBeaconUuid` (format /
  determinism / padding) + the `UnsupportedProximityService` no-op contract +
  the factory no-op on the VM host. The default-no-op keeps the existing
  live-vote tests green.
- Web-safety follows the same conditional-import pattern verified for NFC + the
  prover; CI's `flutter build web` confirms.

## Device-fenced + honest gap

The BLE scan + RSSI need a real radio — no emulator/CI has BLE — so the radio is
verified on a device (the bar the on-device prover already sits behind). And
**`flutter_blue_plus` is scan/central-only**: the organizer *advertising* the
beacon needs a physical BLE beacon broadcasting the service UUID, or a
peripheral-mode plugin — a documented follow-up. The seam, web-safe factory,
beacon-id derivation, capability-gated wiring, and UI are the verified parts.
