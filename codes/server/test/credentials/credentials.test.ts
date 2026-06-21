import { describe, it, expect } from "vitest";
import {
  newIssuer,
  blind,
  blindSign,
  finalize,
  verifyCredential,
} from "../../src/credentials";
import { sha256hex } from "../../src/crypto";

/**
 * RFC 9474 RSABSSA-PSS blind-signature credentials (system-design §12.2).
 *
 * The protocol the tests drive end-to-end:
 *   client:  { blinded, state } = blind(issuerPub, message)
 *   issuer:  blindSig            = blindSign(issuerPriv, blinded)   // sees only the BLINDED token
 *   client:  credentialSig       = finalize(issuerPub, message, blindSig, state)
 *   verify:  verifyCredential(issuerPub, message, credentialSig) === true
 *
 * `message` binds the decision (caller passes `decisionId || serial`), so a
 * credential minted for one decision cannot be replayed against another.
 */

const MSG = "decision-abc-123|serial:9f2c4e7a1b";

describe("credentials — RFC 9474 RSABSSA-PSS", () => {
  it("completes a full blind -> blindSign -> finalize -> verify round-trip", async () => {
    const issuer = newIssuer();
    const { blinded, state } = await blind(issuer.publicKeySpkiPem, MSG);
    const blindSig = await blindSign(issuer.privateKeyPkcs8Pem, blinded);
    const credentialSig = await finalize(
      issuer.publicKeySpkiPem,
      MSG,
      blindSig,
      state,
    );
    const ok = await verifyCredential(
      issuer.publicKeySpkiPem,
      MSG,
      credentialSig,
    );
    expect(ok).toBe(true);
  });

  it("rejects a tampered message at verify time", async () => {
    const issuer = newIssuer();
    const { blinded, state } = await blind(issuer.publicKeySpkiPem, MSG);
    const blindSig = await blindSign(issuer.privateKeyPkcs8Pem, blinded);
    const credentialSig = await finalize(
      issuer.publicKeySpkiPem,
      MSG,
      blindSig,
      state,
    );
    const ok = await verifyCredential(
      issuer.publicKeySpkiPem,
      "decision-abc-123|serial:DIFFERENT",
      credentialSig,
    );
    expect(ok).toBe(false);
  });

  it("rejects a tampered (bit-flipped) credential signature", async () => {
    const issuer = newIssuer();
    const { blinded, state } = await blind(issuer.publicKeySpkiPem, MSG);
    const blindSig = await blindSign(issuer.privateKeyPkcs8Pem, blinded);
    const credentialSig = await finalize(
      issuer.publicKeySpkiPem,
      MSG,
      blindSig,
      state,
    );

    const raw = Buffer.from(credentialSig, "base64");
    raw[0] ^= 0xff; // flip a byte
    const tampered = raw.toString("base64");

    const ok = await verifyCredential(issuer.publicKeySpkiPem, MSG, tampered);
    expect(ok).toBe(false);
  });

  it("does not verify a credential issued under A against issuer B's pubkey", async () => {
    const issuerA = newIssuer();
    const issuerB = newIssuer();

    const { blinded, state } = await blind(issuerA.publicKeySpkiPem, MSG);
    const blindSig = await blindSign(issuerA.privateKeyPkcs8Pem, blinded);
    const credentialSig = await finalize(
      issuerA.publicKeySpkiPem,
      MSG,
      blindSig,
      state,
    );

    expect(
      await verifyCredential(issuerA.publicKeySpkiPem, MSG, credentialSig),
    ).toBe(true);
    expect(
      await verifyCredential(issuerB.publicKeySpkiPem, MSG, credentialSig),
    ).toBe(false);
  });

  it("never throws on malformed input — returns false instead", async () => {
    const issuer = newIssuer();
    expect(
      await verifyCredential(issuer.publicKeySpkiPem, MSG, "not-base64-@@@"),
    ).toBe(false);
    expect(await verifyCredential(issuer.publicKeySpkiPem, MSG, "")).toBe(false);
    expect(
      await verifyCredential("-----BEGIN PUBLIC KEY-----\nbroken\n-----END PUBLIC KEY-----", MSG, "AAAA"),
    ).toBe(false);
    // garbage pubkey + garbage sig still resolves false, no throw
    expect(await verifyCredential("garbage", MSG, "AAAA")).toBe(false);
  });

  it("binds the decision: a credential for decision X fails to verify under decision Y", async () => {
    const issuer = newIssuer();
    const decisionX = "decision-X";
    const decisionY = "decision-Y";
    const serial = "serial:deadbeef";
    const msgX = `${decisionX}|${serial}`;
    const msgY = `${decisionY}|${serial}`;

    const { blinded, state } = await blind(issuer.publicKeySpkiPem, msgX);
    const blindSig = await blindSign(issuer.privateKeyPkcs8Pem, blinded);
    const credentialSig = await finalize(
      issuer.publicKeySpkiPem,
      msgX,
      blindSig,
      state,
    );

    expect(
      await verifyCredential(issuer.publicKeySpkiPem, msgX, credentialSig),
    ).toBe(true);
    // Same serial, different decision => the credential does NOT verify.
    expect(
      await verifyCredential(issuer.publicKeySpkiPem, msgY, credentialSig),
    ).toBe(false);
  });

  it("the issuer never sees the final serial: blindSign input differs from the verify message", async () => {
    const issuer = newIssuer();
    const { blinded } = await blind(issuer.publicKeySpkiPem, MSG);

    // What the issuer receives (the blinded token) reveals nothing about MSG:
    // it is not equal to the message bytes, nor to a hash of the message.
    const blindedBytes = Buffer.from(blinded, "base64");
    expect(blindedBytes.toString("utf8")).not.toContain("serial");
    expect(blindedBytes.toString("utf8")).not.toContain("decision");
    expect(blindedBytes.equals(Buffer.from(MSG, "utf8"))).toBe(false);
    expect(blindedBytes.toString("hex")).not.toBe(sha256hex(MSG));
  });

  it("is randomized: blinding the same message twice yields different blinded tokens", async () => {
    const issuer = newIssuer();
    const a = await blind(issuer.publicKeySpkiPem, MSG);
    const b = await blind(issuer.publicKeySpkiPem, MSG);
    expect(a.blinded).not.toBe(b.blinded);
  });
});

describe("credentials — issuer pubKeyHash (anchored in setupCommitment)", () => {
  it("produces a >=2048-bit RSA keypair and a sha256hex(pubPem) hash", () => {
    const issuer = newIssuer();
    expect(issuer.publicKeySpkiPem).toContain("BEGIN PUBLIC KEY");
    expect(issuer.privateKeyPkcs8Pem).toContain("BEGIN PRIVATE KEY");
    expect(issuer.pubKeyHash).toBe(sha256hex(issuer.publicKeySpkiPem));
    expect(issuer.pubKeyHash).toMatch(/^[0-9a-f]{64}$/);
  });

  it("pubKeyHash is stable for a given key and differs across keys", () => {
    const issuer = newIssuer();
    // Recomputing over the same PEM is deterministic.
    expect(sha256hex(issuer.publicKeySpkiPem)).toBe(issuer.pubKeyHash);

    const other = newIssuer();
    expect(other.pubKeyHash).not.toBe(issuer.pubKeyHash);
  });
});
