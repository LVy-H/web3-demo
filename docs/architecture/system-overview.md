# System Architecture Overview

> **Rewritten 2026-06-19** to match the ground-up redesign. The previous version
> (EVM/Solidity registry + 6 ZK voting modules + Semaphore Groth16 verifier + Express
> relayer) is **retired** and preserved in git history. **Canonical source of truth:**
> [`docs/superpowers/specs/2026-06-19-tessera-system-design.md`](../superpowers/specs/2026-06-19-tessera-system-design.md).
> This file is the orientation map; the design doc has the detail, threat model, and
> honest-claims analysis.

## One paragraph

Tessera lets a group make a decision everyone can trust, and lets anyone check the result
is honest **without trusting whoever ran it**. It is **open-source software a community
self-hosts**. A community runs one **server** that holds an **append-only ballot log**; the
log's checkpoints are pinned to a **public, host-independent anchor** (a signed-root
broadcast by default; a public L2 chain as the equivocation-resistant upgrade). Secret
ballots use **blind-signature credentials** (no ZK, no chain for voting). Anyone can
recompute the tally from the published ballots and confirm it matches the anchored record.
It is **not** a blockchain app and **not** trustless — it spends a bounded trust in the
organiser (for integrity) to buy enormous simplicity, and backs that trust with public
verifiability.

## Components

```
        ┌──────────────────────────────────────────────┐
        │  PUBLIC ANCHOR  (default: signed-root broadcast;│  host-independent,
        │  upgrade: an L2 chain)  — setupCommitment + roots│  tamper-evident
        └───────────────▲──────────────────────▲─────────┘
                        │ post roots           │ read roots (anyone, free)
   ┌────────────────────┴─────────┐   ┌─────────┴────────────────┐
   │  TESSERA SERVER (self-host)  │   │   VERIFIER (anyone)      │
   │  • decision lifecycle + auth │   │  • recompute tally+verdict
   │  • eligibility + per-decision│   │  • Merkle root == anchor │
   │    blind-sign issuer         │   │  • serials / inclusion   │
   │  • append-only log + running │   │  • read trust level (V5) │
   │    hash-chained checkpoints  │   └─────────▲────────────────┘
   │  • Merkle roots + receipts   │             │ published ballots (read-only)
   └───▲──────────────▲───────────┘             │
       │ join / cast  │ serve app + proofs ─────┘
   ┌───┴──────────────────────────┐
   │  CLIENT (Flutter, web-first) │  Participant / Convener / Verifier UI
   └──────────────────────────────┘
```

- **Server** (self-hosted, one command, SQLite default): decision lifecycle
  (`draft→registration→open→closed→challenge→published`/`cancelled`), convener auth,
  eligibility (open/invite/passcode/domain), per-decision blind-signature credential issuer,
  the append-only ballot log, running hash-chained checkpoints + Merkle roots, the anchor
  adapter, and it serves the client + the public read API. No hard dependency on any
  Tessera-authors-run service.
- **Anchor** (pluggable): `broadcast` (default, zero-wallet — the signed final root is
  distributed to voters), `chain` (an L2 for host-independent non-equivocation, needs a
  funded wallet), `casual` (host-attested only, branded unverifiable). Trust level is always
  disclosed to verifiers (V5).
- **Client** (one Flutter codebase, web-first): voter (join→cast→verify), convener
  (create→run→close→publish→share), verifier UI. The voter path carries a hard web-payload
  budget (CI-gated; thin web shell as the pre-planned fallback).
- **Verifier** (anyone — a client tab, a static page, or a CLI): recomputes the tally **and
  the decision verdict** from the published ballots, recomputes the Merkle root and binds it
  to the anchored root, checks credential serials + inclusion. Needs only public reads + the
  anchor.

## Trust model (summary — full version in the design doc §6)

| Holds even against a malicious host | Rests on host honesty (named limits) | Out of scope |
|---|---|---|
| tally correctness (recompute) | eligibility / ballot-stuffing (host defines the roster; audited via published/challengeable rosters) | coercion-resistance |
| ballot-set tamper-evidence after acknowledgement (hash-chained receipts + anchored roots) | secret-ballot privacy vs a *live* malicious host (metadata correlation — single-party) | anonymity vs global chain validators |
| setup immutability (anchored commitment) | censorship-by-silence (receipt-withholding) | nation-state availability |

The stronger guarantees (privacy even against the host) are the **post-1.0 "strong mode"**:
separate registrar ⊥ ballot box (Belenios-style), and/or the parked Semaphore ZK credential.

## Voting methods

Pick-one · approve-any · ranked (IRV) · quadratic (credit split) · multi-question survey,
plus abstain/none-of-the-above. Tally is **pure off-chain code** (the `core_domain/voting/`
logic, recomputable by any verifier from the published ballots) — there is no on-chain tally
and no per-vote transaction.

## What this replaced

Retired in the 2026-06-19 redesign: the `PollRegistry` EIP-1167 factory, the six
`Zk*Voting` module contracts, `ZkAirdrop`, the Mock/real Groth16 `SemaphoreVerifier`, the
three Semaphore provers + SNARK artifacts, and the Express relayer. Rationale and the
foundation-by-foundation verdict are in the design doc §8/§17.
