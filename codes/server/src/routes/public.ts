import { Router } from "express";
import type { Repos } from "../db";
import type { ServerKey } from "../crypto";
import { canonicalize, sha256hex } from "../crypto";
import { merkleRoot } from "../merkle";
import { signedRootPayload } from "../anchor";
import { tally, verdict, type Method, type Rule, type BallotPayload } from "../tally";
import { verifyDecision, type VerifierBundle } from "../verifier";
import { parseDecision, type ParsedDecision } from "./decisionView";

export interface PublicDeps {
  repos: Repos;
  serverKey: ServerKey;
}

/**
 * rosterCommitment = sha256hex(canonicalize(eligibility)) — the same value the
 * convener folded into the setupCommitment at create time. Exposed (as a hash,
 * never the raw eligibility) so an independent verifier can recompute the
 * setupCommitment from public data (§11.1).
 */
function rosterCommitmentOf(d: ParsedDecision): string {
  return sha256hex(canonicalize(d.eligibility));
}

/**
 * The decision's anchored issuer pubkey hash, or null. SECRET mode mints a
 * per-decision RSABSSA-PSS issuer at create; its `pubKeyHash` is in the
 * setupCommitment, so a verifier needs the SAME value to rebuild it. Open mode
 * has no issuer → null.
 */
function issuerPubKeyHashOf(repos: PublicDeps["repos"], decisionId: string): string | null {
  return repos.signingKeys.get(decisionId)?.pubKeyHash ?? null;
}

export function publicRouter(deps: PublicDeps): Router {
  const { repos, serverKey } = deps;
  const router = Router();

  // GET /key — the server's advertised Ed25519 public key (SPKI PEM). ---------
  // A verifier needs this to check the anchor's signedRoot; it is the host's
  // signing identity, committed/advertised once and stable across restarts.
  router.get("/key", (_req, res) => {
    res.status(200).json({
      serverPubKeyPem: serverKey.publicKeyPem,
      keyId: serverKey.keyId,
    });
  });

  // GET /decisions/:id — public metadata view (never exposes tokens). --------
  router.get("/decisions/:id", (req, res) => {
    const row = repos.decisions.get(String(req.params.id));
    if (!row) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return;
    }
    const d = parseDecision(row);
    res.status(200).json({
      id: d.id,
      title: d.title,
      options: d.options,
      method: d.method,
      ballotMode: d.ballotMode,
      resultsPolicy: d.resultsPolicy,
      rule: d.rule,
      schedule: d.schedule,
      visibility: d.visibility,
      anchorMode: d.anchorMode,
      // Public commitments a verifier needs to rebuild the setupCommitment.
      rosterCommitment: rosterCommitmentOf(d),
      // SECRET mode: the anchored per-decision issuer pubkey hash (§12.2); null
      // in open mode. A verifier folds this into its recomputed setupCommitment.
      issuerPubKeyHash: issuerPubKeyHashOf(repos, d.id),
      // §6 stuffing audit: how many blind-sig credentials were issued (≤ roster).
      issuedCount: repos.issuedCredentials.count(d.id),
      setupCommitment: d.setupCommitment,
      // The signing identity the verifier checks the anchor signature against.
      serverPubKeyPem: serverKey.publicKeyPem,
      state: d.state,
      createdAt: d.createdAt,
      turnout: repos.ballots.count(d.id),
      trustLevel: d.anchorMode,
    });
  });

  // GET /decisions/:id/issuer — the PUBLIC per-decision RSABSSA issuer pubkey. --
  // A secret-mode voter holds only the decision id; to `blind()` a credential
  // they need the issuer SPKI public key. `create` returns it once to the
  // convener, but a fresh voter cannot see that response — so expose it here,
  // trust-minimised: the client recomputes sha256hex(issuerPublicKeyPem) and
  // checks it equals the anchored `issuerPubKeyHash` (in the setupCommitment)
  // before blinding, so a tampered key is caught before any round trip.
  // Open mode / a decision with no issuer key → 404 NOT_SECRET.
  router.get("/decisions/:id/issuer", (req, res) => {
    const id = String(req.params.id);
    const row = repos.decisions.get(id);
    if (!row) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return;
    }
    const d = parseDecision(row);
    const key = repos.signingKeys.get(id);
    if (d.ballotMode !== "secret" || !key) {
      // Not a secret-ballot decision (no per-decision issuer) → nothing to serve.
      res.status(404).json({ error: "not-secret", code: "NOT_SECRET", decisionId: id });
      return;
    }
    res.status(200).json({
      issuerPublicKeyPem: key.publicKeyPem,
      // The SAME anchored hash the public view / verifier bind to; the client
      // asserts sha256hex(issuerPublicKeyPem) === this before blinding.
      issuerPubKeyHash: key.pubKeyHash,
    });
  });

  // GET /ballots?decisionId=&after=&limit= — cursor-paginated ballot list. ----
  router.get("/ballots", (req, res) => {
    const decisionId = String(req.query.decisionId ?? "");
    if (!decisionId) {
      res.status(400).json({ error: "invalid", code: "VALIDATION" });
      return;
    }
    // `byDecision` filters `log_seq > afterSeq`; logSeq is 0-indexed, so the
    // default cursor is -1 (return from the very first ballot). A caller-supplied
    // `after` is the last logSeq they have seen.
    const after =
      req.query.after !== undefined ? Number(req.query.after) : -1;
    const limit =
      req.query.limit !== undefined ? Number(req.query.limit) : 100;
    const afterSeq = Number.isFinite(after) ? after : -1;
    const lim = Number.isFinite(limit) && limit > 0 ? limit : 100;

    const rows = repos.ballots.byDecision(decisionId, afterSeq, lim);
    // `serial` + the public `ballotHash` are included so a verifier can rebuild
    // the Merkle bundle from public data alone (recomputeBallotHash needs both).
    const ballots = rows.map((b) => ({
      logSeq: b.logSeq,
      payload: JSON.parse(b.payloadJson),
      serial: b.credentialSerial,
      ballotHash: b.ballotHash,
      prevHead: b.prevHead,
    }));
    const leafCount = repos.ballots.count(decisionId);
    const nextCursor =
      ballots.length === lim && ballots.length > 0
        ? ballots[ballots.length - 1].logSeq
        : null;
    // M3: an explicit end-of-stream flag so a verifier recomputing the §11.5
    // Merkle root knows when it has drained the log. `complete` is true once this
    // page reached the end (fewer than `limit` rows, or no further cursor).
    const complete = nextCursor === null;

    res.status(200).json({ ballots, leafCount, nextCursor, complete });
  });

  // GET /root?decisionId= — current RFC 6962 Merkle root + tree size. ---------
  router.get("/root", (req, res) => {
    const decisionId = String(req.query.decisionId ?? "");
    if (!repos.decisions.get(decisionId)) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return;
    }
    const head = repos.head.get(decisionId);
    const root = head?.head ?? merkleRoot([]);
    const treeSize = head?.leafCount ?? 0;
    // `head`/`leafCount` are kept as aliases of `root`/`treeSize` for any
    // existing client; they now carry the Merkle root, not the hash-chain head.
    res.status(200).json({ root, treeSize, head: root, leafCount: treeSize });
  });

  // GET /results?decisionId= — non-authoritative recomputed tally + verdict. --
  router.get("/results", (req, res) => {
    const decisionId = String(req.query.decisionId ?? "");
    const row = repos.decisions.get(decisionId);
    if (!row) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return;
    }
    const d = parseDecision(row);
    // afterSeq = -1 → include the logSeq-0 ballot (the repo filters `> afterSeq`).
    const ballots = repos.ballots
      .byDecision(decisionId, -1)
      .map((b) => JSON.parse(b.payloadJson) as BallotPayload);

    const t = tally(d.method as Method, ballots, d.options.length);
    // Phase-2 open mode: the published cast set IS the denominator (turnout).
    const v = verdict(t, d.rule as unknown as Rule, t.totalCast);

    res.status(200).json({ tally: t, verdict: v, authoritative: false });
  });

  // GET /anchor?decisionId= — the broadcast anchor bundle (§12.1). -----------
  // After /publish: the latest persisted signed checkpoint (the distributed,
  // tamper-evident root). Before publish: a LIVE broadcast of the current root
  // (signed on the fly over the same preimage) so a verifier can bind in-flight.
  router.get("/anchor", (req, res) => {
    const decisionId = String(req.query.decisionId ?? "");
    const row = repos.decisions.get(decisionId);
    if (!row) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return;
    }
    const checkpoint = repos.checkpoints.latest(decisionId);
    if (checkpoint) {
      res.status(200).json({
        mode: "broadcast",
        root: checkpoint.root,
        treeSize: checkpoint.treeSize,
        signedRoot: checkpoint.signedRoot,
        status: "broadcast",
      });
      return;
    }
    // No final checkpoint yet → broadcast the LIVE root (same signed preimage as
    // a checkpoint), so /anchor is bindable throughout voting, not only after
    // publish. This is exactly what /publish later persists for the final root.
    const head = repos.head.get(decisionId);
    const root = head?.head ?? merkleRoot([]);
    const treeSize = head?.leafCount ?? 0;
    const signedRoot = serverKey.sign(
      signedRootPayload({ root, treeSize, decisionId }),
    );
    res.status(200).json({
      mode: "broadcast",
      root,
      treeSize,
      signedRoot,
      status: "broadcast",
    });
  });

  // GET /verify/:id — assemble the public bundle + run the independent verifier.
  // NON-AUTHORITATIVE: the point is that the verifier is a pure module anyone can
  // run themselves over the public endpoints; this is a server-side convenience
  // that builds the SAME bundle from the DB and returns verifyDecision()'s report.
  router.get("/verify/:id", (req, res) => {
    const id = String(req.params.id);
    const row = repos.decisions.get(id);
    if (!row) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return;
    }
    const d = parseDecision(row);

    // Ballots, as the verifier sees them (everything here is public).
    const ballots = repos.ballots.byDecision(id, -1).map((b) => ({
      logSeq: b.logSeq,
      payload: JSON.parse(b.payloadJson) as BallotPayload,
      serial: b.credentialSerial,
      ballotHash: b.ballotHash,
    }));

    // Anchor: the persisted final checkpoint if published, else the live root.
    const checkpoint = repos.checkpoints.latest(id);
    let anchorRoot: string;
    let anchorTreeSize: number;
    let anchorSignedRoot: string;
    if (checkpoint) {
      anchorRoot = checkpoint.root;
      anchorTreeSize = checkpoint.treeSize;
      anchorSignedRoot = checkpoint.signedRoot;
    } else {
      const head = repos.head.get(id);
      anchorRoot = head?.head ?? merkleRoot([]);
      anchorTreeSize = head?.leafCount ?? 0;
      anchorSignedRoot = serverKey.sign(
        signedRootPayload({ root: anchorRoot, treeSize: anchorTreeSize, decisionId: id }),
      );
    }

    // The result the server would publish (so the verifier asserts it matches
    // its OWN recompute). Open mode: turnout is the denominator.
    const t = tally(
      d.method as Method,
      ballots.map((b) => b.payload),
      d.options.length,
    );
    const v = verdict(t, d.rule as unknown as Rule, t.totalCast);

    const bundle: VerifierBundle = {
      decision: {
        id: d.id,
        title: d.title,
        options: d.options,
        method: d.method as Method,
        ballotMode: d.ballotMode as "open" | "secret",
        resultsPolicy: d.resultsPolicy as "sealed" | "live",
        rule: d.rule as unknown as Rule,
        schedule: d.schedule,
        visibility: d.visibility,
        anchorMode: d.anchorMode,
        rosterCommitment: rosterCommitmentOf(d),
        // SECRET mode binds the real anchored issuer pubkey hash; open mode null.
        issuerPubKeyHash: issuerPubKeyHashOf(repos, d.id),
      },
      setupCommitment: d.setupCommitment,
      serverPubKeyPem: serverKey.publicKeyPem,
      ballots,
      anchor: {
        root: anchorRoot,
        treeSize: anchorTreeSize,
        signedRoot: anchorSignedRoot,
      },
      publishedResult: { tally: t, verdict: v },
    };

    const report = verifyDecision(bundle);
    res.status(200).json({ report, authoritative: false });
  });

  return router;
}
