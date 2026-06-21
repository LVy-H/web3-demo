/**
 * Tessera independent verifier (§11) — recompute everything from public data
 * and bind it to the anchored Merkle root.
 *
 * This is the differentiator: a participant (or anyone) takes the public
 * bundle the server serves — decision metadata, the ballot set, the signed
 * checkpoint root — and re-derives the published result *without trusting the
 * host*. The verifier shares NO state with the server: it only reuses the same
 * pure primitives (`../crypto`, `../merkle`, `../tally`) that the spec pins, so
 * a faithful server and an independent verifier necessarily agree, and a
 * tampered bundle necessarily fails a check.
 *
 * Six checks, one per §11 step:
 *   1. setup          — setupCommitment binds the decision's rules (§11.1)
 *   2. leaves         — every ballotHash is the public leaf of its ballot (§11.2)
 *   3. root-binding   — Merkle(ballots) == anchor.root AND signedRoot verifies (§11.5)
 *   4. contiguity     — logSeq is 0..n-1, no gaps/dupes, treeSize == n (§11.3)
 *   5. no-double-vote — no duplicate serial among secret-mode ballots (§6/§11.0)
 *   6. tally-verdict  — recomputed tally+verdict match the published result (§11.4)
 *
 * NEVER throws on a bad/tampered bundle: any structural defect becomes a FAILED
 * check, never a crash. `report.ok` is the AND of all six.
 *
 * PINNED public recipes (the integration emits exactly these — see the plan):
 *   ballotHash = sha256hex('tessera:leaf:v1\n' + canonicalize(
 *                  { decisionId, logSeq, payload, serial: serial ?? null }))
 *   signedRoot = serverSign(canonicalize({ root, treeSize, decisionId }))
 *
 * Pure module: depends only on `../crypto`, `../merkle`, `../tally`. No db/io.
 */

import { canonicalize, sha256hex, computeSetupCommitment, verifySig } from "../crypto";
import { merkleRoot } from "../merkle";
import { tally, verdict, type BallotPayload, type Rule, type Tally, type Verdict } from "../tally";

/** Domain-separation prefix for the public, recomputable ballot leaf. */
export const LEAF_DOMAIN = "tessera:leaf:v1\n";

/** A single ballot as served in the public log (everything here is public). */
export interface BundleBallot {
  logSeq: number;
  payload: BallotPayload;
  /** Secret-mode credential serial; `null` in open mode. */
  serial: string | null;
  /** The server-served leaf hash; the verifier recomputes and asserts it. */
  ballotHash: string;
}

/** The anchored, server-signed checkpoint over the final Merkle root. */
export interface BundleAnchor {
  root: string;
  treeSize: number;
  /** base64 Ed25519 signature over canonicalize({root,treeSize,decisionId}). */
  signedRoot: string;
}

/** The decision metadata a verifier needs to recompute the setupCommitment. */
export interface BundleDecision {
  id: string;
  title: string;
  options: string[];
  method: Tally["method"];
  ballotMode: "open" | "secret";
  resultsPolicy: "sealed" | "live";
  rule: Rule;
  schedule: unknown;
  visibility: unknown;
  anchorMode: unknown;
  rosterCommitment: unknown;
  issuerPubKeyHash: string | null;
}

/** The full self-contained bundle handed to an independent verifier. */
export interface VerifierBundle {
  decision: BundleDecision;
  setupCommitment: string;
  /** SPKI PEM of the server's Ed25519 key (advertised to verifiers). */
  serverPubKeyPem: string;
  ballots: BundleBallot[];
  anchor: BundleAnchor;
  /** The result the server published; if present it is asserted to match. */
  publishedResult?: { tally: Tally; verdict: Verdict };
}

/** One verification step's outcome. */
export interface Check {
  name: string;
  ok: boolean;
  detail: string;
}

/** The verifier's full, self-contained report (never partial — always 6 checks). */
export interface VerifierReport {
  /** AND of every check. */
  ok: boolean;
  decisionId: string;
  checks: Check[];
  /** The verifier's OWN recomputed tally (honest, regardless of publishedResult). */
  tally: Tally;
  /** The verifier's OWN recomputed verdict. */
  verdict: Verdict;
}

const CHECK_ORDER = [
  "setup",
  "leaves",
  "root-binding",
  "contiguity",
  "no-double-vote",
  "tally-verdict",
] as const;

/** Recompute the public ballot leaf from its (entirely public) inputs. */
export function recomputeBallotHash(decisionId: string, b: {
  logSeq: number;
  payload: BallotPayload;
  serial: string | null;
}): string {
  return sha256hex(
    LEAF_DOMAIN +
      canonicalize({
        decisionId,
        logSeq: b.logSeq,
        payload: b.payload,
        serial: b.serial ?? null,
      }),
  );
}

/** Canonical preimage the server signs for the anchor (§12.1). */
export function signedRootPreimage(root: string, treeSize: number, decisionId: string): string {
  return canonicalize({ root, treeSize, decisionId });
}

/**
 * Run a single check, converting any thrown error into a failed check so a
 * malformed/tampered bundle is reported, never crashed-on (§13 honest-claims:
 * a verifier that throws on bad input proves nothing).
 */
function guard(name: string, fn: () => { ok: boolean; detail: string }): Check {
  try {
    const { ok, detail } = fn();
    return { name, ok, detail };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return { name, ok: false, detail: `check threw (treated as failure): ${msg}` };
  }
}

/**
 * Independently verify a published decision against its broadcast anchor.
 *
 * Recomputes the setupCommitment, every ballot leaf, the Merkle root, the
 * signed-root signature, log contiguity, serial uniqueness, and the tally +
 * verdict — and binds them all to the anchored root. Never throws.
 */
export function verifyDecision(bundle: VerifierBundle): VerifierReport {
  const decisionId =
    (bundle && bundle.decision && typeof bundle.decision.id === "string"
      ? bundle.decision.id
      : "") ?? "";

  const ballots: BundleBallot[] = Array.isArray(bundle?.ballots) ? bundle.ballots : [];

  // The verifier's OWN tally/verdict — computed up front so they appear in the
  // report even when a check fails (an auditor wants the honest number).
  const ownTally = guardedTally(bundle);
  const ownVerdict = guardedVerdict(bundle, ownTally);

  const byName: Record<string, Check> = {};

  // ── Check 1: setup (§11.1) ────────────────────────────────────────────────
  byName["setup"] = guard("setup", () => {
    const d = bundle.decision;
    const recomputed = computeSetupCommitment({
      options: d.options,
      method: d.method,
      rule: d.rule,
      ballotMode: d.ballotMode,
      resultsPolicy: d.resultsPolicy,
      rosterCommitment: d.rosterCommitment,
      issuerPubKeyHash: d.issuerPubKeyHash ?? null,
      schedule: d.schedule,
    });
    const ok = recomputed === bundle.setupCommitment;
    return {
      ok,
      detail: ok
        ? "setupCommitment binds the decision's options/method/rule/modes/roster/issuer/schedule"
        : `setupCommitment mismatch: recomputed ${recomputed} != served ${String(bundle.setupCommitment)}`,
    };
  });

  // ── Check 2: leaves (§11.2) ───────────────────────────────────────────────
  byName["leaves"] = guard("leaves", () => {
    let bad = 0;
    let firstBadSeq: number | undefined;
    for (const b of ballots) {
      const recomputed = recomputeBallotHash(decisionId, {
        logSeq: b.logSeq,
        payload: b.payload,
        serial: b.serial ?? null,
      });
      if (recomputed !== b.ballotHash) {
        bad++;
        if (firstBadSeq === undefined) firstBadSeq = b.logSeq;
      }
    }
    const ok = bad === 0;
    return {
      ok,
      detail: ok
        ? `all ${ballots.length} ballotHash(es) recompute from the public leaf recipe`
        : `${bad} ballot(s) do not match their served ballotHash (first at logSeq ${firstBadSeq})`,
    };
  });

  // ── Check 3: root-binding (§11.5) ─────────────────────────────────────────
  byName["root-binding"] = guard("root-binding", () => {
    const ordered = [...ballots].sort((a, b) => a.logSeq - b.logSeq);
    const recomputedRoot = merkleRoot(ordered.map((b) => b.ballotHash));
    const anchor = bundle.anchor ?? ({} as BundleAnchor);
    const rootMatches = recomputedRoot === anchor.root;

    const preimage = signedRootPreimage(anchor.root, anchor.treeSize, decisionId);
    const sigOk = verifySig(bundle.serverPubKeyPem, preimage, anchor.signedRoot);

    const ok = rootMatches && sigOk;
    let detail: string;
    if (ok) {
      detail = "Merkle root over served ballots == anchor.root AND the server signature over {root,treeSize,decisionId} verifies";
    } else if (!rootMatches && !sigOk) {
      detail = `root mismatch (recomputed ${recomputedRoot} != anchor ${String(anchor.root)}) and signedRoot does not verify`;
    } else if (!rootMatches) {
      detail = `Merkle root over served ballots ${recomputedRoot} != anchor.root ${String(anchor.root)}`;
    } else {
      detail = "anchor.signedRoot does not verify against the server public key for {root,treeSize,decisionId}";
    }
    return { ok, detail };
  });

  // ── Check 4: contiguity (§11.3) ───────────────────────────────────────────
  byName["contiguity"] = guard("contiguity", () => {
    const n = ballots.length;
    const seqs = ballots.map((b) => b.logSeq);
    const seen = new Set<number>();
    let dup = false;
    let outOfRange = false;
    for (const s of seqs) {
      if (!Number.isInteger(s) || s < 0 || s >= n) outOfRange = true;
      if (seen.has(s)) dup = true;
      seen.add(s);
    }
    // With no dup and no out-of-range, seen covers exactly {0..n-1}.
    const contiguous = !dup && !outOfRange && seen.size === n;
    const treeSizeOk = bundle.anchor?.treeSize === n;
    const ok = contiguous && treeSizeOk;
    let detail: string;
    if (ok) {
      detail = `logSeq is a contiguous 0..${n - 1} (no gaps/dupes) and treeSize === ${n}`;
    } else if (!contiguous) {
      detail = `logSeq is not a contiguous 0..${n - 1}${dup ? " (duplicate seq)" : ""}${outOfRange ? " (seq out of range)" : ""}`;
    } else {
      detail = `treeSize ${String(bundle.anchor?.treeSize)} != ballot count ${n}`;
    }
    return { ok, detail };
  });

  // ── Check 5: no-double-vote (§6 / §11.0) ──────────────────────────────────
  byName["no-double-vote"] = guard("no-double-vote", () => {
    const mode = bundle.decision?.ballotMode;
    if (mode !== "secret") {
      // Open mode: there are no anonymous credentials, so the host vouches for
      // one-ballot-per-eligible. The verifier cannot prove this from public data
      // (§6) — it is host-trusted, and we say so rather than pretend it's checked.
      return {
        ok: true,
        detail: "open mode: one-ballot-per-voter is host-trusted (§6); no anonymous serial to enforce",
      };
    }
    const serials = ballots.map((b) => b.serial).filter((s): s is string => s != null);
    const seen = new Set<string>();
    const dupes = new Set<string>();
    for (const s of serials) {
      if (seen.has(s)) dupes.add(s);
      seen.add(s);
    }
    const ok = dupes.size === 0;
    return {
      ok,
      detail: ok
        ? `no duplicate serial among ${serials.length} secret-mode ballot(s)`
        : `${dupes.size} duplicate secret-mode serial(s): ${[...dupes].slice(0, 5).join(", ")}`,
    };
  });

  // ── Check 6: tally-verdict (§11.4) ────────────────────────────────────────
  byName["tally-verdict"] = guard("tally-verdict", () => {
    const pub = bundle.publishedResult;
    if (!pub) {
      return {
        ok: true,
        detail: `recomputed tally + verdict (${ownVerdict.outcome}); no publishedResult to compare against`,
      };
    }
    const tallyMatch = canonicalize(ownTally) === canonicalize(pub.tally);
    const verdictMatch = canonicalize(ownVerdict) === canonicalize(pub.verdict);
    const ok = tallyMatch && verdictMatch;
    let detail: string;
    if (ok) {
      detail = `recomputed tally + verdict match the publishedResult (${ownVerdict.outcome})`;
    } else if (!tallyMatch && !verdictMatch) {
      detail = "recomputed tally AND verdict differ from the publishedResult";
    } else if (!tallyMatch) {
      detail = "recomputed tally differs from the published tally";
    } else {
      detail = `recomputed verdict (${ownVerdict.outcome}) differs from the published verdict (${String(pub.verdict?.outcome)})`;
    }
    return { ok, detail };
  });

  const checks = CHECK_ORDER.map((name) => byName[name]);
  const ok = checks.every((c) => c.ok);

  return { ok, decisionId, checks, tally: ownTally, verdict: ownVerdict };
}

/** Recompute the tally; on any structural defect fall back to an empty tally. */
function guardedTally(bundle: VerifierBundle): Tally {
  try {
    const ballots: BundleBallot[] = Array.isArray(bundle?.ballots) ? bundle.ballots : [];
    const method = bundle.decision.method;
    const optionCount = Array.isArray(bundle.decision.options)
      ? bundle.decision.options.length
      : 0;
    const payloads = ballots.map((b) => b.payload);
    return tally(method, payloads, optionCount);
  } catch {
    return {
      method: "single",
      optionCount: 0,
      optionScores: [],
      abstain: 0,
      totalCast: 0,
    };
  }
}

/** Recompute the verdict over the verifier's own tally; never throws. */
function guardedVerdict(bundle: VerifierBundle, t: Tally): Verdict {
  try {
    return verdict(t, bundle.decision.rule, t.totalCast);
  } catch {
    return { outcome: "failed" };
  }
}
