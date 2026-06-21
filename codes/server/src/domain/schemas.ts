// Tessera domain — zod request/payload schemas (§3 C1/C-rules, §9, §10).
//
// Two public surfaces:
//   • DecisionCreateSchema      — validates `POST /decisions` input.
//   • ballotPayloadSchema(method, optionCount?) — validates the canonical
//     BallotPayload union AND that payload.kind is valid for `method`
//     (or 'abstain', which is always allowed, §3 P4).
//
// No I/O, no db. The TS source of truth for the entity types is ./types.ts;
// these schemas mirror that shape for runtime validation.

import { z } from "zod";
import type { Method } from "./types";

// ---------------------------------------------------------------------------
// Shared primitives
// ---------------------------------------------------------------------------

/** A non-negative integer option index. */
const optionIndex = z.number().int().nonnegative();

const methodEnum = z.enum([
  "single",
  "approval",
  "ranked",
  "quadratic",
  "survey",
]);

const ballotModeEnum = z.enum(["open", "secret"]);
const resultsPolicyEnum = z.enum(["sealed", "live"]);
const anchorModeEnum = z.enum(["casual", "broadcast", "chain"]);
const visibilityEnum = z.enum(["listed", "link-only"]);
const eligibilityMethodEnum = z.enum(["open", "passcode", "domain", "invite"]);
const thresholdKindEnum = z.enum(["plurality", "majority", "supermajority"]);
const tieBreakEnum = z.enum(["declare", "runoff", "casting", "random-seed"]);

// ---------------------------------------------------------------------------
// DecisionCreateSchema (§3 C1/C-rules)
// ---------------------------------------------------------------------------

const thresholdSchema = z.object({
  kind: thresholdKindEnum,
  percent: z.number().min(0).max(100).optional(),
});

const ruleSchema = z.object({
  threshold: thresholdSchema,
  quorum: z.number().int().nonnegative().optional(),
  tieBreak: tieBreakEnum,
});

const scheduleSchema = z.object({
  opensAt: z.number().int().optional(),
  closesAt: z.number().int().optional(),
});

// Eligibility: discriminated on `method` but the extra per-method fields
// (passcode, domain, ...) are tolerated. Unknown methods are rejected by the
// enum; unknown extra keys pass through (the route layer reads what it needs).
const eligibilitySchema = z
  .object({ method: eligibilityMethodEnum })
  .passthrough();

export const DecisionCreateSchema = z.object({
  title: z.string().min(1),
  options: z.array(z.string()).min(2),
  method: methodEnum,
  ballotMode: ballotModeEnum,
  resultsPolicy: resultsPolicyEnum,
  eligibility: eligibilitySchema,
  rule: ruleSchema,
  schedule: scheduleSchema,
  visibility: visibilityEnum,
  anchorMode: anchorModeEnum,
  maxParticipants: z.number().int().positive().optional(),
});

/** Inferred input type for `POST /decisions`. */
export type DecisionCreateInput = z.infer<typeof DecisionCreateSchema>;

// ---------------------------------------------------------------------------
// ballotPayloadSchema(method, optionCount?)
// ---------------------------------------------------------------------------

/** The 'abstain' member — valid for every method (§3 P4). */
const abstainSchema = z.object({ kind: z.literal("abstain") }).strict();

/**
 * Build a zod schema validating a {@link BallotPayload} for a given `method`.
 *
 * - The payload's `kind` must be the one matching `method`, OR 'abstain'.
 * - All option indices must be non-negative integers.
 * - When `optionCount` is supplied, indices are range-checked into
 *   `[0, optionCount)` and a quadratic payload's `credits` length must equal
 *   `optionCount` (one credit slot per option).
 */
export function ballotPayloadSchema(
  method: Method,
  optionCount?: number,
): z.ZodType {
  const hasCount = typeof optionCount === "number";

  // Index validator: non-negative int, optionally bounded above by optionCount.
  const index = hasCount
    ? optionIndex.max(optionCount! - 1)
    : optionIndex;

  let variant: z.ZodType;

  switch (method) {
    case "single":
      variant = z.object({ kind: z.literal("single"), choice: index }).strict();
      break;
    case "approval":
      variant = z
        .object({ kind: z.literal("approval"), choices: z.array(index) })
        .strict();
      break;
    case "ranked":
      variant = z
        .object({ kind: z.literal("ranked"), ranking: z.array(index) })
        .strict();
      break;
    case "quadratic": {
      // Payload carries the votes vector directly (votes[i] = votes for option i,
      // non-negative int; cost Σvᵢ² ≤ budget is the cast-time validity check).
      let votes = z.array(optionIndex);
      if (hasCount) {
        // One vote slot per option.
        votes = votes.length(optionCount!);
      }
      variant = z
        .object({ kind: z.literal("quadratic"), votes })
        .strict();
      break;
    }
    case "survey":
      variant = z
        .object({ kind: z.literal("survey"), choices: z.array(index) })
        .strict();
      break;
    default: {
      // Exhaustiveness guard — unreachable for a well-typed Method.
      const _never: never = method;
      throw new Error(`Unknown method: ${String(_never)}`);
    }
  }

  // 'abstain' is always acceptable alongside the method's own variant.
  return z.union([variant, abstainSchema]);
}
