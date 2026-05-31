/**
 * Live Meeting Vote — signed, expiring tickets (S1.1).
 *
 * A ticket is the organizer's per-poll "this QR is genuine and fresh" stamp.
 * It is signed CLIENT-SIDE by the organizer's per-poll ed25519 key (see
 * orgKeypair.ts) and verified both client-side (voter page) and server-side
 * (relayer). The relayer reuses this exact byte layout, so the encoding here
 * is the cross-client contract (spec §2.5) — do not change it casually.
 *
 * Canonical preimage (what gets signed) is a FIXED-WIDTH 32-byte buffer, never
 * JSON.stringify (key order / whitespace would break cross-language verify):
 *
 *   [ pollId 20 bytes ][ nonce 8 bytes ][ expiresAt uint32 big-endian 4 bytes ]
 *
 * Wire form = base64url-nopad( preimage(32) ‖ ed25519 signature(64) ) = 96 bytes.
 */
import { ed25519 } from '@noble/curves/ed25519'
import { bytesToHex, hexToBytes, randomBytes, concatBytes } from '@noble/hashes/utils'
import { base64urlnopad } from '@scure/base'

/** Seconds a ticket stays valid after issuance. Short enough that resharing a
 *  QR with someone outside the room is impractical (attack A3/A4 in the design). */
export const TICKET_TTL_SECONDS = 30

const ADDR_BYTES = 20
const NONCE_BYTES = 8
const EXP_BYTES = 4
const PREIMAGE_BYTES = ADDR_BYTES + NONCE_BYTES + EXP_BYTES // 32
const SIG_BYTES = 64
const WIRE_BYTES = PREIMAGE_BYTES + SIG_BYTES // 96

/** The decoded, unsigned ticket fields. */
export interface Ticket {
  /** Poll address, 0x-prefixed lowercase hex (the M1 poll / clone address). */
  p: `0x${string}`
  /** Single-use nonce, 8 random bytes as hex (no 0x). */
  n: string
  /** Expiry, unix seconds. */
  e: number
}

export type TicketInvalidReason = 'malformed' | 'badSig' | 'expired'

export type VerifyResult =
  | { valid: true; ticket: Ticket }
  | { valid: false; reason: TicketInvalidReason; ticket?: Ticket }

function stripHex(h: string): string {
  return h.startsWith('0x') || h.startsWith('0X') ? h.slice(2) : h
}

/** Build a fresh (unsigned) ticket payload for a poll. `now` is injected (unix
 *  seconds) so callers/tests stay deterministic. */
export function createTicketPayload(
  pollId: string,
  now: number,
  ttlSeconds: number = TICKET_TTL_SECONDS,
): Ticket {
  const addr = stripHex(pollId).toLowerCase()
  if (addr.length !== ADDR_BYTES * 2) {
    throw new Error(`invalid pollId: expected 20-byte hex address, got ${pollId}`)
  }
  return {
    p: `0x${addr}`,
    n: bytesToHex(randomBytes(NONCE_BYTES)),
    e: now + ttlSeconds,
  }
}

/** The 32-byte canonical preimage that gets signed. Exported so the relayer
 *  (and a future Flutter client) can reproduce it byte-for-byte. */
export function ticketPreimage(t: Ticket): Uint8Array {
  const addr = hexToBytes(stripHex(t.p))
  if (addr.length !== ADDR_BYTES) throw new Error('invalid pollId length')
  const nonce = hexToBytes(t.n)
  if (nonce.length !== NONCE_BYTES) throw new Error('invalid nonce length')
  if (!Number.isInteger(t.e) || t.e < 0 || t.e > 0xffffffff) {
    throw new Error('invalid expiry')
  }
  const exp = new Uint8Array(EXP_BYTES)
  new DataView(exp.buffer).setUint32(0, t.e, false) // big-endian
  return concatBytes(addr, nonce, exp)
}

/** Sign a ticket payload with the organizer's ed25519 private key (32-byte hex
 *  or bytes). Returns the base64url-nopad wire string carried in the QR. */
export function signTicket(t: Ticket, privKey: string | Uint8Array): string {
  const priv = typeof privKey === 'string' ? hexToBytes(stripHex(privKey)) : privKey
  const preimage = ticketPreimage(t)
  const sig = ed25519.sign(preimage, priv)
  return base64urlnopad.encode(concatBytes(preimage, sig))
}

/** Parse the wire string back into ticket fields. Does NOT verify the signature
 *  — use verifyTicket for that. Throws on malformed input. */
export function decodeTicket(encoded: string): Ticket {
  const wire = base64urlnopad.decode(encoded)
  if (wire.length !== WIRE_BYTES) {
    throw new Error(`malformed ticket: expected ${WIRE_BYTES} bytes, got ${wire.length}`)
  }
  const addr = wire.subarray(0, ADDR_BYTES)
  const nonce = wire.subarray(ADDR_BYTES, ADDR_BYTES + NONCE_BYTES)
  const e = new DataView(wire.buffer, wire.byteOffset + ADDR_BYTES + NONCE_BYTES, EXP_BYTES).getUint32(0, false)
  return { p: `0x${bytesToHex(addr)}`, n: bytesToHex(nonce), e }
}

/** Verify a wire ticket against the organizer's public key. `now` (unix seconds)
 *  is injected so tests are deterministic; defaults to the current time. */
export function verifyTicket(
  encoded: string,
  pubKey: string | Uint8Array,
  now: number = Math.floor(Date.now() / 1000),
): VerifyResult {
  let wire: Uint8Array
  try {
    wire = base64urlnopad.decode(encoded)
  } catch {
    return { valid: false, reason: 'malformed' }
  }
  if (wire.length !== WIRE_BYTES) return { valid: false, reason: 'malformed' }

  const preimage = wire.subarray(0, PREIMAGE_BYTES)
  const sig = wire.subarray(PREIMAGE_BYTES, WIRE_BYTES)
  const pub = typeof pubKey === 'string' ? hexToBytes(stripHex(pubKey)) : pubKey

  let sigOk = false
  try {
    sigOk = ed25519.verify(sig, preimage, pub)
  } catch {
    return { valid: false, reason: 'badSig' }
  }
  if (!sigOk) return { valid: false, reason: 'badSig' }

  let ticket: Ticket
  try {
    ticket = decodeTicket(encoded)
  } catch {
    return { valid: false, reason: 'malformed' }
  }
  if (ticket.e <= now) return { valid: false, reason: 'expired', ticket }
  return { valid: true, ticket }
}
