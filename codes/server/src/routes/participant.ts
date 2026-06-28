import { Router, type RequestHandler } from "express";
import rateLimit from "express-rate-limit";
import type { Db, Repos } from "../db";
import { DuplicateBallotError } from "../db";
import type { ServerKey } from "../crypto";
import { canonicalize, sha256hex } from "../crypto";
import { merkleRoot } from "../merkle";
import { ballotPayloadSchema } from "../domain";
import { creditsSpent, QUADRATIC_CREDITS, type Method } from "../tally";
import { hashToken } from "../auth";
import { parseDecision } from "./decisionView";
import { effectiveClose } from "./effectiveClose";
import type { RateLimitConfig } from "../app";

export interface ParticipantDeps {
  db: Db;
  repos: Repos;
  serverKey: ServerKey;
  now: () => number;
  /** §10 ballot rate-limit; `null` disables it (tests/e2e cast fast). */
  ballotRateLimit?: RateLimitConfig | null;
}

/**
 * The PUBLIC, recomputable ballot leaf (system-design §11.2 / the Phase-3 plan).
 *
 *   ballotHash = sha256hex('tessera:leaf:v1\n' + canonicalize(
 *                  { decisionId, logSeq, payload, serial: serial ?? null }))
 *
 * Recomputable from public data ALONE: the idempotencyKey is deliberately NOT
 * in the leaf (it stays a private dedup key in the UNIQUE constraint), and the
 * leaf binds `logSeq` so the position is committed. The independent verifier
 * recomputes this exact string (`recomputeBallotHash`), so the server MUST emit
 * it byte-for-byte. `serial` is the credential serial (null in open mode).
 */
function computeBallotHash(
  decisionId: string,
  logSeq: number,
  payload: unknown,
  serial: string | null,
): string {
  return sha256hex(
    "tessera:leaf:v1\n" +
      canonicalize({ decisionId, logSeq, payload, serial: serial ?? null }),
  );
}

export function participantRouter(deps: ParticipantDeps): Router {
  const { db, repos, serverKey } = deps;
  const router = Router();

  // §10 abuse control: rate-limit ballot casts per client IP. `null` disables it
  // (tests/e2e). A 429 is the standard throttle response. NOTE (H2): open mode
  // has no per-voter credential, so a determined eligible voter can still cast
  // multiple ballots by varying idempotencyKey — the true one-ballot-per-voter
  // guarantee arrives with Phase-3 blind-sig credentials. maxParticipants (the
  // cast-path cap below) + this rate-limit are the Phase-2 FRICTION controls.
  const ballotLimiter: RequestHandler = deps.ballotRateLimit
    ? rateLimit({
        windowMs: deps.ballotRateLimit.windowMs,
        max: deps.ballotRateLimit.max,
        standardHeaders: true,
        legacyHeaders: false,
      })
    : (_req, _res, next) => next();

  router.post("/ballots", ballotLimiter, (req, res) => {
    const { decisionId, payload, idempotencyKey, passcode, email } =
      req.body ?? {};

    const row = repos.decisions.get(decisionId);
    if (!row) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return;
    }
    const decision = parseDecision(row);

    // A SIGNED, exhibitable 'decision-closed' refusal — a late ballot must get
    // proof it was refused (§10/§12.5). Shared by the state check + the
    // effective-close check below.
    const rejectClosed = () => {
      const signature = serverKey.sign(
        canonicalize({ error: "decision-closed", decisionId }),
      );
      res.status(409).json({
        error: "decision-closed",
        code: "DECISION_CLOSED",
        decisionId,
        signature,
      });
    };

    // Late / not-yet-open cast → SIGNED rejection (§10/§12.5, exhibitable).
    if (decision.state !== "open") {
      rejectClosed();
      return;
    }

    // M2 — maxParticipants cap. NOTE (H2): in open mode there is no per-voter
    // credential, so this caps DISTINCT ballots, not distinct voters; a
    // determined eligible voter could still vary idempotencyKey. It (with the
    // rate-limit) is the Phase-2 FRICTION control; true one-ballot-per-voter
    // arrives with Phase-3 blind-sig credentials. Checked before accepting.
    if (
      decision.maxParticipants !== null &&
      decision.maxParticipants !== undefined &&
      repos.ballots.count(decisionId) >= decision.maxParticipants
    ) {
      const signature = serverKey.sign(
        canonicalize({ error: "decision-full", decisionId }),
      );
      res.status(409).json({
        error: "decision-full",
        code: "MAX_PARTICIPANTS",
        decisionId,
        signature,
      });
      return;
    }

    // M2 — scheduled / extended close enforcement (§12.5). The EFFECTIVE close is
    // the latest 'extend' amendment's closesAt, else the decision schedule's
    // closesAt. A ballot arriving after it gets the SAME signed decision-closed
    // proof (the server may have been down past the scheduled close).
    const closeAt = effectiveClose(
      repos.lifecycle.byDecision(decisionId),
      decision.schedule,
    );
    if (closeAt !== null && deps.now() > closeAt) {
      rejectClosed();
      return;
    }

    // Eligibility (open mode: open | passcode | domain) — signed refusals. -----
    //
    // H2 (disclosed limitation, §6): open mode — INCLUDING a shared passcode —
    // has NO per-voter credential, so a determined eligible voter can cast
    // multiple ballots by varying idempotencyKey. This is the deliberate "open
    // mode trades stuffing-resistance for friction" trade-off; the true
    // one-ballot-per-voter guarantee arrives with Phase-3 blind-sig credentials.
    // maxParticipants (above) + the rate-limit are the Phase-2 friction controls.
    // We intentionally do NOT call repos.eligibility.markUsed for a shared
    // passcode here: a shared secret is one record for the whole roster, so
    // marking it 'used' would lock out everyone after the FIRST cast.
    const elig = decision.eligibility;
    const ineligible = () => {
      const signature = serverKey.sign(
        canonicalize({ error: "ineligible", decisionId }),
      );
      res.status(403).json({
        error: "ineligible",
        code: "INELIGIBLE",
        decisionId,
        signature,
      });
    };

    if (elig.method === "passcode") {
      if (typeof passcode !== "string" || passcode.length === 0) {
        ineligible();
        return;
      }
      const presented = hashToken(passcode);
      const record = repos.eligibility.find(decisionId, presented);
      if (!record) {
        ineligible();
        return;
      }
    } else if (elig.method === "domain") {
      const allowed = String((elig as { domain?: unknown }).domain ?? "")
        .toLowerCase()
        .replace(/^@/, "");
      const at = typeof email === "string" ? email.lastIndexOf("@") : -1;
      const domain =
        at >= 0 ? email.slice(at + 1).toLowerCase() : "";
      if (!allowed || !domain || domain !== allowed) {
        ineligible();
        return;
      }
    }
    // open → no gate.

    // Payload validation (per-method, range-checked to option count). ---------
    const schema = ballotPayloadSchema(
      decision.method as Method,
      decision.options.length,
    );
    const parsed = schema.safeParse(payload);
    if (!parsed.success) {
      res.status(400).json({
        error: "invalid-ballot",
        code: "VALIDATION",
        issues: parsed.error.issues,
      });
      return;
    }
    const validPayload = parsed.data as { kind: string; votes?: number[] };

    // Quadratic budget gate (Σ vᵢ² ≤ QUADRATIC_CREDITS). ----------------------
    if (
      decision.method === "quadratic" &&
      validPayload.kind === "quadratic" &&
      Array.isArray(validPayload.votes) &&
      creditsSpent(validPayload.votes) > QUADRATIC_CREDITS
    ) {
      res.status(400).json({
        error: "budget-exceeded",
        code: "BUDGET_EXCEEDED",
      });
      return;
    }

    if (typeof idempotencyKey !== "string" || idempotencyKey.length === 0) {
      res.status(400).json({
        error: "invalid",
        code: "VALIDATION",
        issues: [
          { path: ["idempotencyKey"], message: "idempotencyKey is required" },
        ],
      });
      return;
    }

    // Open mode: there is no anonymous credential, so the serial is null (the
    // public leaf records `serial: null`). Persisting null — rather than the
    // voter's email — keeps the public ballot log non-identifying. Credentialed
    // secret-mode (serial = unblinded credential serial) is a later iteration.
    const serial: string | null = null;

    // Single transaction: append ballot + recompute the Merkle root + persist
    // the receipt committing to it (the running root === §11.5 Merkle root). ---
    const commit = db.transaction(() => {
      const prevHead = repos.head.get(decisionId)?.head ?? "";
      const logSeq = repos.ballots.count(decisionId);

      // The PUBLIC leaf: binds decisionId + this position + payload + serial,
      // and is recomputable by an independent verifier from public data alone.
      const ballotHash = computeBallotHash(decisionId, logSeq, payload, serial);

      repos.ballots.append({
        decisionId,
        payloadJson: JSON.stringify(payload),
        credentialSerial: serial,
        idempotencyKey,
        logSeq,
        prevHead,
        ballotHash,
      });

      // Recompute the RFC 6962 Merkle root over EVERY leaf (including the one
      // just appended). This becomes the receipt's runningRoot and the decision
      // head, so /root, the receipt, and the verifier's recomputation all agree.
      const newRoot = merkleRoot(repos.ballots.leafHashes(decisionId));
      repos.head.set(decisionId, newRoot, logSeq + 1);

      const serverSig = serverKey.sign(
        canonicalize({
          ballotHash,
          logPosition: logSeq,
          runningRoot: newRoot,
        }),
      );
      repos.receipts.put({
        ballotHash,
        decisionId,
        logPosition: logSeq,
        runningRoot: newRoot,
        serverSig,
      });

      return {
        ballotHash,
        logPosition: logSeq,
        runningRoot: newRoot,
        serverSig,
      };
    });

    try {
      const receipt = commit();
      res.status(201).json({ receipt, decisionId });
    } catch (err) {
      if (err instanceof DuplicateBallotError) {
        // Exactly-once retry: same (decisionId, idempotencyKey). The leaf now
        // binds logSeq, so we compare the STORED payload (not a recomputed hash)
        // to tell an identical replay from a same-key/different-payload conflict.
        const stored = repos.ballots.findByIdempotency(decisionId, idempotencyKey);
        const existing = stored ? repos.receipts.byBallot(stored.ballotHash) : null;
        const samePayload =
          stored !== null &&
          canonicalize(JSON.parse(stored.payloadJson)) === canonicalize(payload);
        if (existing && samePayload) {
          res.status(200).json({
            receipt: {
              ballotHash: existing.ballotHash,
              logPosition: existing.logPosition,
              runningRoot: existing.runningRoot,
              serverSig: existing.serverSig,
            },
            decisionId,
          });
          return;
        }
        // Same key, DIFFERENT payload → conflict (exactly-once is violated).
        res.status(409).json({
          error: "idempotency-conflict",
          code: "IDEMPOTENCY_CONFLICT",
        });
        return;
      }
      throw err;
    }
  });

  return router;
}
