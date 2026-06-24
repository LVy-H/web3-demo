export class SlugError extends Error {
  constructor(msg: string) { super(msg); this.name = "SlugError"; }
}
export const RESERVED_SLUGS: ReadonlySet<string> = new Set([
  "www", "admin", "api", "control", "health", "localhost",
]);
const SLUG_RE = /^[a-z0-9-]{1,40}$/;
export function validateSlug(s: string): void {
  if (!SLUG_RE.test(s)) throw new SlugError(`invalid slug '${s}' (use ^[a-z0-9-]{1,40}$)`);
  if (s.startsWith("-") || s.endsWith("-")) throw new SlugError(`slug '${s}' may not start/end with '-'`);
  if (RESERVED_SLUGS.has(s)) throw new SlugError(`slug '${s}' is reserved`);
}
