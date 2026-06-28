# Roadmap

> **Reset 2026-06-19.** The previous Phase 0–14 roadmap (on-chain + Semaphore-ZK +
> relayer) is **retired** — it grew organically and no longer matches the product. This
> roadmap is derived from the ground-up rethink in
> [`docs/superpowers/specs/2026-06-19-tessera-system-design.md`](../superpowers/specs/2026-06-19-tessera-system-design.md)
> (read it first — it defines the core job, threat model, and the lean-hybrid
> architecture this plan builds). The old phases are preserved in git history and
> `CHANGELOG.md`.

## What changed and why

A four-lens adversarial review confirmed the product's value is **trust, not scale**, and
that the heavy stack (smart-contract chain, Groth16 ZK, relayer) solved a problem the
chosen threat model — *trust the organiser for integrity, prove the count to everyone* —
doesn't have. The new architecture is a **self-hosted verifiable bulletin board**: an
append-only ballot log + blind-signature credentials + a public commitment anchor
(broadcast by default, a public chain as the equivocation-resistant upgrade). See the
design doc §8/§13/§16.

**Kept** from the prior build: the Dark Bauhaus design system, the `core_domain` journey
state machines + off-chain tally logic (IRV/quadratic/survey), `core_storage`, the
voting-method UI screens, and the join-code grammar. **Dropped:** Semaphore/Groth16, the
3 provers, the relayer, the 6 voting contracts + registry + on-chain verifier, and the
dev-signer/wallet onboarding. (Inventory: see the implementation plan.)

## Status legend

**DONE** · **IN PROGRESS** · **NEXT** · **PLANNED** · **POST-1.0**

---

## Phase 0 — Design & decision reset — **DONE (2026-06-19)**
- System design doc written and hardened against adversarial review (security / systems /
  product / red-team). Core job, threat model, requirements (incl. the product FRs the
  review surfaced), data model, API, verification protocol, honest-claims, 1.0-vs-post-1.0
  scope all settled.
- Repo cleanup: main synced, worktree/branch sprawl pruned, artifacts cleared.

## Phase 1 — Dismantle & extract — **NEXT**
> Make the workspace match the new architecture before building. Mostly deletion + a clean
> seam where the old chain/relay/crypto ports were.
- Delete the ZK proving stack (`core_crypto/proof/*`, the 4.7 MB SNARK artifacts, 3
  provers), the relayer (`codes/relayer/`), the contracts (`codes/contracts/` — 6 modules,
  registry, verifiers, airdrop, hardhat/deploy/typechain), and the client's `ChainWriter`
  + dev-signer + port adapters (`*_port_adapter.dart`, `relay_*_port.dart`).
- Keep & quarantine behind interfaces: `design_system`, `core_domain` (journeys + `voting/`
  tally), `core_storage`, the `feature_*` UI screens + ballot widgets + `ballot_encoding`,
  `join_grammar`. Keep the `core_relay` HTTP-client *shape* and the relayer's
  Express/Vitest *scaffolding* as the new server's starting point.
- Park the Semaphore ZK code (don't delete the option — it's the post-1.0 "strong mode").
- **Exit:** workspace compiles with old backends stubbed out; CI green on the kept packages;
  no Solidity/ZK/relayer left on the critical path.

## Phase 2 — The server — **PLANNED**
> The self-hostable core: a single service with an append-only log.
- Append-only ballot log (SQLite, WAL, single-writer, idempotent casts — design §12.6).
- Decision lifecycle (`draft→registration→open→closed→challenge→published`/`cancelled`),
  convener auth (bootstrap admin token + per-convener tokens), the REST API (§10) with a
  signed error model.
- Eligibility methods (open / invite / passcode / domain) + abuse controls.
- **Exit:** a convener can create→open→close→publish an **open-ballot** decision end-to-end;
  a voter casts and gets a self-contained receipt; one-command (broadcast-mode) deploy works.

## Phase 3 — Trust core: credentials, checkpoints, anchor, verifier — **PLANNED**
> The part that makes the result *checkable without trusting the host*.
- Secret-ballot **blind-signature credentials** (per-decision RSABSSA-PSS, pubkey committed
  in `setupCommitment`; registration-closes-before-voting).
- Running **hash-chained checkpoints** + Merkle log (RFC 6962-style) + receipts that sign
  the running root.
- **Anchor adapter**: broadcast (default, zero-wallet) + public-chain (upgrade) with tx
  status/finality handling + trust-level disclosure (V5).
- **Public verifier**: recompute tally **and verdict** from published ballots, recompute the
  Merkle root and bind it to the anchored root, check serials/inclusion. Challenge window.
- **Exit:** an independent party verifies a **secret-ballot** decision against the anchor
  without trusting the server; the verification protocol (§11) holds end-to-end.

## Phase 4 — Client rewire & web-payload gate — **PLANNED**
- Swap the journey ports from chain/relay/crypto to **server HTTP**; reuse the screens.
- Self-contained receipts; trust-level (V5) in the UI; returning-voter / shared-device
  states (P7).
- **N4 web-payload spike → CI gate** on the voter path (≤~1 MB, ≤~3 s cold load on throttled
  4G). If Flutter web misses, adopt the **pre-planned thin web voter shell** (design §12.4).
- **Exit:** the full voter + convener + verifier flows work in the client against the server;
  the voter-path payload budget is a green CI gate (or the shell fallback is in place).

## Phase 5 — Product completeness — **PLANNED**
> The FRs the review proved are first-hour-of-real-use needs, not polish.
- Decision **result semantics**: pass threshold / quorum / tie-break → published verdict
  (carried/failed/tie/quorum-not-met), recomputed by the verifier.
- **Notifications/reminders** (opt-in channel; "closing soon" / "now open").
- Lifecycle **edit / cancel / extend**; **abstain / none-of-the-above**; **result
  share/export** (link/QR, CSV, PDF for minutes).
- **Accessibility** pass to WCAG 2.1 AA on the voter path; strings externalised (i18n-ready).
- **Exit:** a real club / student-org / board can run a decision end-to-end and come back to
  it, with an accessible voter path.

## Phase 6 — 1.0 hardening & release — **PLANNED**
- Security review of the verification protocol + credential handling; durability/crash
  tests; rate-limit/abuse hardening; one-command self-host packaging + ops docs (TLS,
  backups of the `data/` volume incl. keys, the optional funded-wallet anchor path).
- Truth-up all docs; cut **1.0**.
- **Exit (1.0 bar):** verification protocol holds; voter path WCAG-AA + within payload
  budget; one-command self-host (broadcast default); honest claims (§13) match reality.

---

## Post-1.0 (named, not vague — design §16)

- **Strong mode / privacy against the host** — separate **registrar ⊥ ballot box**
  (Belenios-style "either-party-honest"), and/or the **parked Semaphore ZK** membership
  credential for permissionless, host-independent anonymity. *This is the answer to the
  review's deepest finding; it's an upgrade, not a 1.0 gate.*
- **Witnessed-log anchor** — no-wallet non-equivocation (better than broadcast mode).
- **Proxy / delegate voting** (HOA bylaw need), **multi-question ballots**, **full i18n**,
  **native apps** beyond web.

## Out of scope (explicit)
- Coercion-resistance / receipt-freeness (MACI-class) — a separate "formal election" product.
- On-chain voting / global-validator anonymity — the chain is a notary only.
- DAO governance over the deployment; cross-instance federation.

## How to update this file
- Phase status changes happen here. When a phase ships, mark it DONE with the outcome and
  move the active marker. Don't accumulate history here — that's `CHANGELOG.md`.
- Architecture decisions belong in the design doc; this file tracks *sequencing*.
