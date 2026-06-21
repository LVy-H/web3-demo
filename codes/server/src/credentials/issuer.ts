import { generateKeyPairSync } from "node:crypto";
import { sha256hex } from "../crypto/hash";

/**
 * A per-decision blind-signature issuer (system-design §12.2).
 *
 * One fresh RSA keypair is minted for a single decision. `pubKeyHash` is folded
 * into that decision's `setupCommitment` (and anchored before registration), so
 * the host cannot swap signing keys after setup — every credential a verifier
 * later checks must verify under *this* anchored pubkey (§6, §11.1).
 *
 * Per-decision keys also contain leakage: compromising one decision's issuer key
 * tells an attacker nothing about any other decision.
 */
export interface Issuer {
  /** SPKI public key (PEM). The value hashed into `setupCommitment` and advertised to verifiers. */
  publicKeySpkiPem: string;
  /** PKCS#8 private key (PEM). The issuer's secret; only `blindSign` ever touches it. */
  privateKeyPkcs8Pem: string;
  /** `sha256hex(publicKeySpkiPem)` — the stable, anchorable key commitment. */
  pubKeyHash: string;
}

/**
 * RSA modulus length for issuer keys. RFC 9474 RSABSSA requires >= 2048; 2048 is
 * the floor and keeps blind-sign latency reasonable for the registration path.
 */
const MODULUS_LENGTH = 2048;

/**
 * Mint a fresh per-decision issuer keypair.
 *
 * The keypair is a plain RSA key (no hash baked in) exported as PEM. The blind
 * protocol applies RSA-PSS with SHA-384 at sign/verify time (see `blindrsa.ts`);
 * RSA keys are algorithm-agnostic, so the same PEM serves both. `pubKeyHash` is
 * computed over the exact PEM string the verifier will recompute, so the hash is
 * reproducible from published metadata.
 */
export function newIssuer(): Issuer {
  const { publicKey, privateKey } = generateKeyPairSync("rsa", {
    modulusLength: MODULUS_LENGTH,
    publicExponent: 0x10001,
  });

  const publicKeySpkiPem = publicKey
    .export({ type: "spki", format: "pem" })
    .toString();
  const privateKeyPkcs8Pem = privateKey
    .export({ type: "pkcs8", format: "pem" })
    .toString();

  return {
    publicKeySpkiPem,
    privateKeyPkcs8Pem,
    pubKeyHash: sha256hex(publicKeySpkiPem),
  };
}
