import type { LifecycleEvent } from "../db";
import type { Schedule } from "../domain";

/**
 * The EFFECTIVE close time of a decision (M2 / §12.5).
 *
 * Precedence: the latest `extend` amendment's `closesAt` overrides the decision
 * schedule's `closesAt`. "Latest" is the highest `ts` among 'extend' events
 * (the lifecycle log is appended in `ts` order). Returns `null` when neither a
 * schedule close nor any extend exists (manual-close only — never auto-late).
 *
 * @param events   the decision's lifecycle events (any order).
 * @param schedule the decision's parsed schedule.
 */
export function effectiveClose(
  events: readonly LifecycleEvent[],
  schedule: Schedule,
): number | null {
  let latestExtend: LifecycleEvent | null = null;
  for (const e of events) {
    if (e.transition === "extend" && typeof e.closesAt === "number") {
      if (latestExtend === null || e.ts > latestExtend.ts) {
        latestExtend = e;
      }
    }
  }
  if (latestExtend !== null) {
    return latestExtend.closesAt as number;
  }
  return typeof schedule.closesAt === "number" ? schedule.closesAt : null;
}
