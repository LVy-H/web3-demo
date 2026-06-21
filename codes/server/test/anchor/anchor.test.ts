import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { merkleRoot } from "../../src/merkle";
import {
  canonicalize,
  loadOrCreateServerKey,
  verifySig,
  type ServerKey,
} from "../../src/crypto";
import {
  buildCheckpoint,
  verifyCheckpointSig,
  anchorFor,
  ChainAnchorNotImplemented,
  type Checkpoint,
} from "../../src/anchor";

/**
 * Anchor + checkpoint module (system-design §11 checkpoints, §12.1 anchor).
 *
 * The contract under test is the *signed-root payload*: the server signs
 * `canonicalize({ root, treeSize, decisionId })` and a verifier must recompute
 * the exact same canonical string to validate the signature. These tests pin
 * that payload and the three anchor modes (broadcast / casual / chain).
 */

// A few ballotHash leaves (whole-byte hex), in logSeq order.
const LEAVES = [
  "aa",
  "bbbb",
  "00ff00ff",
  "deadbeefdeadbeefdeadbeefdeadbeef",
];
const DECISION_ID = "decision-42";

let tmp: string;
let key: ServerKey;
let otherKey: ServerKey;

beforeAll(() => {
  tmp = mkdtempSync(join(tmpdir(), "tessera-anchor-"));
  key = loadOrCreateServerKey(join(tmp, "primary"));
  otherKey = loadOrCreateServerKey(join(tmp, "attacker"));
});

afterAll(() => {
  rmSync(tmp, { recursive: true, force: true });
});

function honestCheckpoint(leaves = LEAVES): Checkpoint {
  return buildCheckpoint({
    decisionId: DECISION_ID,
    leaves,
    prevRoot: null,
    sign: key.sign,
  });
}

describe("buildCheckpoint", () => {
  it("computes root == merkleRoot(leaves) and treeSize == leaves.length", () => {
    const cp = honestCheckpoint();
    expect(cp.root).toBe(merkleRoot(LEAVES));
    expect(cp.treeSize).toBe(LEAVES.length);
    expect(cp.decisionId).toBe(DECISION_ID);
    expect(cp.prevRoot).toBeNull();
    expect(cp.status).toBe("built");
  });

  it("carries prevRoot through for an interim->final chain", () => {
    const prev = honestCheckpoint(LEAVES.slice(0, 2));
    const cp = buildCheckpoint({
      decisionId: DECISION_ID,
      leaves: LEAVES,
      prevRoot: prev.root,
      sign: key.sign,
    });
    expect(cp.prevRoot).toBe(prev.root);
  });

  it("signs EXACTLY canonicalize({ root, treeSize, decisionId })", () => {
    const cp = honestCheckpoint();
    const payload = canonicalize({
      root: cp.root,
      treeSize: cp.treeSize,
      decisionId: cp.decisionId,
    });
    // The signature on the checkpoint must verify against that exact payload.
    expect(verifySig(key.publicKeyPem, payload, cp.signedRoot)).toBe(true);
  });

  it("handles the empty tree (treeSize 0, still signs the empty root)", () => {
    const cp = buildCheckpoint({
      decisionId: DECISION_ID,
      leaves: [],
      prevRoot: null,
      sign: key.sign,
    });
    expect(cp.treeSize).toBe(0);
    expect(cp.root).toBe(merkleRoot([]));
    expect(verifyCheckpointSig(key.publicKeyPem, cp)).toBe(true);
  });
});

describe("verifyCheckpointSig", () => {
  it("is true for an honestly-signed checkpoint", () => {
    const cp = honestCheckpoint();
    expect(verifyCheckpointSig(key.publicKeyPem, cp)).toBe(true);
  });

  it("is false when the root is tampered", () => {
    const cp = honestCheckpoint();
    const forged: Checkpoint = { ...cp, root: merkleRoot(LEAVES.slice(0, 3)) };
    expect(verifyCheckpointSig(key.publicKeyPem, forged)).toBe(false);
  });

  it("is false when treeSize is tampered", () => {
    const cp = honestCheckpoint();
    const forged: Checkpoint = { ...cp, treeSize: cp.treeSize + 1 };
    expect(verifyCheckpointSig(key.publicKeyPem, forged)).toBe(false);
  });

  it("is false when decisionId is tampered", () => {
    const cp = honestCheckpoint();
    const forged: Checkpoint = { ...cp, decisionId: "decision-99" };
    expect(verifyCheckpointSig(key.publicKeyPem, forged)).toBe(false);
  });

  it("is false when signed by a different key", () => {
    const cp = buildCheckpoint({
      decisionId: DECISION_ID,
      leaves: LEAVES,
      prevRoot: null,
      sign: otherKey.sign,
    });
    // honest payload, but the wrong server pubkey verifying it
    expect(verifyCheckpointSig(key.publicKeyPem, cp)).toBe(false);
  });

  it("never throws on malformed input", () => {
    const cp = honestCheckpoint();
    expect(verifyCheckpointSig("not-a-pem", cp)).toBe(false);
    expect(
      verifyCheckpointSig(key.publicKeyPem, {
        ...cp,
        signedRoot: "@@notbase64@@",
      }),
    ).toBe(false);
    // @ts-expect-error — exercise a structurally-broken checkpoint
    expect(verifyCheckpointSig(key.publicKeyPem, null)).toBe(false);
  });
});

describe("anchor — broadcast mode (default, zero-wallet)", () => {
  it("returns a distributable bundle carrying the signed final root", () => {
    const cp = honestCheckpoint();
    const anchor = anchorFor("broadcast");
    const bundle = anchor.anchor(cp);
    expect(bundle).toEqual({
      mode: "broadcast",
      root: cp.root,
      treeSize: cp.treeSize,
      signedRoot: cp.signedRoot,
    });
    // Narrow the discriminated union before touching mode-specific fields.
    expect(bundle.mode).toBe("broadcast");
    if (bundle.mode !== "broadcast") throw new Error("expected broadcast bundle");
    // The distributed signed root verifies for a holder (tamper-evident).
    expect(
      verifySig(
        key.publicKeyPem,
        canonicalize({
          root: bundle.root,
          treeSize: bundle.treeSize,
          decisionId: cp.decisionId,
        }),
        bundle.signedRoot,
      ),
    ).toBe(true);
  });

  it("reports status 'broadcast'", () => {
    const anchor = anchorFor("broadcast");
    expect(anchor.status()).toBe("broadcast");
  });

  it("is the default mode when none is given", () => {
    const cp = honestCheckpoint();
    const bundle = anchorFor().anchor(cp);
    expect(bundle.mode).toBe("broadcast");
    if (bundle.mode !== "broadcast") throw new Error("expected broadcast bundle");
    expect(bundle.signedRoot).toBe(cp.signedRoot);
  });
});

describe("anchor — casual mode (trust-the-host, no signed distribution)", () => {
  it("omits the signature and reports status 'casual'", () => {
    const cp = honestCheckpoint();
    const anchor = anchorFor("casual");
    const bundle = anchor.anchor(cp);
    expect(bundle).toEqual({
      mode: "casual",
      root: cp.root,
      treeSize: cp.treeSize,
    });
    expect("signedRoot" in bundle).toBe(false);
    expect(anchor.status()).toBe("casual");
  });
});

describe("anchor — chain mode (stub seam, post-1.0)", () => {
  it("records status 'queued' without submitting", () => {
    const cp = honestCheckpoint();
    const anchor = anchorFor("chain");
    const bundle = anchor.anchor(cp);
    expect(bundle).toEqual({ mode: "chain", status: "queued" });
    expect(anchor.status()).toBe("queued");
  });

  it("throws the typed ChainAnchorNotImplemented on submit", () => {
    const cp = honestCheckpoint();
    const anchor = anchorFor("chain");
    expect(() => anchor.submit(cp)).toThrow(ChainAnchorNotImplemented);
    try {
      anchor.submit(cp);
      throw new Error("should have thrown");
    } catch (e) {
      expect(e).toBeInstanceOf(ChainAnchorNotImplemented);
      expect((e as Error).name).toBe("ChainAnchorNotImplemented");
    }
  });
});

describe("anchor — unknown mode", () => {
  it("rejects an unsupported mode", () => {
    // @ts-expect-error — exercise the runtime guard
    expect(() => anchorFor("ipfs")).toThrow();
  });
});
