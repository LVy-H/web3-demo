import {
  webcrypto,
  createPublicKey,
  createPrivateKey,
} from "node:crypto";

/**
 * Thin bridge to the vetted RFC 9474 RSABSSA-PSS implementation
 * `@cloudflare/blindrsa-ts` (Apache-2.0). We do NOT hand-roll the blinding math:
 * this file only (a) loads the ESM-only library from our CommonJS build and
 * (b) converts between the PEM keys the rest of the server stores and the
 * WebCrypto `CryptoKey` objects the library consumes. The cryptography lives
 * entirely inside the library.
 *
 * Suite: RSABSSA-SHA384-PSS-Randomized — the randomized PSS variant called for
 * by system-design §12.2 (RFC 9474 §5; randomization strengthens unlinkability).
 */

// ---------------------------------------------------------------------------
// ESM interop. `@cloudflare/blindrsa-ts` is published as pure ESM
// (`"type": "module"`). The server compiles to CommonJS (tsconfig
// `module: "CommonJS"`), under which TypeScript rewrites this `await import(...)`
// into `Promise.resolve().then(() => require(...))`. That is exactly what we
// want: Node >= 22.12 / >= 23 supports `require()` of a *synchronous* ESM module
// (this library has no top-level await), so the compiled CommonJS build loads it
// cleanly; and vitest's transform wires the dynamic import's module callback so
// the same source loads under test too. We do this lazily (and memoize) so the
// ESM load happens off the hot path and only once per process.
// ---------------------------------------------------------------------------
type BlindRsaModule = typeof import("@cloudflare/blindrsa-ts");

let suitePromise:
  | Promise<ReturnType<BlindRsaModule["RSABSSA"]["SHA384"]["PSS"]["Randomized"]>>
  | undefined;

/**
 * Lazily load the library and instantiate the randomized SHA-384 PSS suite once.
 * `supportsRSARAW: false` keeps us on the pure WebCrypto path (no platform RSA
 * raw primitive), which is portable across Node versions.
 */
function getSuite() {
  if (!suitePromise) {
    suitePromise = import("@cloudflare/blindrsa-ts").then((mod) =>
      mod.RSABSSA.SHA384.PSS.Randomized({ supportsRSARAW: false }),
    );
  }
  return suitePromise;
}

const RSA_PSS_SHA384 = { name: "RSA-PSS", hash: "SHA-384" } as const;

/**
 * Randomizer length (bytes) prepended by the randomized PSS variant's
 * `prepare()` — RFC 9474 §4.1 fixes this at 32. Because the randomizer is part
 * of the message that gets signed, the *verifier* needs the exact same
 * randomizer; we therefore ship it inside the credential signature (see
 * {@link finalize} / {@link verifyCredential}) so the public API can keep
 * working in terms of the original, randomizer-free `message`.
 */
const RANDOMIZER_LEN = 32;

/**
 * WebCrypto key handle. We source the type from `node:crypto`'s webcrypto rather
 * than the DOM lib (the server's tsconfig `lib` is ES2022 only, with no `dom`),
 * so the build needs no DOM types.
 */
type WebCryptoKey = Awaited<
  ReturnType<typeof webcrypto.subtle.importKey>
>;

/** Import an SPKI PEM public key as a WebCrypto RSA-PSS verify key. */
async function importPublicKey(spkiPem: string): Promise<WebCryptoKey> {
  const der = createPublicKey(spkiPem).export({ type: "spki", format: "der" });
  return webcrypto.subtle.importKey(
    "spki",
    der,
    RSA_PSS_SHA384,
    true,
    ["verify"],
  );
}

/** Import a PKCS#8 PEM private key as a WebCrypto RSA-PSS sign key. */
async function importPrivateKey(pkcs8Pem: string): Promise<WebCryptoKey> {
  const der = createPrivateKey(pkcs8Pem).export({
    type: "pkcs8",
    format: "der",
  });
  return webcrypto.subtle.importKey(
    "pkcs8",
    der,
    RSA_PSS_SHA384,
    true,
    ["sign"],
  );
}

/** UTF-8 / Buffer message -> Uint8Array (the library's byte type). */
function toBytes(message: string | Uint8Array): Uint8Array {
  return typeof message === "string"
    ? new TextEncoder().encode(message)
    : message;
}

/**
 * Opaque client-side blinding state produced by {@link blind} and consumed by
 * {@link finalize}. Holds the prepared (randomized) message and the blinding
 * inverse `inv`; both are base64-encoded so the state can cross a wire / be
 * stashed by a client between the two round-trip legs.
 */
export interface BlindState {
  /** The prepared message bytes (randomizer-prefixed), base64. */
  prepared: string;
  /** The blinding inverse `inv`, base64. */
  inv: string;
}

/**
 * Client step 1. Blind `message` under the issuer's public key.
 * Returns the blinded token to hand to the issuer plus the opaque {@link BlindState}
 * needed to later unblind the issuer's response.
 */
export async function blind(
  publicKeySpkiPem: string,
  message: string | Uint8Array,
): Promise<{ blinded: string; state: BlindState }> {
  const suite = await getSuite();
  const pub = await importPublicKey(publicKeySpkiPem);
  const prepared = suite.prepare(toBytes(message));
  const { blindedMsg, inv } = await suite.blind(pub, prepared);
  return {
    blinded: Buffer.from(blindedMsg).toString("base64"),
    state: {
      prepared: Buffer.from(prepared).toString("base64"),
      inv: Buffer.from(inv).toString("base64"),
    },
  };
}

/**
 * Issuer step. Blind-sign a blinded token with the issuer's private key.
 * The issuer sees only the blinded bytes — never the prepared/final message —
 * so issuance cannot be linked to the eventual credential. Returns base64.
 */
export async function blindSign(
  privateKeyPkcs8Pem: string,
  blinded: string,
): Promise<string> {
  const suite = await getSuite();
  const priv = await importPrivateKey(privateKeyPkcs8Pem);
  const blindSig = await suite.blindSign(
    priv,
    new Uint8Array(Buffer.from(blinded, "base64")),
  );
  return Buffer.from(blindSig).toString("base64");
}

/**
 * Client step 2. Unblind the issuer's blind signature into a final, *self-
 * contained* credential signature over `message`, using the {@link BlindState}
 * from {@link blind}. `message` MUST be byte-identical to the one passed to
 * {@link blind}.
 *
 * Returned credential layout: `base64( randomizer(32) ‖ rawSignature )`. The
 * randomizer is the prefix `prepare()` prepended at blind time; the raw RSA
 * signature was produced over `randomizer ‖ message`. Carrying the randomizer
 * in the credential lets {@link verifyCredential} verify against just the
 * caller's original `message` (the cast only ever passes `(serial, sig)`).
 */
export async function finalize(
  publicKeySpkiPem: string,
  message: string | Uint8Array,
  blindSig: string,
  state: BlindState,
): Promise<string> {
  const suite = await getSuite();
  const pub = await importPublicKey(publicKeySpkiPem);
  // The library signs/verifies the PREPARED message (randomizer ‖ message).
  const prepared = new Uint8Array(Buffer.from(state.prepared, "base64"));
  // Defensive binding check: the state's prepared bytes must be
  // `randomizer ‖ message` for the `message` the caller claims to be finalizing,
  // so a client cannot blind one message then finalize as another.
  const msgBytes = Buffer.from(toBytes(message));
  const preparedTail = Buffer.from(prepared.subarray(RANDOMIZER_LEN));
  if (!preparedTail.equals(msgBytes)) {
    throw new Error("finalize: message does not match the blinded state");
  }
  const inv = new Uint8Array(Buffer.from(state.inv, "base64"));
  const rawSig = await suite.finalize(
    pub,
    prepared,
    new Uint8Array(Buffer.from(blindSig, "base64")),
    inv,
  );
  const randomizer = prepared.subarray(0, RANDOMIZER_LEN);
  // credential := randomizer ‖ rawSig
  return Buffer.concat([Buffer.from(randomizer), Buffer.from(rawSig)]).toString(
    "base64",
  );
}

/**
 * Verify a finalized credential signature over `message` under the issuer's
 * public key. The credential is `randomizer(32) ‖ rawSignature`; we split it,
 * reconstruct the prepared message `randomizer ‖ message`, and verify the
 * signature over it.
 *
 * Never throws — returns `false` on any malformed key, credential, or message
 * (an attacker-controlled credential must yield a clean `false`, not a crash).
 * The `message` MUST embed the `decisionId` binding (e.g. `decisionId ‖ serial`)
 * so a credential minted for one decision cannot be replayed against another.
 */
export async function verifyCredential(
  publicKeySpkiPem: string,
  message: string | Uint8Array,
  credentialSig: string,
): Promise<boolean> {
  try {
    const suite = await getSuite();
    const pub = await importPublicKey(publicKeySpkiPem);

    const token = Buffer.from(credentialSig, "base64");
    // A valid credential is at least randomizer(32) + a non-empty signature.
    if (token.length <= RANDOMIZER_LEN) return false;
    const randomizer = token.subarray(0, RANDOMIZER_LEN);
    const rawSig = token.subarray(RANDOMIZER_LEN);

    // Reconstruct the exact bytes that were signed: randomizer ‖ message.
    const prepared = Buffer.concat([randomizer, Buffer.from(toBytes(message))]);

    return await suite.verify(pub, new Uint8Array(rawSig), new Uint8Array(prepared));
  } catch {
    return false;
  }
}
