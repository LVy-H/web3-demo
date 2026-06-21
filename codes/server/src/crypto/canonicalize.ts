/**
 * Deterministic JSON serialization for commitment + signing.
 *
 * Guarantees (see system-design §9 — `setupCommitment`, and §11 — verification):
 *  - object keys are sorted lexicographically, recursively, so the output is
 *    identical for structurally-equal values regardless of key insertion order;
 *  - arrays preserve their order (order IS semantically significant);
 *  - no insignificant whitespace;
 *  - non-finite numbers (NaN/Infinity), `undefined`, functions, and symbols are
 *    REJECTED rather than silently coerced to `null` (as `JSON.stringify` would),
 *    because a commitment must never depend on a lossy coercion.
 *
 * Number formatting is delegated to the standard ECMAScript `Number` →
 * shortest-round-trip representation (the same one `JSON.stringify` uses), which
 * is stable: equal numbers always produce equal text.
 */
export function canonicalize(v: unknown): string {
  return encode(v);
}

function encode(v: unknown): string {
  if (v === null) return "null";

  const t = typeof v;

  if (t === "string") return JSON.stringify(v);

  if (t === "boolean") return v ? "true" : "false";

  if (t === "number") {
    if (!Number.isFinite(v as number)) {
      throw new TypeError(
        `canonicalize: non-finite number (${String(v)}) is not representable`,
      );
    }
    // Normalizes -0 to "0" and uses the shortest round-trip form.
    return JSON.stringify(v);
  }

  if (t === "bigint") {
    throw new TypeError("canonicalize: bigint is not supported");
  }

  if (t === "undefined") {
    throw new TypeError("canonicalize: undefined is not representable");
  }

  if (t === "function" || t === "symbol") {
    throw new TypeError(`canonicalize: ${t} is not representable`);
  }

  if (Array.isArray(v)) {
    return "[" + v.map((el) => encode(el)).join(",") + "]";
  }

  if (t === "object") {
    const obj = v as Record<string, unknown>;
    const keys = Object.keys(obj).sort();
    const parts: string[] = [];
    for (const k of keys) {
      const val = obj[k];
      // Object entries whose value is `undefined` are normally dropped by
      // JSON.stringify; for a commitment we reject them so the input is explicit.
      if (val === undefined) {
        throw new TypeError(
          `canonicalize: undefined value at key "${k}" is not representable`,
        );
      }
      parts.push(JSON.stringify(k) + ":" + encode(val));
    }
    return "{" + parts.join(",") + "}";
  }

  throw new TypeError(`canonicalize: unsupported value type "${t}"`);
}
