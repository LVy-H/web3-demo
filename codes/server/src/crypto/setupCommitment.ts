import { canonicalize } from "./canonicalize";
import { sha256hex } from "./hash";

/**
 * The inputs to the §9 `setupCommitment`. These are exactly the fields the
 * verifier recomputes from a decision's anchored metadata (system-design §11.1).
 *
 * `issuerPubKeyHash` is the hash of the per-decision blind-signature issuer
 * public key (§12.2). Phase 2 ships open-ballot only — there is no issuer — so
 * it is `null` (or omitted, which is treated identically).
 *
 * The remaining shapes (`rule`, `schedule`, …) are intentionally loose here:
 * the canonical serializer only needs them to be JSON-representable, and the
 * authoritative per-field schemas live in the domain module. The commitment is
 * defined purely structurally so it stays stable across modules.
 */
export interface SetupParts {
  options: unknown;
  method: unknown;
  rule: unknown;
  ballotMode: unknown;
  resultsPolicy: unknown;
  rosterCommitment: unknown;
  issuerPubKeyHash?: string | null;
  schedule: unknown;
}

/**
 * setupCommitment = sha256hex(canonicalize([ options, method, rule, ballotMode,
 *   resultsPolicy, rosterCommitment, issuerPubKeyHash ?? null, schedule ]))
 *
 * An ARRAY (not an object) fixes the field order to the §9 preimage order, so
 * the commitment is independent of how the parts object was constructed while
 * remaining sensitive to every value.
 */
export function computeSetupCommitment(parts: SetupParts): string {
  const preimage = [
    parts.options,
    parts.method,
    parts.rule,
    parts.ballotMode,
    parts.resultsPolicy,
    parts.rosterCommitment,
    parts.issuerPubKeyHash ?? null,
    parts.schedule,
  ];
  return sha256hex(canonicalize(preimage));
}
