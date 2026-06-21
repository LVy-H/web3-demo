import { Router } from "express";
import type { Db, Repos } from "../db";
import { DuplicateBallotError } from "../db";
import type { ServerKey } from "../crypto";
import { canonicalize, sha256hex, chainNext } from "../crypto";
import { ballotPayloadSchema } from "../domain";
import { creditsSpent, QUADRATIC_CREDITS, type Method } from "../tally";
import { hashToken } from "../auth";
import { parseDecision } from "./decisionView";

export interface ParticipantDeps {
  db: Db;
  repos: Repos;
  serverKey: ServerKey;
  now: () => number;
}

/** Domain-separated canonical hash of a ballot (the leaf in the receipt chain). */
function computeBallotHash(
  decisionId: string,
  payload: unknown,
  idempotencyKey: string,
): string {
  return sha256hex(
    "tessera:ballot:v1\n" +
      canonicalize({ decisionId, payload, idempotencyKey }),
  );
}

export function participantRouter(deps: ParticipantDeps): Router {
  const { db, repos, serverKey } = deps;
  const router = Router();

  router.post("/ballots", (req, res) => {
    const { decisionId, payload, idempotencyKey, passcode, email } =
      req.body ?? {};

    const row = repos.decisions.get(decisionId);
    if (!row) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return;
    }
    const decision = parseDecision(row);

    // Late / not-yet-open cast → SIGNED rejection (§10/§12.5, exhibitable).
    if (decision.state !== "open") {
      const signature = serverKey.sign(
        canonicalize({ error: "decision-closed", decisionId }),
      );
      res.status(409).json({
        error: "decision-closed",
        code: "DECISION_CLOSED",
        decisionId,
        signature,
      });
      return;
    }

    // Eligibility (open mode: open | passcode | domain) — signed refusals. -----
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

    const ballotHash = computeBallotHash(decisionId, payload, idempotencyKey);
    const serial = typeof email === "string" ? email : null;

    // Single transaction: append ballot + advance head + persist receipt. -----
    const commit = db.transaction(() => {
      const prevHead = repos.head.get(decisionId)?.head ?? "";
      const logSeq = repos.ballots.count(decisionId);
      const newHead = chainNext(prevHead, ballotHash);

      repos.ballots.append({
        decisionId,
        payloadJson: JSON.stringify(payload),
        credentialSerial: serial,
        idempotencyKey,
        logSeq,
        prevHead,
        ballotHash,
      });
      repos.head.set(decisionId, newHead, logSeq + 1);

      const serverSig = serverKey.sign(
        canonicalize({
          ballotHash,
          logPosition: logSeq,
          runningRoot: newHead,
        }),
      );
      repos.receipts.put({
        ballotHash,
        decisionId,
        logPosition: logSeq,
        runningRoot: newHead,
        serverSig,
      });

      return {
        ballotHash,
        logPosition: logSeq,
        runningRoot: newHead,
        serverSig,
      };
    });

    try {
      const receipt = commit();
      res.status(201).json({ receipt, decisionId });
    } catch (err) {
      if (err instanceof DuplicateBallotError) {
        // Exactly-once retry: same (decisionId, idempotencyKey). If the payload
        // is identical the ballotHash matches the stored receipt → 200 replay.
        const existing = repos.receipts.byBallot(ballotHash);
        if (existing) {
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
        // Same key, DIFFERENT payload → no receipt for this hash → conflict.
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
