import {
  generateKeyPairSync,
  sign as edSign,
  verify as edVerify,
  createPublicKey,
  createPrivateKey,
  type KeyObject,
} from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { sha256hex } from "./hash";

const PRIVATE_PEM = "server-ed25519-key.pem";
const PUBLIC_PEM = "server-ed25519-key.pub.pem";

export interface ServerKey {
  /** SPKI public key in PEM form (the value committed/advertised to verifiers). */
  publicKeyPem: string;
  /** Short, stable identifier: sha256hex(publicKeyPem).slice(0,16). */
  keyId: string;
  /** Detached Ed25519 signature over utf8(msg), base64-encoded. */
  sign(msg: string): string;
}

/**
 * Load the server's Ed25519 signing key from `dir`, creating + persisting it on
 * first use. Subsequent calls with the same `dir` return the identical key
 * (same publicKeyPem / keyId), so the server's signing identity is stable across
 * restarts (system-design §12.3 — the server signs receipts / lifecycle events /
 * checkpoint roots).
 */
export function loadOrCreateServerKey(dir: string): ServerKey {
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }

  const privPath = join(dir, PRIVATE_PEM);
  const pubPath = join(dir, PUBLIC_PEM);

  let privateKey: KeyObject;
  let publicKeyPem: string;

  if (existsSync(privPath)) {
    const pem = readFileSync(privPath, "utf8");
    privateKey = createPrivateKey(pem);
    // Derive the public PEM from the private key so it is always consistent,
    // even if the .pub.pem on disk were missing or stale.
    publicKeyPem = createPublicKey(privateKey)
      .export({ type: "spki", format: "pem" })
      .toString();
    // Heal a missing public sidecar.
    if (!existsSync(pubPath)) {
      writeFileSync(pubPath, publicKeyPem, { mode: 0o644 });
    }
  } else {
    const pair = generateKeyPairSync("ed25519");
    privateKey = pair.privateKey;
    const privPem = privateKey
      .export({ type: "pkcs8", format: "pem" })
      .toString();
    publicKeyPem = pair.publicKey
      .export({ type: "spki", format: "pem" })
      .toString();
    // Private key gets restrictive permissions; it is the server's secret.
    writeFileSync(privPath, privPem, { mode: 0o600 });
    writeFileSync(pubPath, publicKeyPem, { mode: 0o644 });
  }

  const keyId = sha256hex(publicKeyPem).slice(0, 16);

  return {
    publicKeyPem,
    keyId,
    sign(msg: string): string {
      // Ed25519 in node:crypto: pass `null` as the algorithm (the digest is
      // intrinsic to the scheme), sign the raw utf8 bytes.
      const sig = edSign(null, Buffer.from(msg, "utf8"), privateKey);
      return sig.toString("base64");
    },
  };
}

/**
 * Verify a base64 detached Ed25519 signature over utf8(msg). Returns `false`
 * (never throws) on malformed input — a verification failure, not a crash, is
 * the correct outcome for an attacker-controlled signature.
 */
export function verifySig(
  publicKeyPem: string,
  msg: string,
  sigB64: string,
): boolean {
  try {
    const pub = createPublicKey(publicKeyPem);
    const sig = Buffer.from(sigB64, "base64");
    // Ed25519 signatures are exactly 64 bytes; reject anything else early so a
    // truncated/garbage base64 string can't reach the verifier.
    if (sig.length !== 64) return false;
    return edVerify(null, Buffer.from(msg, "utf8"), pub, sig);
  } catch {
    return false;
  }
}
