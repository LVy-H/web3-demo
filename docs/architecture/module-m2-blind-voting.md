# Secret Ballots

The old `ZkBlindVoting` commit-reveal contract module is retired. Current
Tessera secret ballots use blind-signature credentials on the self-hosted
server.

## Current Flow

1. A secret-mode decision is created with a per-decision RSABSSA issuer key.
2. During registration, the voter blinds a credential message locally.
3. `POST /register` blind-signs the opaque token after eligibility checks.
4. The voter finalizes the credential client-side.
5. During voting, `POST /ballots` presents `(serial, credentialSig)`.
6. The server verifies the credential over `decisionId|serial`.
7. The serial is recorded in the public ballot leaf to enforce no double vote.

## Guarantees

- The server does not see the final credential during issuance.
- Published ballots do not contain a voter identity.
- Reusing a serial returns a signed `SERIAL_USED` refusal.
- The verifier checks duplicate serials from public data.

## Caveat

This protects against participants, observers, and forensic inspection of the
published log. It does not fully protect against timing/metadata correlation by
a live malicious host; that is the named post-1.0 strong-mode work.
