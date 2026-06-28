import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync, existsSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  loadOrCreateServerKey,
  verifySig,
  sha256hex,
} from "../../src/crypto";

let dir: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "tessera-key-"));
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("loadOrCreateServerKey", () => {
  it("creates an Ed25519 key and exposes a PEM public key + keyId", () => {
    const k = loadOrCreateServerKey(dir);
    expect(k.publicKeyPem).toContain("BEGIN PUBLIC KEY");
    expect(k.keyId).toMatch(/^[0-9a-f]{16}$/);
  });

  it("derives keyId as sha256hex(publicKeyPem).slice(0,16)", () => {
    const k = loadOrCreateServerKey(dir);
    expect(k.keyId).toBe(sha256hex(k.publicKeyPem).slice(0, 16));
  });

  it("persists the private + public PEM to disk", () => {
    loadOrCreateServerKey(dir);
    const files = readdirSync(dir);
    expect(files.some((f) => f.endsWith(".pem"))).toBe(true);
    expect(existsSync(join(dir, "server-ed25519-key.pem"))).toBe(true);
    expect(existsSync(join(dir, "server-ed25519-key.pub.pem"))).toBe(true);
  });

  it("returns the SAME publicKeyPem and keyId on a second call (load, not regenerate)", () => {
    const first = loadOrCreateServerKey(dir);
    const second = loadOrCreateServerKey(dir);
    expect(second.publicKeyPem).toBe(first.publicKeyPem);
    expect(second.keyId).toBe(first.keyId);
  });

  it("a signature from the reloaded key verifies under the original public key", () => {
    const first = loadOrCreateServerKey(dir);
    const second = loadOrCreateServerKey(dir);
    const sig = second.sign("reload-test");
    expect(verifySig(first.publicKeyPem, "reload-test", sig)).toBe(true);
  });

  it("produces a base64 detached signature", () => {
    const k = loadOrCreateServerKey(dir);
    const sig = k.sign("hello");
    expect(sig).toMatch(/^[A-Za-z0-9+/]+={0,2}$/);
    // Ed25519 signature is 64 bytes → 88 base64 chars (with padding)
    expect(Buffer.from(sig, "base64").length).toBe(64);
  });

  it("different dirs yield different keys", () => {
    const a = loadOrCreateServerKey(dir);
    const other = mkdtempSync(join(tmpdir(), "tessera-key-"));
    try {
      const b = loadOrCreateServerKey(other);
      expect(b.publicKeyPem).not.toBe(a.publicKeyPem);
      expect(b.keyId).not.toBe(a.keyId);
    } finally {
      rmSync(other, { recursive: true, force: true });
    }
  });
});

describe("sign / verifySig (Ed25519 roundtrip)", () => {
  it("verifies a genuine signature", () => {
    const k = loadOrCreateServerKey(dir);
    const sig = k.sign("the message");
    expect(verifySig(k.publicKeyPem, "the message", sig)).toBe(true);
  });

  it("rejects a tampered message", () => {
    const k = loadOrCreateServerKey(dir);
    const sig = k.sign("the message");
    expect(verifySig(k.publicKeyPem, "the messagE", sig)).toBe(false);
  });

  it("rejects a tampered signature", () => {
    const k = loadOrCreateServerKey(dir);
    const sig = k.sign("the message");
    const raw = Buffer.from(sig, "base64");
    raw[0] ^= 0xff;
    const tampered = raw.toString("base64");
    expect(verifySig(k.publicKeyPem, "the message", tampered)).toBe(false);
  });

  it("rejects a signature under a different key's public key", () => {
    const k = loadOrCreateServerKey(dir);
    const other = mkdtempSync(join(tmpdir(), "tessera-key-"));
    try {
      const k2 = loadOrCreateServerKey(other);
      const sig = k.sign("the message");
      expect(verifySig(k2.publicKeyPem, "the message", sig)).toBe(false);
    } finally {
      rmSync(other, { recursive: true, force: true });
    }
  });

  it("returns false (does not throw) on a malformed signature", () => {
    const k = loadOrCreateServerKey(dir);
    expect(verifySig(k.publicKeyPem, "msg", "not-base64-@@@")).toBe(false);
    expect(verifySig(k.publicKeyPem, "msg", "")).toBe(false);
  });

  it("signs utf8 bytes (multibyte messages roundtrip)", () => {
    const k = loadOrCreateServerKey(dir);
    const msg = "héllo — 世界 🗳";
    const sig = k.sign(msg);
    expect(verifySig(k.publicKeyPem, msg, sig)).toBe(true);
  });
});
