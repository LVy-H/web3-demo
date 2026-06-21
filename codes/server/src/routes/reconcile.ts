import type { Repos } from "../db";
import type { ServerKey } from "../crypto";
import { canonicalize } from "../crypto";
import { parseDecision } from "./decisionView";
import { effectiveClose } from "./effectiveClose";

export interface ReconcileDeps {
  repos: Repos;
  serverKey: ServerKey;
  now: () => number;
}

/**
 * Startup reconcile (§12.5, M2): auto-close every `open` decision whose
 * EFFECTIVE close (latest 'extend' closesAt, else schedule.closesAt) is already
 * past `now()`. Without this, a server that was DOWN past a scheduled close
 * would re-open accepting late ballots until a manual close.
 *
 * Each auto-close appends a signed lifecycle event (open → closed) — the same
 * tamper-evident shape the convener /close route uses — and flips the row state.
 * Idempotent: a decision already closed is skipped.
 *
 * @returns the ids of the decisions that were auto-closed.
 */
export function reconcileExpiredDecisions(deps: ReconcileDeps): string[] {
  const { repos, serverKey } = deps;
  const closed: string[] = [];

  for (const row of repos.decisions.list({ state: "open" })) {
    const d = parseDecision(row);
    const closeAt = effectiveClose(repos.lifecycle.byDecision(d.id), d.schedule);
    if (closeAt === null || deps.now() <= closeAt) continue;

    const timestamp = deps.now();
    const signedSig = serverKey.sign(
      canonicalize({
        decisionId: d.id,
        from: "open",
        to: "closed",
        actor: "system:reconcile",
        timestamp,
      }),
    );
    repos.lifecycle.append({
      decisionId: d.id,
      transition: "closed",
      actor: "system:reconcile",
      ts: timestamp,
      signedSig,
      closesAt: null,
    });
    repos.decisions.setState(d.id, "closed", timestamp);
    closed.push(d.id);
  }

  return closed;
}
