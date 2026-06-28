import { Router } from "express";
import type { Repos } from "../db";
import { tally, verdict, type Method, type Rule, type BallotPayload } from "../tally";
import { parseDecision } from "./decisionView";

export interface PublicDeps {
  repos: Repos;
}

export function publicRouter(deps: PublicDeps): Router {
  const { repos } = deps;
  const router = Router();

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
      setupCommitment: d.setupCommitment,
      state: d.state,
      createdAt: d.createdAt,
      turnout: repos.ballots.count(d.id),
      trustLevel: d.anchorMode,
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
    const ballots = rows.map((b) => ({
      logSeq: b.logSeq,
      payload: JSON.parse(b.payloadJson),
      ballotHash: b.ballotHash,
      prevHead: b.prevHead,
    }));
    const leafCount = repos.ballots.count(decisionId);
    const nextCursor =
      ballots.length === lim && ballots.length > 0
        ? ballots[ballots.length - 1].logSeq
        : null;
    // M3: an explicit end-of-stream flag so a verifier recomputing the §11.5
    // chain knows when it has drained the log. `complete` is true once this page
    // reached the end (fewer than `limit` rows, or no further cursor) — never
    // recompute the head from a single page when `complete` is false (a >limit
    // log would diverge from /root).
    const complete = nextCursor === null;

    res.status(200).json({ ballots, leafCount, nextCursor, complete });
  });

  // GET /root?decisionId= — current chain head + leaf count. -----------------
  router.get("/root", (req, res) => {
    const decisionId = String(req.query.decisionId ?? "");
    if (!repos.decisions.get(decisionId)) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return;
    }
    const head = repos.head.get(decisionId);
    res.status(200).json({
      head: head?.head ?? "",
      leafCount: head?.leafCount ?? 0,
    });
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

  // GET /anchor?decisionId= — Phase-2 anchor view (no chain posting). --------
  router.get("/anchor", (req, res) => {
    const decisionId = String(req.query.decisionId ?? "");
    const row = repos.decisions.get(decisionId);
    if (!row) {
      res.status(404).json({ error: "not-found", code: "NOT_FOUND" });
      return;
    }
    const d = parseDecision(row);
    const head = repos.head.get(decisionId);
    res.status(200).json({
      mode: d.anchorMode,
      head: head?.head ?? "",
      leafCount: head?.leafCount ?? 0,
      status: d.anchorMode === "casual" ? "casual" : "broadcast",
    });
  });

  return router;
}
