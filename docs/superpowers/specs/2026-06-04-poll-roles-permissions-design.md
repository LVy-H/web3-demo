# Poll ownership + permissions clarity — design

**Date:** 2026-06-04
**Status:** approved (autonomous build; approval gate waived per the 8-hour mandate — write-it-down kept)

## Problem

User feedback: *"The votes are all displayed — I don't even know who owns that
and what permission everyone has."*

Two real gaps, both rooted in the wallet-free model:

1. **Ownership is opaque.** Under sponsored (wallet-free) creation the **relayer
   owns every poll**, so the poll-detail "OWNER" row shows the same relayer
   address (`0xf39Fd6…`) on every poll — a raw hex string that means nothing to a
   user. There's no signal for "this is sponsored/community-run" vs "a specific
   person created this" vs "I created this".
2. **The permission model is never explained.** Who runs a poll, who may vote,
   and — crucially in a ZK app — the fact that **nobody can see who voted for
   what**, are nowhere stated. A user can reasonably wonder whether their vote is
   visible, or who controls the poll.

## Approach

A small pure helper to label ownership meaningfully, plus a reusable explainer
sheet (same pattern as `signing_explainer`) — both surfaced on the poll detail.

### 1. `pollOwner` — pure label helper (`lib/ui/core/poll_roles.dart`)

```dart
enum PollOwnerKind { sponsored, you, other }
class PollOwner { final PollOwnerKind kind; final String label; final String address; }

PollOwner pollOwner({required String owner, String? relayerAddress, String? myAddress});
```

- `owner == relayerAddress` (case-insensitive) → **sponsored**, label "Sponsored ·
  relayer-run".
- `owner == myAddress` → **you**, label "You".
- otherwise → **other**, label = `shortAddr(owner)` (a specific creator).

Pure → unit-tested across all three kinds + case-insensitivity + null inputs.

### 2. `showPermissionsExplainerSheet` (`lib/ui/core/permissions_explainer.dart`)

A themed bottom sheet — **"WHO CAN DO WHAT"** — that explains:

- **Owner / runner** — invites voters and opens/closes voting. For a *sponsored*
  poll, that's the Tessera relayer running it on everyone's behalf (no single
  person owns it).
- **Voters** — invited members (registered identities). Each casts exactly **one**
  vote.
- **Anonymity** — votes are zero-knowledge proofs: **nobody — not even the owner —
  can see who voted for what.** Only the tallies are public. (This is the robust
  answer to "who voted": you can't, by design — and neither can anyone else.)
- **You** — your role on *this* poll, when known: registered → "you can vote
  anonymously"; not registered → "join to vote".

Takes the `PollOwnerKind` + optional `isRegistered` so the owner/you lines match
the poll in front of the user. Static otherwise → widget-testable.

### 3. Poll-detail wiring

- The vote view-model probes `RelayClient.getRelayerInfo()` in `load()` and exposes
  `relayerAddress` (null if the relayer is down → ownership falls back to the raw
  short address; safe degradation).
- The detail screen replaces the bare **OWNER** row with a **RUN BY** row showing
  `pollOwner(...).label` (relayer address from the vm, my address from
  `ChainWriter.signerAddress`), followed by a **"Who can do what"** link that opens
  the explainer with this poll's owner-kind + `vm.isRegistered`.

## Out of scope

- Browse-card ownership badges — the same `pollOwner` helper makes this a one-liner
  follow-up; deferred to keep this diff focused on the detail surface.
- De-anonymizing voters — impossible by design; the explainer states why.

## Verification (headless)

- `flutter analyze` clean; `flutter test` green.
- Unit test: `pollOwner` for sponsored / you / other + case-insensitivity + nulls.
- Widget test: the explainer renders the four sections incl. the anonymity line;
  the sponsored owner-kind shows the relayer-run wording.
