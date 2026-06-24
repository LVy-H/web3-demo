import { Router, type RequestHandler, type Request, type Response, type NextFunction } from "express";
import rateLimit from "express-rate-limit";
import type { Db, Repos } from "../db";
import { DuplicateBallotError, DuplicateSerialError } from "../db";
import type { ServerKey } from "../crypto";
import { canonicalize, sha256hex } from "../crypto";
import { merkleRoot } from "../merkle";
import { ballotPayloadSchema } from "../domain";
import { creditsSpent, QUADRATIC_CREDITS, type Method } from "../tally";
import { hashToken } from "../auth";
import { blindSign, verifyCredential } from "../credentials";
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
 * Thrown inside the cast transaction when a SECRET-mode credential `serial` is
 * already present for the decision (the no-double-vote re-check, §11.3). The
 * route maps it to a signed 409 rather than recording a double-vote.
 */
class SerialUsedError extends Error {
  readonly decisionId: string;
  readonly serial: string;
  constructor(decisionId: string, serial: string) {
    super(`serial already cast for decision ${decisionId}`);
    this.name = "SerialUsedError";
    this.decisionId = decisionId;
    this.serial = serial;
  }
}

/**
 * Express 4 does NOT catch a rejected promise from an `async` handler (it would
 * hang the request / surface as an unhandledRejection). `/register` and
 * `/ballots` are async (the blind-sig credential bridge is async), so we wrap
 * them to forward any rejection to Express's error machinery via `next`.
 */
function asyncHandler(
  fn: (req: Request, res: Response) => Promise<void>,
): RequestHandler {
  return (req, res, next: NextFunction) => {
    fn(req, res).catch(next);
  };
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

  /**
   * Shared eligibility gate for both /register and /ballots (open | passcode |
   * domain). Returns `true` iff the presented body satisfies the decision's
   * eligibility method. `open` admits everyone (no gate). §6 honest scope: the
   * roster is host-defined, so passing is necessary, not a proof against host
   * stuffing.
   */
  function checkEligibility(
    decision: ReturnType<typeof parseDecision>,
    body: { passcode?: unknown; email?: unknown },
  ): boolean {
    const elig = decision.eligibility;
    if (elig.method === "passcode") {
      const { passcode } = body;
      if (typeof passcode !== "string" || passcode.length === 0) return false;
      const record = repos.eligibility.find(decision.id, hashToken(passcode));
      return record !== null;
    }
    if (elig.method === "domain") {
      const allowed = String((elig as { domain?: unknown }).domain ?? "")
        .toLowerCase()
        .replace(/^@/, "");
      const email = body.email;
      const at = typeof email === "string" ? email.lastIndexOf("@") : -1;
      const domain = at >= 0 ? (email as string).slice(at + 1).toLowerCase() : "";
      return Boolean(allowed && domain && domain === allowed);
    }
    // open (and invite, whose single-use credential is the secret-mode flow) →
    // no inline gate here.
    return true;
  }

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

  // POST /register — SECRET mode credential issuance (§12.2, §11.0). ----------
  // The client blinds a credential message LOCALLY and sends only the blinded
  // token; the server blind-signs it with the per-decision issuer private key
  // and returns the blind signature for the client to `finalize()`. The server
  // NEVER sees the final (serial, sig), so issuance cannot be linked to the
  // eventual ballot from the issued blob (the §6 honest-scope limit is timing/
  // metadata correlation by a LIVE host, NOT the issued token itself).
  //
  // Registration CLOSES before voting: this route requires state 'registration'
  // and 403/409s once the decision is 'open' (breaks issuance↔cast ordering).
  router.post("/register", ballotLimiter, asyncHandler(async (req, res) => {
    const { decisionId, blindedMessage } = req.body ?? {};

    const row = repos.decisions.get(decisionId);
    if (!row) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return;
    }
    const decision = parseDecision(row);

    // Only SECRET-mode decisions issue blind-sig credentials.
    if (decision.ballotMode !== "secret") {
      res.status(400).json({
        error: "not-secret-mode",
        code: "NOT_SECRET_MODE",
        decisionId,
      });
      return;
    }

    // Registration-before-voting (§11.0): once 'open' (or beyond), registration
    // is closed → a SIGNED, exhibitable refusal so a late registrant has proof.
    if (decision.state !== "registration") {
      const signature = serverKey.sign(
        canonicalize({ error: "registration-closed", decisionId }),
      );
      res.status(409).json({
        error: "registration-closed",
        code: "REGISTRATION_CLOSED",
        decisionId,
        signature,
      });
      return;
    }

    // Eligibility gate (open | passcode | domain). Same surface as cast: a
    // shared passcode / allowed domain admits a registrant; `open` admits all.
    // NOTE (§6): the roster is host-defined; passing this is necessary, not a
    // proof against host stuffing.
    if (!checkEligibility(decision, req.body ?? {})) {
      const signature = serverKey.sign(
        canonicalize({ error: "ineligible", decisionId }),
      );
      res.status(403).json({
        error: "ineligible",
        code: "INELIGIBLE",
        decisionId,
        signature,
      });
      return;
    }

    // Cap issuance at maxParticipants (open mode trades stuffing for friction,
    // §10) — measured against the issued-credential ledger, not cast ballots.
    if (
      decision.maxParticipants !== null &&
      decision.maxParticipants !== undefined &&
      repos.issuedCredentials.count(decisionId) >= decision.maxParticipants
    ) {
      const signature = serverKey.sign(
        canonicalize({ error: "registration-full", decisionId }),
      );
      res.status(409).json({
        error: "registration-full",
        code: "MAX_PARTICIPANTS",
        decisionId,
        signature,
      });
      return;
    }

    if (typeof blindedMessage !== "string" || blindedMessage.length === 0) {
      res.status(400).json({
        error: "invalid",
        code: "VALIDATION",
        issues: [
          { path: ["blindedMessage"], message: "blindedMessage is required" },
        ],
      });
      return;
    }

    const key = repos.signingKeys.get(decisionId);
    if (!key) {
      // A secret-mode decision MUST have an issuer key (minted at create). Its
      // absence is a server-state error, not a client one.
      res.status(500).json({ error: "no-issuer-key", code: "NO_ISSUER_KEY" });
      return;
    }

    let blindSignature: string;
    try {
      blindSignature = await blindSign(key.privateKeyPem, blindedMessage);
    } catch {
      // A malformed blinded token (e.g. wrong size for the modulus) is a client
      // error, not a crash.
      res.status(400).json({
        error: "invalid-blinded-message",
        code: "INVALID_BLINDED_MESSAGE",
        decisionId,
      });
      return;
    }

    // Record the issuance in the append-only §6 ledger (no link to a ballot).
    repos.issuedCredentials.record(decisionId, deps.now());

    res.status(200).json({ decisionId, blindSignature });
  }));

  router.post("/ballots", ballotLimiter, asyncHandler(async (req, res) => {
    const { decisionId, payload, idempotencyKey, serial, credentialSig } =
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

    // ── Eligibility — SECRET vs OPEN mode. ────────────────────────────────────
    // SECRET (§11.2/§11.3): the ballot carries an anonymous blind-sig credential
    // `(serial, credentialSig)`. The credential is the eligibility proof — there
    // is no roster lookup. We verify it against the per-decision issuer pubkey
    // over the EXACT bound message `${decisionId}|${serial}`, and the serial is
    // the no-double-vote key (the public leaf binds it, so the verifier's check
    // works). `credentialSerial = serial` is persisted below.
    let credentialSerial: string | null = null;
    if (decision.ballotMode === "secret") {
      if (
        typeof serial !== "string" ||
        serial.length === 0 ||
        typeof credentialSig !== "string" ||
        credentialSig.length === 0
      ) {
        ineligible();
        return;
      }
      const key = repos.signingKeys.get(decisionId);
      // No issuer key ⇒ malformed secret decision; treat the cast as ineligible
      // (a forged/unverifiable credential, from the voter's perspective).
      if (!key) {
        ineligible();
        return;
      }
      const message = `${decisionId}|${serial}`;
      const ok = await verifyCredential(key.publicKeyPem, message, credentialSig);
      if (!ok) {
        ineligible();
        return;
      }
      // No double-vote (§11.3): a serial already cast for this decision → a
      // SIGNED 409 conflict the voter can exhibit. Checked before the
      // transaction; the (decisionId, serial) uniqueness is re-confirmed inside.
      if (repos.ballots.serialExists(decisionId, serial)) {
        const signature = serverKey.sign(
          canonicalize({ error: "serial-used", decisionId, serial }),
        );
        res.status(409).json({
          error: "serial-used",
          code: "SERIAL_USED",
          decisionId,
          signature,
        });
        return;
      }
      credentialSerial = serial;
    } else {
      // OPEN mode (open | passcode | domain) — signed refusals.
      //
      // H2 (disclosed limitation, §6): open mode — INCLUDING a shared passcode —
      // has NO per-voter credential, so a determined eligible voter can cast
      // multiple ballots by varying idempotencyKey. This is the deliberate "open
      // mode trades stuffing-resistance for friction" trade-off; the per-voter
      // one-ballot guarantee is exactly what SECRET mode's credential gives.
      // maxParticipants (above) + the rate-limit are the open-mode friction
      // controls. We intentionally do NOT call repos.eligibility.markUsed for a
      // shared passcode: it is one record for the whole roster, so marking it
      // 'used' would lock out everyone after the FIRST cast.
      if (!checkEligibility(decision, req.body ?? {})) {
        ineligible();
        return;
      }
    }

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

    // The public-leaf serial: the unblinded credential serial in SECRET mode
    // (set above), `null` in OPEN mode. Persisting null in open mode — rather
    // than the voter's email — keeps the public ballot log non-identifying; in
    // secret mode the serial is anonymous-by-construction (the issuer never saw
    // the final token) yet enables the no-double-vote check.
    const leafSerial: string | null = credentialSerial;

    // Single transaction: append ballot + recompute the Merkle root + persist
    // the receipt committing to it (the running root === §11.5 Merkle root). ---
    const commit = db.transaction(() => {
      // Re-confirm serial uniqueness INSIDE the txn (single-writer SQLite, but
      // belt-and-braces against an interleave): a duplicate secret serial aborts
      // the txn rather than recording a double-vote.
      if (leafSerial !== null && repos.ballots.serialExists(decisionId, leafSerial)) {
        throw new SerialUsedError(decisionId, leafSerial);
      }
      const prevHead = repos.head.get(decisionId)?.head ?? "";
      const logSeq = repos.ballots.count(decisionId);

      // The PUBLIC leaf: binds decisionId + this position + payload + serial,
      // and is recomputable by an independent verifier from public data alone.
      const ballotHash = computeBallotHash(decisionId, logSeq, payload, leafSerial);

      repos.ballots.append({
        decisionId,
        payloadJson: JSON.stringify(payload),
        credentialSerial: leafSerial,
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
      if (err instanceof SerialUsedError || err instanceof DuplicateSerialError) {
        // A duplicate secret-mode serial — caught either by the pre-insert
        // read-check (SerialUsedError) or by the DB UNIQUE index at INSERT time
        // under a concurrent interleave (DuplicateSerialError). Both return the
        // SAME signed 409 (no double-vote, §11.3).
        const serial =
          err instanceof SerialUsedError ? err.serial : err.credentialSerial;
        const signature = serverKey.sign(
          canonicalize({ error: "serial-used", decisionId, serial }),
        );
        res.status(409).json({
          error: "serial-used",
          code: "SERIAL_USED",
          decisionId,
          signature,
        });
        return;
      }
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
  }));

  return router;
}
