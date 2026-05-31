/**
 * Live Meeting Vote — confirmation code derivation (S1.1).
 *
 * The voter's phone shows a short code; the organizer reads it off the phone
 * face-to-face and finds the matching row in the projected queue. The code is
 * DETERMINISTIC from the ticket nonce + the voter's ephemeral identity
 * commitment, so the voter side and the organizer/relayer side derive the same
 * value independently (no extra round-trip, and it can't be spoofed to collide
 * without the same inputs).
 *
 *   code = SHA-256( nonceBytes ‖ commitment-as-32-byte-big-endian )
 *          → first 16 bits → mod 10000 → zero-padded to 4 digits
 *
 * Canonical encoding — the relayer and any future Flutter client must reproduce
 * it byte-for-byte (spec §2.5).
 */
import { sha256 } from '@noble/hashes/sha256'
import { hexToBytes, concatBytes } from '@noble/hashes/utils'

const COMMITMENT_BYTES = 32

function nonceToBytes(nonce: string | Uint8Array): Uint8Array {
  if (typeof nonce !== 'string') return nonce
  return hexToBytes(nonce.startsWith('0x') ? nonce.slice(2) : nonce)
}

/** Big-endian 32-byte encoding of a bigint commitment (Semaphore commitments
 *  fit in the BN254 field, < 2^254, so 32 bytes is always enough). */
function commitmentToBytes(commitment: bigint | string): Uint8Array {
  const value = typeof commitment === 'bigint' ? commitment : BigInt(commitment)
  if (value < 0n) throw new Error('commitment must be non-negative')
  const out = new Uint8Array(COMMITMENT_BYTES)
  let v = value
  for (let i = COMMITMENT_BYTES - 1; i >= 0; i--) {
    out[i] = Number(v & 0xffn)
    v >>= 8n
  }
  if (v !== 0n) throw new Error('commitment exceeds 32 bytes')
  return out
}

/** Derive the 4-digit confirmation code (e.g. "0427") for a (nonce, commitment)
 *  pair. Pure and deterministic. */
export function confirmationCode(
  nonce: string | Uint8Array,
  commitment: bigint | string,
): string {
  const digest = sha256(concatBytes(nonceToBytes(nonce), commitmentToBytes(commitment)))
  // first 16 bits, big-endian
  const first16 = ((digest[0] ?? 0) << 8) | (digest[1] ?? 0)
  return String(first16 % 10000).padStart(4, '0')
}
