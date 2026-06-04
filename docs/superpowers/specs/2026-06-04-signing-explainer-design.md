# "How signing works" explainer + truthful Settings signer status — design

**Date:** 2026-06-04
**Status:** approved (autonomous build; approval gate waived per the 8-hour mandate — write-it-down kept)

## Problem

The user's single biggest pain point: *"the wallet connection… so UI/UX unfriendly
and not productionable."* Tessera now has a **wallet-free** primary path (the
sponsored relayer creates polls, self-registers voters, and relays votes — #79,
#81, and the live-verifier proof). But two UI surfaces still imply a wallet is
required:

1. **Settings → SIGNING & PROVING** shows the signer as `"wallet (connect to
   sign)"` whenever there's no local dev-signer — ignoring the sponsored relayer
   entirely. It tells the user they need a wallet when they don't.
2. There is **no single place** that explains the signing model. The create
   screen has a good 3-state banner, but a user elsewhere has nowhere to learn
   "you don't need a wallet."

## Approach

Make Settings tell the truth, and add one reusable explainer.

### 1. Truthful signer status (Settings)

Probe the relayer once on open (`RelayClient.getRelayerInfo()`, the same probe
`create_screen` uses — `RelayClient` is an app-wide provider). Resolve the signer
row to the *active* path, in priority order:

- dev-signer present (`ChainWriter.canSign`) → `dev signer · 0x…`
- else sponsored relayer reachable (`info.registry != null`) → `wallet-free
  (sponsored relayer)`
- else → `wallet (connect to sign)` (the honest fallback when nothing else is up)

While the probe is in flight, show `…` (it already shows `…` for version).

### 2. "How signing works" explainer

`lib/ui/core/signing_explainer.dart` — `showSigningExplainerSheet(context)`, a
themed scroll-safe bottom sheet that leads with **"You don't need a wallet."** and
lists the three paths with one line each:

- **Wallet-free (sponsored relayer)** — *default.* A relayer pays gas and submits
  for you; your vote is still your own anonymous ZK proof. Nothing to install.
- **Local dev-signer** — a `DEV_PRIVATE_KEY` for local development only; never
  shipped.
- **Connect a wallet** — optional, advanced; device-only.

Surfaced from a `_linkRow('How signing works', …)` in the Settings SIGNING &
PROVING section. Reusable, so the create screen / vote flow can link it later.

## Out of scope

- Changing the actual signing logic or the create-screen banner (already correct).
- Wallet onboarding redesign.

## Verification

- `flutter analyze` clean.
- Widget test: the explainer sheet renders the "You don't need a wallet" lead and
  all three path headings. Headless — no device.
- The Settings probe degrades safely (relayer down → honest wallet fallback); the
  signer-resolution helper is a pure function, unit-testable.
