# Secret-ballot CLIENT wiring (Dart RSABSSA) — design + acceptance

> 2026-06-28. Completes the named NEXT (Phase-4 secret-ballot path). The server
> side (per-decision RFC 9474 **RSABSSA-SHA384-PSS-Randomized** issuer,
> `/register` blind-sign, credentialed `/ballots` cast, verifier) shipped on
> `redesign/secret-ballots`/`multi-tenant` and is green. This wires the **Flutter
> client** so a voter can cast a *verifiable secret ballot* end-to-end, and proves
> it against a **real running `codes/server`** (no mocks).

## Why this is verifiable (the whole point)

The credential math must interoperate **byte-for-byte** with the server's
`@cloudflare/blindrsa-ts`. We do not assert correctness by inspection — we
*prove* it: the Dart client blinds locally, the **real server** blind-signs with
its private key, the Dart client finalizes, and the **real server**
`verifyCredential`s the cast and the public `GET /verify` returns `ok:true`. If
the Dart blinding is wrong by one byte, the server rejects the cast (403
INELIGIBLE) and the live test goes red. Green ⇒ correct.

## Server addition (small, required)

A secret-mode voter only has the decision id; they need the issuer's SPKI public
key to `blind()` under it. Today only the convener's **create** response carries
`issuerPublicKeyPem`; the public `GET /decisions/:id` view exposes only
`issuerPubKeyHash`. Add a **public** read:

- `GET /decisions/:id/issuer` → `200 {issuerPublicKeyPem, issuerPubKeyHash}` for
  secret-mode decisions; `404 {code:"NOT_SECRET"}` for open mode / unknown id.
- The client **must** verify `sha256(SPKI-DER(issuerPublicKeyPem))` equals the
  `issuerPubKeyHash` it already trusts (it is bound into `setupCommitment`, which
  the verifier checks against the anchor). This makes the key fetch
  trust-minimised — a tampered key fails the hash check before any blinding.
- Add a route test (secret → 200 + hash matches create; open → 404).

Match the existing `pubKeyHash` recipe exactly (see `credentials/issuer.ts` /
`pubKeyHashOf`) so the client's recomputed hash agrees.

## Client crypto — `core_crypto/lib/credentials/blind_rsa.dart`

Pure-Dart **RSABSSA-SHA384-PSS-Randomized** (RFC 9474 §4.1/§5; mirror
`codes/server/src/credentials/blindrsa.ts`). Use `pointycastle` for RSA key
parse, SHA-384, and BigInt modpow; implement EMSA-PSS-ENCODE + blinding by hand.

`blind(spkiPem, message) -> (blindedB64, BlindState{preparedB64, invB64})`:
1. `prepared = randomizer(32 random bytes) ‖ message`  (the Randomized variant's `prepare()`).
2. EMSA-PSS-ENCODE(`prepared`): Hash=SHA-384, MGF=MGF1-SHA-384, **sLen = 48**
   (= hLen; the library default), emBits = modBits − 1 (modBits = 2048). Produces
   `EM` of `k = 256` bytes; `m = OS2IP(EM)`.
3. Blind: random `r` in `[1, n)` with `gcd(r, n) = 1`; `x = r^e mod n`;
   `z = (m · x) mod n`; `inv = r^{-1} mod n`. `blinded = I2OSP(z, k)`.
4. Return `blinded` (base64), state `{prepared, inv}` (base64).

`finalize(spkiPem, message, blindSigB64, state) -> credentialB64`:
1. `s = (OS2IP(blindSig) · inv) mod n`; `sig = I2OSP(s, k)`.
2. **Verify** RSASSA-PSS(pub, `prepared`, `sig`) — must pass (guards a bad sign).
3. Bind: assert `prepared[32:] == message`.
4. `credential = base64( randomizer(32) ‖ sig )`  (server splits it back the same way).

`verifyCredentialLocally(spkiPem, message, credentialB64) -> bool` (for the unit
round-trip test): split `randomizer ‖ sig`, RSASSA-PSS-VERIFY over
`randomizer ‖ message`.

`issuerKeyHash(spkiPem) -> hex`: sha256 of the SPKI DER, matching the server.

**Correctness anchors** (these are where byte-exact interop usually breaks):
- `prepare()` prepends exactly 32 random bytes; the signature is over
  `randomizer ‖ message`, never the bare message.
- PSS salt length is **48** (hLen of SHA-384), not 0 (this is `PSS`, not `PSSZero`).
- `EM`/`blinded`/`sig` are all fixed-width `k = 256` bytes, big-endian.
- `emBits = 2047`, so the leftmost byte of `EM` is masked to its low 7 bits per
  EMSA-PSS-ENCODE step 11.

## Client API — `core_relay/lib/server_client.dart`

- `Future<Map> getIssuer(String id)` → `GET /decisions/:id/issuer`.
- `Future<Map> register(String decisionId, String blindedMessage)` →
  `POST /register {decisionId, blindedMessage}` → `{blindSignature}`.
- Extend cast for secret mode: `castBallot(... , String? serial, String? credentialSig)`
  adding `serial`/`credentialSig` to the body when present (open-mode callers unaffected).
- Mirror the contract in `server_client_test.dart` against `MockClient`.

## Client flow — secret-ballot voter

A small `SecretBallotCredential` service (in `core_crypto` or `feature_vote`):
`fetch issuer → verify hash == issuerPubKeyHash → serial = 16 random bytes hex →
message = "$decisionId|$serial" → blind → register → finalize → return (serial,
credentialSig)`. Wire it into the secret-mode branch of the voter port adapter
(`feature_vote/.../server_voter_port_adapter.dart`) so a secret decision casts
with `(serial, credentialSig)`; open mode is unchanged. Update the comment in
`core_crypto/.../proof/proof_service_stub.dart` to point at this path (the ZK
stub stays fenced; this is the credential replacement it promised).

## Acceptance (HARD gate — verified-or-fenced)

1. **Unit**: `blind_rsa` finalize→verify round-trips locally; PSS encode matches
   a known-answer vector if one is handy; tampered credential ⇒ `false`.
2. **Live e2e** `core_relay/test/server_client_secret_live_test.dart`
   (`@Tags(['live'])`, gated on `TESSERA_LIVE_SERVER`+`TESSERA_ADMIN_TOKEN`, like
   `server_client_live_test.dart`): against a **real** `codes/server`,
   `createDecision(secret)` → `getIssuer` (hash verifies) → `register`×N (blind
   locally) → `open` → `castBallot(serial, credentialSig)`×N → a **reused serial
   ⇒ 409** → `close` → `publish` → `GET /verify` ⇒ `ok:true`. This is the proof
   the Dart RSABSSA interoperates with the server.
3. Standard gates stay green: `melos analyze`, `melos test` (non-live),
   `flutter build web`; server `npm run typecheck && npm test`.

**If byte-exact interop cannot be achieved this pass**: do NOT ship a false
green. Keep the secret-mode cast **fenced** with a clear error, land the server
`/issuer` route + the Dart scaffolding behind it, and document the precise
blocker (which PSS/encode step diverges) here. Open mode is untouched either way.

Tee every build/test to `.out/` and grep the log on failure rather than re-running.

## Outcome (2026-06-28) — byte-exact interop ACHIEVED, NOT fenced

The full path landed and is proven against a real server — no fallback needed.

- **Server**: `GET /decisions/:id/issuer` added to `routes/public.ts`
  (`200 {issuerPublicKeyPem, issuerPubKeyHash}` for secret mode; `404 NOT_SECRET`
  open; `404 NOT_FOUND` unknown). Route tests added; `npm run typecheck` + all
  **406** server tests green.
- **Dart crypto**: `core_crypto/lib/credentials/blind_rsa.dart` —
  hand-rolled EMSA-PSS-ENCODE/-VERIFY (SHA-384, MGF1-SHA-384, sLen=48,
  emBits=2047, k=256), 32-byte randomizer prepend, native-`BigInt` blinding,
  `pointycastle` ASN.1 SPKI parse. `issuerKeyHash` = `sha256hex(PEM string)` —
  matches `issuer.ts` exactly (the spec's "SPKI-DER" phrasing is loose; the
  recipe hashes the **PEM string**, confirmed by the live `getIssuer` assert).
- **Unit proof**: `blind_rsa_test.dart` — full Dart blind→sign→finalize→verify
  round-trip **plus** a CROSS-IMPL KAT: a credential produced by the server's
  `@cloudflare/blindrsa-ts` verifies under Dart `verifyCredentialLocally`, and
  `issuerKeyHash` reproduces the server `pubKeyHash`. 8/8 green.
- **Client + flow**: `ServerClient.getIssuer/register/getVerify` + secret-mode
  `castBallot(serial, credentialSig)`; `SecretBallotRegistrar`
  (`feature_vote/.../secret_ballot_credential.dart`) wired into the secret
  branch of `server_voter_port_adapter.dart` (open mode unchanged). Contract +
  orchestration tests green.
- **HARD GATE — LIVE e2e GREEN**:
  `core_relay/test/server_client_secret_live_test.dart` against a real
  `codes/server` (PORT 3091): create(secret) → getIssuer (recomputed hash ==
  anchored) → register×3 (blind locally) → open → cast×3 → reused-serial ⇒ 409
  SERIAL_USED → close → publish → `GET /verify` ⇒
  `ok=true; checks=setup,leaves,root-binding,contiguity,no-double-vote,
  tally-verdict all true; tally=[2,1]; verdict=carried`. The Dart RSABSSA
  interoperates with the server **byte-for-byte**.
