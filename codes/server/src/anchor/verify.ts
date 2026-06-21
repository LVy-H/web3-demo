/**
 * Tessera server — checkpoint signature verification (the verifier's §11 step-5
 * binding check, host-side mirror).
 *
 * Recomputes the EXACT signed-root payload from the checkpoint's own
 * {root, treeSize, decisionId} and checks the detached Ed25519 signature against
 * the supplied server pubkey. Never throws — an attacker-controlled checkpoint or
 * a malformed pubkey is a verification *failure* (`false`), not a crash.
 */
import { verifySig } from "../crypto";
import { signedRootPayload, type Checkpoint } from "./checkpoint";

/**
 * Verify a checkpoint's `signedRoot` against `serverPubKeyPem`. Returns true iff
 * the signature is a valid Ed25519 signature, by that key, over
 * `canonicalize({ root, treeSize, decisionId })` recomputed from the checkpoint.
 *
 * Tampering with root / treeSize / decisionId, or presenting a signature from a
 * different key, all yield `false`.
 */
export function verifyCheckpointSig(
  serverPubKeyPem: string,
  checkpoint: Checkpoint,
): boolean {
  try {
    if (checkpoint == null || typeof checkpoint !== "object") return false;
    const { root, treeSize, decisionId, signedRoot } = checkpoint;
    if (
      typeof root !== "string" ||
      typeof treeSize !== "number" ||
      typeof decisionId !== "string" ||
      typeof signedRoot !== "string"
    ) {
      return false;
    }
    const payload = signedRootPayload({ root, treeSize, decisionId });
    return verifySig(serverPubKeyPem, payload, signedRoot);
  } catch {
    return false;
  }
}
