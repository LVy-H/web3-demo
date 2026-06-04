# "MINE" filter — polls you created — design

**Date:** 2026-06-04
**Status:** approved (autonomous build)

## Problem / UX reasoning

The ownership thread (#88 detail, #91 browse cards) made *who runs* a poll clear.
The natural next question a user has is *"which of these are mine?"* — but under
the wallet-free model the relayer is the on-chain `creator` of every sponsored
poll, so **"polls I made" cannot be derived from the chain**. It needs a local
record, written when this device successfully creates a poll.

## Approach

### `CreatedPollsStore` (mirrors `IdentityStore`)
A capability with `all()` / `add(address)`, backed by `flutter_secure_storage`
(a JSON address list, lowercased) in prod and `InMemoryCreatedPollsStore` for
tests. Not secret, but it rides the existing secure store to avoid adding a prefs
dependency.

### Record on create
`create_screen._afterSponsored` (the wallet-free create success path) records the
new poll address before navigating. Provided app-wide.

### "MINE" browse filter
A new `_Status.mine` + a **MINE** pill in the status strip. When selected,
`_filterSort` keeps only polls whose address is in the locally-stored created set
(loaded on open and re-read when MINE is tapped, so a just-created poll appears).
Combines with the search/category filters; the existing empty state covers "you
haven't created any yet."

## Verification (headless)

- `flutter analyze` clean; `flutter test` green — `CreatedPollsStore` contract
  (add/all, lowercase, dedup, copy-on-read) + a browse widget test (a device that
  created only poll `_b` sees just that poll under MINE). `CreatedPollsStore`
  providers added to the browse test harnesses.

## Out of scope (next)

- Tracking polls you **voted in** (a second "kind") — spread across the per-module
  vote view-models; a follow-on.
- A MINE-specific empty state ("You haven't created any polls yet").
