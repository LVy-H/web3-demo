import { Router, type Request, type Response } from "express";
import type { Repos } from "../db";
import type { ServerKey } from "../crypto";
import {
  canonicalize,
  sha256hex,
  computeSetupCommitment,
  genesisHead,
} from "../crypto";
import {
  DecisionCreateSchema,
  assertTransition,
  IllegalTransitionError,
  type DecisionState,
} from "../domain";
import { requireConvener, hashToken } from "../auth";
import { parseDecision } from "./decisionView";

export interface ConvenerDeps {
  repos: Repos;
  serverKey: ServerKey;
  now: () => number;
}

/**
 * Sign + append a lifecycle event over the canonical §9 transition record, then
 * (for real state changes) flip the decision row. The signed preimage always
 * uses the domain shape `{decisionId, from, to, actor, timestamp}` so a verifier
 * recomputes it from anchored metadata regardless of how it is stored.
 */
function appendSignedLifecycle(
  deps: ConvenerDeps,
  args: {
    decisionId: string;
    from: DecisionState;
    to: DecisionState;
    actor: string;
    /** Stored transition label; defaults to `to` (use 'extend' for amendments). */
    transition?: string;
    /** Extra fields folded into the signed preimage (e.g. closesAt). */
    extra?: Record<string, unknown>;
  },
): number {
  const timestamp = deps.now();
  const preimage = canonicalize({
    decisionId: args.decisionId,
    from: args.from,
    to: args.to,
    actor: args.actor,
    timestamp,
    ...(args.extra ?? {}),
  });
  const signedSig = deps.serverKey.sign(preimage);
  deps.repos.lifecycle.append({
    decisionId: args.decisionId,
    transition: args.transition ?? args.to,
    actor: args.actor,
    ts: timestamp,
    signedSig,
  });
  return timestamp;
}

export function convenerRouter(deps: ConvenerDeps): Router {
  const { repos } = deps;
  const router = Router();

  // Per-route guard (NOT router.use): convener routes share the path prefix
  // `/decisions/:id` with the public read API, so a router-wide middleware would
  // 401 the unauthenticated public GETs that fall through this router first.
  const guard = requireConvener(repos);

  // Load the decision and assert the caller is its convener; else write the
  // appropriate response and return null so the handler can early-exit.
  function loadOwned(req: Request, res: Response) {
    const id = String(req.params.id);
    const row = repos.decisions.get(id);
    if (!row) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return null;
    }
    if (row.convenerId !== req.account!.id) {
      res.status(403).json({ error: "forbidden", code: "FORBIDDEN" });
      return null;
    }
    return parseDecision(row);
  }

  // POST /decisions ----------------------------------------------------------
  router.post("/decisions", guard, (req, res) => {
    const parsed = DecisionCreateSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({
        error: "invalid",
        code: "VALIDATION",
        issues: parsed.error.issues,
      });
      return;
    }
    const d = parsed.data;

    // rosterCommitment binds the eligibility config (passcode hash / domain rule)
    // into the setupCommitment; `open` still commits its (method-only) shape.
    const rosterCommitment = sha256hex(canonicalize(d.eligibility));

    const setupCommitment = computeSetupCommitment({
      options: d.options,
      method: d.method,
      rule: d.rule,
      ballotMode: d.ballotMode,
      resultsPolicy: d.resultsPolicy,
      rosterCommitment,
      issuerPubKeyHash: null,
      schedule: d.schedule,
    });

    const decision = repos.decisions.insert({
      convenerId: req.account!.id,
      title: d.title,
      optionsJson: JSON.stringify(d.options),
      method: d.method,
      eligibilityJson: JSON.stringify(d.eligibility),
      visibility: d.visibility,
      ballotMode: d.ballotMode,
      resultsPolicy: d.resultsPolicy,
      ruleJson: JSON.stringify(d.rule),
      scheduleJson: JSON.stringify(d.schedule),
      anchorMode: d.anchorMode,
      maxParticipants: d.maxParticipants ?? null,
      setupCommitment,
      state: "draft",
    });

    // Eligibility record (open mode): passcode stores the passcode HASH; domain
    // stores the allowed domain; `open` stores nothing (no gate at cast time).
    const elig = d.eligibility as { method: string; passcode?: unknown; domain?: unknown };
    if (elig.method === "passcode" && typeof elig.passcode === "string") {
      repos.eligibility.create({
        decisionId: decision.id,
        method: "passcode",
        identifierOrHash: hashToken(elig.passcode),
        status: "issued",
        challengeable: false,
      });
    } else if (elig.method === "domain" && typeof elig.domain === "string") {
      repos.eligibility.create({
        decisionId: decision.id,
        method: "domain",
        identifierOrHash: elig.domain.toLowerCase().replace(/^@/, ""),
        status: "issued",
        challengeable: false,
      });
    }

    res.status(201).json({
      id: decision.id,
      state: "draft",
      setupCommitment,
    });
  });

  // Shared state-change handler (open/close/publish/cancel). -----------------
  function transitionHandler(to: DecisionState) {
    return (req: Request, res: Response) => {
      const decision = loadOwned(req, res);
      if (!decision) return;
      const from = decision.state as DecisionState;
      try {
        assertTransition(from, to);
      } catch (err) {
        if (err instanceof IllegalTransitionError) {
          res.status(409).json({
            error: "illegal-transition",
            code: "ILLEGAL_TRANSITION",
            from: err.from,
            to: err.to,
          });
          return;
        }
        throw err;
      }
      const at = appendSignedLifecycle(deps, {
        decisionId: decision.id,
        from,
        to,
        actor: req.account!.id,
      });
      repos.decisions.setState(decision.id, to, at);

      if (to === "open") {
        // Initialise the running head at genesis for this decision.
        repos.head.set(decision.id, genesisHead(decision.id), 0);
      }
      res.status(200).json({ id: decision.id, state: to });
    };
  }

  router.post("/decisions/:id/open", guard, transitionHandler("open"));
  router.post("/decisions/:id/close", guard, transitionHandler("closed"));
  router.post("/decisions/:id/cancel", guard, transitionHandler("cancelled"));

  // publish: closed→published OR challenge→published. -------------------------
  router.post("/decisions/:id/publish", guard, (req, res) => {
    const decision = loadOwned(req, res);
    if (!decision) return;
    const from = decision.state as DecisionState;
    try {
      assertTransition(from, "published");
    } catch (err) {
      if (err instanceof IllegalTransitionError) {
        res.status(409).json({
          error: "illegal-transition",
          code: "ILLEGAL_TRANSITION",
          from: err.from,
          to: err.to,
        });
        return;
      }
      throw err;
    }
    const at = appendSignedLifecycle(deps, {
      decisionId: decision.id,
      from,
      to: "published",
      actor: req.account!.id,
    });
    repos.decisions.setState(decision.id, "published", at);
    res.status(200).json({ id: decision.id, state: "published" });
  });

  // extend: open stays open; the latest extend event is the effective close. --
  router.post("/decisions/:id/extend", guard, (req, res) => {
    const decision = loadOwned(req, res);
    if (!decision) return;
    if (decision.state !== "open") {
      res.status(409).json({
        error: "illegal-transition",
        code: "ILLEGAL_TRANSITION",
        from: decision.state,
        to: "open",
      });
      return;
    }
    const closesAt = req.body?.closesAt;
    if (typeof closesAt !== "number" || !Number.isInteger(closesAt)) {
      res.status(400).json({
        error: "invalid",
        code: "VALIDATION",
        issues: [{ path: ["closesAt"], message: "closesAt must be an integer" }],
      });
      return;
    }
    appendSignedLifecycle(deps, {
      decisionId: decision.id,
      from: "open",
      to: "open",
      actor: req.account!.id,
      transition: "extend",
      extra: { transition: "extend", closesAt },
    });
    // (preimage carries transition:'extend' + closesAt so the amendment is
    //  tamper-evident; the row's `transition` column stores 'extend' too.)
    // State row is NOT mutated (§12.5): the effective close time is the latest
    // extend event, recoverable from the signed lifecycle log.
    res.status(200).json({ id: decision.id, state: "open", closesAt });
  });

  // GET /decisions/:id/turnout ----------------------------------------------
  router.get("/decisions/:id/turnout", guard, (req, res) => {
    const decision = loadOwned(req, res);
    if (!decision) return;
    res.status(200).json({ count: repos.ballots.count(decision.id) });
  });

  return router;
}
