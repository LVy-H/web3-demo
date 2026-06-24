import { describe, it, expect } from "vitest";
import { fingerprintOfPem, fetchFingerprint } from "../../src/orchestrator/fingerprint";

describe("fingerprint", () => {
  it("hashes the PEM string deterministically", () => {
    const fp = fingerprintOfPem("-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----\n");
    expect(fp).toMatch(/^[0-9a-f]{64}$/);
    expect(fingerprintOfPem("x")).not.toBe(fp);
  });
  it("fetchFingerprint reads serverPubKeyPem from /key", async () => {
    const fakeFetch = (async (url: string) => {
      expect(url).toBe("http://inst:3001/key");
      return { ok: true, json: async () => ({ serverPubKeyPem: "PEMDATA" }) } as Response;
    }) as unknown as typeof fetch;
    expect(await fetchFingerprint("http://inst:3001", fakeFetch)).toBe(fingerprintOfPem("PEMDATA"));
  });
});
