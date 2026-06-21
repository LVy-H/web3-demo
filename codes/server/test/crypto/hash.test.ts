import { describe, it, expect } from "vitest";
import { createHash } from "node:crypto";
import { sha256hex } from "../../src/crypto";

describe("sha256hex", () => {
  it("matches the known SHA-256 vector for the empty string", () => {
    expect(sha256hex("")).toBe(
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    );
  });

  it("matches the known SHA-256 vector for 'abc'", () => {
    expect(sha256hex("abc")).toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
  });

  it("returns a 64-char lowercase hex string", () => {
    const h = sha256hex("tessera");
    expect(h).toMatch(/^[0-9a-f]{64}$/);
  });

  it("hashes a Buffer identically to its utf8 string", () => {
    expect(sha256hex(Buffer.from("héllo", "utf8"))).toBe(sha256hex("héllo"));
  });

  it("agrees with node:crypto for arbitrary input", () => {
    const s = "the quick brown fox";
    const expected = createHash("sha256").update(s, "utf8").digest("hex");
    expect(sha256hex(s)).toBe(expected);
  });

  it("is deterministic", () => {
    expect(sha256hex("repeat")).toBe(sha256hex("repeat"));
  });
});
