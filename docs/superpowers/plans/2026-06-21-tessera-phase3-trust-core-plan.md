# Tessera Phase 3 — Trust core (verifiable + secret ballots)

> **Design source:** `../specs/2026-06-19-tessera-system-design.md` — §6 (threat model), §11 (verification protocol), §12.1 (anchor), §12.2 (credentials).
> **Branch:** `redesign/phase3-trust` (stacked on `redesign/phase2-server`).
> **Goal:** make the published result **checkable without trusting the host** (the differentiator) — and add **secret ballots**. Built as parallel worktree modules merged back.

## What Phase 3 adds (on top of Phase 2's open-ballot server)
1. **Merkle log (RFC 6962)** — replace/augment the simple hash-chain head with a domain-separated Merkle tree so a verifier gets real **inclusion proofs**; receipts commit to the Merkle root.
2. **Checkpoints + anchor (broadcast, zero-wallet)** — the server signs interim/final checkpoint roots; the final **signed root is distributed** (the broadcast anchor). `/anchor` serves it; a chain adapter is a stubbed seam.
3. **Independent verifier** — recompute tally **+ verdict**, recompute the **Merkle root over the served ballots and assert it equals the anchored root** (§11.5 binding), check inclusion proofs + no duplicate serials. Exposed as a self-contained module (usable as a CLI / served verify page) so anyone can run it.
4. **Secret ballots — blind-signature credentials (RFC 9474 RSABSSA-PSS)** — per-decision issuer keypair; `POST /register` issues a blind-signed credential; secret-mode cast presents `(serial, sig)`; pubkey hash ∈ `setupCommitment`; registration-closes-before-voting (§6/§11.0).

## Honest-scope guardrails (do NOT overclaim — §6)
- Secret mode protects against participants/observers/forensics, **not a live malicious host** (single-party metadata correlation). That stays the post-1.0 "strong mode."
- Roster-stuffing within the host's roster budget remains host-trusted; the verifier is a detection aid, not a proof against the host on eligibility.

## Module decomposition (parallel; disjoint dirs under `codes/server/src`)

### Module M — `src/merkle/` (pure; no deps) — INDEPENDENT, fan out now
RFC 6962 domain-separated hashing (leaf prefix `0x00`, node prefix `0x01`, SHA-256).
```ts
export function merkleRoot(leaves: Buffer[] | string[]): string
export function inclusionProof(leaves, index): { index, audit: string[] }
export function verifyInclusion(leafHash: string, index: number, audit: string[], root: string, treeSize: number): boolean
```
TDD: RFC 6962 known vectors (empty, 1, n leaves); inclusion proof round-trips for every index; tamper → false.

### Module C — `src/credentials/` (blind-sig) — INDEPENDENT, fan out now
RFC 9474 **RSABSSA-PSS** blind signatures. **Use a vetted library** (`@cloudflare/blindrsa-ts`) — do NOT hand-roll the blinding math.
```ts
export function newIssuer(): { publicKeyJwk; privateKeyPem; pubKeyHash }   // per-decision keypair
export function blindSign(privateKey, blindedMsg): Buffer                  // server side
export function verifyCredential(publicKey, message, signature): boolean   // at cast
// + client-side helpers (blind/finalize) for tests + the future client
```
TDD: full blind→sign→unblind→verify round-trip; wrong message/sig → false; pubKeyHash stable.

### Module A — `src/anchor/` (after M) — checkpoints + broadcast anchor
Build interim/final checkpoints over the Merkle root; sign each with the Ed25519 server key (Phase-2 `crypto`); `broadcast` mode distributes the final signed root; `casual` mode = no signed distribution; `chain` is a stubbed adapter. Persist checkpoints (new migration). `/anchor` returns `{mode, root, signedRoot, status}`.

### Module V — `src/verifier/` (after M + A) — the independent checker
Pure recompute: tally+verdict (reuse `src/tally`), Merkle root over served ballots == anchored root, inclusion proof per receipt, no duplicate serials, `setupCommitment` matches. Expose `verifyDecision(bundle): VerifierReport`. Add a `verify` npm script (CLI) + a `GET /verify/:id` convenience that returns the report (non-authoritative; the point is anyone can run the module themselves).

### Integration (after modules) — routes + db + secret-mode cast
`POST /register` (issuer), secret-mode `POST /ballots` (credential-gated, serial uniqueness), `/root` → Merkle root, receipts → Merkle inclusion, `/anchor` → signed checkpoint, `setupCommitment` includes `issuerPubKeyHash`. New db tables: `signing_keys`, `issued_credentials`, `checkpoints`.

## Exit
An independent run of `src/verifier` validates a published decision (open AND secret) against the broadcast anchor without trusting the server — §11 protocol holds; honest-claims (§6/§13) unchanged.

## Sequencing
Wave 1 (parallel, now): **M (merkle)**, **C (credentials)** — pure/independent.
Wave 2: **A (anchor)** [needs M], **V (verifier)** [needs M, tally].
Wave 3: route/db integration + secret-mode cast + the §11 e2e + the verifier CLI.
