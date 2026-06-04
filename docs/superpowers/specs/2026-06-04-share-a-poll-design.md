# Share-a-poll — design

**Date:** 2026-06-04
**Status:** approved (autonomous build; approval gate waived per the 8-hour mandate — the write-it-down step is kept)

## Problem

The app can **scan** a Tessera deep-link (`scan_router.dart`, navbar SCAN, shipped
in #76) and route it — `tessera://poll/<addr>?module=<m>` opens the poll. But
nothing **generates** that link, so the scan loop is half-open: there's a reader
with no writer. To share a poll today a user would hand-copy the address and tell
the recipient which module it is. We close the loop: any poll can produce its own
QR + deep-link, scannable by the existing reader.

## Approach

A pure generator that is the exact inverse of `routeForScannedValue`, plus a small
themed bottom sheet to display it. No new dependency — `qr_flutter: ^4.1.0` is
already used by `live_host_screen.dart`.

### 1. Pure link generator (co-located with the parser)

In `lib/ui/core/scan_router.dart`, next to `routeForScannedValue` so the link
grammar and its inverse live in one file:

```dart
/// Build the canonical Tessera deep-link for a poll — the inverse of
/// [routeForScannedValue]. Round-trips: routeForScannedValue(shareLinkForPoll(a, m))
/// == '/poll/$a?module=$m'.
String shareLinkForPoll(String address, {String? module}) {
  final q = (module != null && module.isNotEmpty) ? '?module=$module' : '';
  return 'tessera://poll/$address$q';
}
```

### 2. Round-trip property test (the verifiable core)

In `test/ui/core/scan_router_test.dart` (extending the existing 13-case suite):
for every shipped module type **and** the no-module case, assert

    routeForScannedValue(shareLinkForPoll(addr, module: m)) == '/poll/$addr?module=$m'

This pins the invariant that a shared QR always scans back to the same poll. It is
fully headless (`flutter test`) — no device needed.

### 3. Share sheet (the visible feature)

`lib/ui/core/share_poll_sheet.dart` — `showSharePollSheet(context, {required
address, module, title})`, a themed modal bottom sheet (`Db.*` palette) that shows:

- a white-quiet-zone `QrImageView` of `shareLinkForPoll(address, module: module)`,
- the link as selectable monospace text,
- a **COPY LINK** button (`Clipboard.setData`, matching the existing
  commitment-copy idiom) with a "copied" snackbar.

Reusable from any screen. Stateless except the transient "copied" feedback.

### 4. Wiring

A **SHARE** affordance (an `Icons.ios_share` / `qr_code_2` `IconButton`) in the
`poll_detail_screen` app bar that calls `showSharePollSheet` with the poll's
address + module. Poll-detail is the canonical surface; other module screens can
adopt the same one-liner later (out of scope here to keep the diff tight).

### 5. Widget test

A widget test that pumps the sheet and finds the link text + a `QrImageView`,
confirming it builds and renders the right payload. Headless.

## Out of scope

- OS share-sheet (`share_plus`) — not a dependency; copy-to-clipboard + QR matches
  the existing pattern and needs no new permission.
- Adding the affordance to all six module cast screens — follow-up.
- Any device-only / WebView path.

## Verification

`flutter analyze` clean + `flutter test` green (the round-trip unit test + the
widget test). No device required.
