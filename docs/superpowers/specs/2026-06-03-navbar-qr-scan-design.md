# Navbar QR scan — design

> **Goal:** surface QR scanning as a first-class, one-tap entry in the bottom
> navigation bar. Today the camera scanner is buried in the live-meeting voter
> flow (`qr_scan_sheet.dart`, scans the host's rotating ticket QR). Promote it to
> the navbar and make it route *any* recognized Tessera deep-link (live-vote
> ticket, verify receipt, poll link), with an always-reachable paste fallback.

## UI/UX research (2026-06-03)

- **Material 3 NavigationBar** allows **3–5 destinations** (5 is the max). A
  *FAB* represents a primary **action** and sits above the bar; nav items are
  *top-level destinations*. ([m3.material.io/components/navigation-bar](https://m3.material.io/components/navigation-bar/guidelines))
  - Orthodox Material would make "Scan" a FAB (it's an action, not a
    destination). We instead place it **in the navbar** (the product ask) as a
    5th item — still within the 3–5 limit — but treat its tap as an **action**
    (open the camera) rather than switching to a persistent tab. The icon
    (`qr_code_scanner`) signals "do something", not "go somewhere".
- **Scanner UX:** open straight to the scanner (zero-friction); request **only**
  the camera permission; give a **success cue** (haptic) on detect; provide an
  **always-reachable manual paste fallback** for when the camera is denied /
  unavailable; and don't act on opaque external payloads without recognition.
  ([UX of QR codes](https://medium.com/@dvprry/the-ux-of-qr-codes-and-scanning-stuff-with-our-phones-819721c3ccef),
  [html5-qrcode](https://github.com/mebjas/html5-qrcode))
- The existing `qr_scan_sheet.dart` already implements the capability gate
  (`cameraScanSupported`: mobile-only), the permission-denied / no-camera error
  state, and the "paste instead" messaging. We reuse it and add the missing
  pieces: a testable router, an in-flow paste dialog, and success haptics.

## Design

### Placement
A 5th `NavigationDestination` **SCAN** (`qr_code_scanner` icon) is appended to
the bar (POLLS / VERIFY / CREATE / IDENTITY / **SCAN**). Its tap is intercepted
in `AppShell`: instead of `shell.goBranch`, it calls `scanAndRoute(context)`.
The shell's `selectedIndex` stays on the current branch (0–3), so SCAN never
renders as a "selected tab" — it reads as an action.

### Scan → route
`routeForScannedValue(String raw) → String?` (pure, unit-tested) maps a scanned
payload to a `go_router` location:

| Scanned payload | Route |
|---|---|
| `tessera://live/<addr>/vote?t=<ticket>` | `/live/<addr>/vote?t=<ticket>` |
| `tessera://live/<addr>/host` | `/live/<addr>/host` |
| `tessera://verify?poll=<a>&nullifier=<n>` | `/verify?poll=<a>&nullifier=<n>` |
| `tessera://poll/<addr>?module=<m>` | `/poll/<addr>?module=<m>` |
| anything else | `null` → "Unrecognized QR/link" feedback |

`https?://…/<same paths>` is also accepted (future web shares). The host QR
already encodes `tessera://live/<addr>/vote?t=<wire>` (see
`live_host_view_model.dart`), so the primary path is covered on day one.

### Flow — `scanAndRoute(BuildContext)`
1. If `cameraScanSupported` → open the camera scan sheet (reused
   `showQrScanSheet`, now with a generic title + a "PASTE A LINK" affordance).
   On detect: light haptic, return the raw value.
2. If the camera isn't supported, or the user chose "paste" → open a paste
   dialog (`showPasteLinkDialog`) with a text field.
3. `routeForScannedValue(raw)` → `context.go(route)` on a match; otherwise a
   `SnackBar` "Couldn't read that as a Tessera link."

### Verified-or-fenced
- **Verified:** `routeForScannedValue` is fully unit-tested (every payload type +
  rejects), and the paste path is exercisable on every platform (web/desktop/
  emulator) with no camera. `flutter analyze` + `flutter test` gate it.
- **Fenced:** the live **camera** decode stays the known real-device follow-up
  (emulator virtual-camera QR injection is unreliable) — exactly the existing
  bound for `cameraScanSupported`. Paste is the verified fallback.

## Files
- `lib/ui/core/scan_router.dart` *(new)* — `routeForScannedValue` +
  `scanAndRoute` + `showPasteLinkDialog`.
- `lib/ui/features/live_vote/qr_scan_sheet.dart` — generalize: optional `title`/
  `hint` params + an `onPaste` affordance + a success haptic. Live-vote keeps its
  ticket-specific copy by passing the same strings.
- `lib/ui/core/app_shell.dart` — 5th SCAN destination + tap intercept.
- `test/ui/core/scan_router_test.dart` *(new)* — unit tests for every mapping.

## Out of scope
- Generating verify/poll QRs (only live tickets are generated today; the scanner
  is forward-compatible with them).
- Gallery-image scanning (camera + paste cover the cases; a later enhancement).
