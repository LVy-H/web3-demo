/**
 * Tessera server — credentials module (Phase 3, system-design §12.2).
 *
 * Per-decision **RFC 9474 RSABSSA-PSS** blind-signature credentials — the
 * foundation for **secret ballots** (anonymous-yet-eligible). The blinding math
 * is delegated to the vetted `@cloudflare/blindrsa-ts` library
 * (RSABSSA-SHA384-PSS-Randomized); we never hand-roll it.
 *
 * Protocol (one decision):
 *   1. `newIssuer()` mints a fresh per-decision RSA keypair; `pubKeyHash` goes
 *      into the decision's `setupCommitment` and is anchored before registration,
 *      so the host cannot swap signing keys (§6, §11.1).
 *   2. Registration (eligibility passes): the client `blind()`s a credential
 *      `message`, the issuer `blindSign()`s the *blinded* token (it never sees
 *      the final token), the client `finalize()`s it into a credential signature.
 *   3. Cast: the voter presents `(serial, credentialSig)`; the server (and any
 *      independent verifier) calls `verifyCredential()` against the anchored
 *      issuer pubkey.
 *
 * **decisionId binding.** The credential `message` MUST bind the decision — the
 * caller constructs `message = decisionId ‖ serial` (e.g. `` `${decisionId}|${serial}` ``).
 * Because the signature commits to those exact bytes, a credential minted for
 * decision X fails `verifyCredential` under decision Y: credentials cannot be
 * replayed across decisions.
 *
 * **Honest scope (§6).** Blind signatures hide the *token*, not the *act*. This
 * gives ballot secrecy against participants, outside observers, and after-the-
 * fact forensics — NOT against a live malicious host (which can correlate
 * register↔cast by timing/IP/session), and it does NOT fix roster stuffing.
 * Do not overclaim.
 */
export { newIssuer, type Issuer } from "./issuer";
export {
  blind,
  blindSign,
  finalize,
  verifyCredential,
  type BlindState,
} from "./blindrsa";
