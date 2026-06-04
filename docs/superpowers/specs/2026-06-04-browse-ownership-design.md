# Browse-card ownership labels — design

**Date:** 2026-06-04
**Status:** approved (autonomous build)

## Problem / UX reasoning

The user's ownership feedback — *"the votes are all displayed, I don't know who
owns that"* — was experienced on the **browse list**, but #88 only fixed the poll
**detail** (RUN BY + the permissions explainer). On the list, each card still
shows `PollInfo.creator` as a raw short hex — and under the wallet-free model the
**relayer creates every sponsored poll**, so *every* card reads the same opaque
`0xF39F…2266`. That's precisely the "I can't tell what these are" feeling, at the
surface where the user actually scans the polls.

## Approach

Reuse the `pollOwner` helper (#88) on the card, rendering a **short** tag suited
to a dense list:

- `relayer-owned` → **SPONSORED**
- `your signer` → **YOU**
- otherwise → the creator's short address (a specific person)

`BrowseScreen` probes `RelayClient.getRelayerInfo()` once on open for the relayer
address (down → cards fall back to the short address — safe degradation), and
reads `ChainWriter.signerAddress` for the "you" case. Both are passed to
`_PollCard`; the card label `"$creator · OPENED RECENTLY"` becomes
`"$ownerLabel · OPENED RECENTLY"`.

No new model field, no view-model change (the probe lives in the screen state,
mirroring the detail screen).

## Verification (headless)

- `flutter analyze` clean; `flutter test` green — a new widget test pumps a
  relayer-owned poll (creator == the mocked `/info` relayer) and asserts the card
  reads **SPONSORED**, not the raw hex. `RelayClient` + `ChainWriter` providers
  added to the browse test harnesses (a relayer-503 default keeps the existing
  tests' cards on the short-address fallback, so their assertions are unchanged).

## Out of scope (next)

- A "Mine" filter / local created+voted tracking (a personal activity view) —
  the meatier follow-on, building on this label + a local store.
