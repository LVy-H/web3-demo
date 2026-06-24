import { describe, it, expect } from "vitest";
import { validateSlug, SlugError } from "../src/slug";

describe("validateSlug", () => {
  it("accepts dns-safe slugs", () => {
    expect(() => validateSlug("acme")).not.toThrow();
    expect(() => validateSlug("acme-2")).not.toThrow();
  });
  it("rejects bad shapes", () => {
    for (const bad of ["", "Acme", "a_b", "a.b", "-x", "x ", "a".repeat(41)])
      expect(() => validateSlug(bad), bad).toThrow(SlugError);
  });
  it("rejects reserved slugs", () => {
    for (const r of ["www", "admin", "api", "control", "health", "localhost"])
      expect(() => validateSlug(r), r).toThrow(/reserved/i);
  });
});
