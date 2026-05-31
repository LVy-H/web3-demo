/**
 * Live Meeting Vote — per-poll organizer ticket-signing keypair (S1.1).
 *
 * IMPORTANT: this ed25519 key signs TICKETS and is entirely SEPARATE from the
 * organizer's MetaMask wallet. The wallet owns the poll and registers voters
 * on-chain; this key only proves "this QR came from me". It never leaves the
 * browser. The public half is what the relayer stores (via /tickets/issue) to
 * verify incoming tickets.
 *
 * Persisted in localStorage under `org-keypair-${pollId}`, mirroring the
 * existing `semaphore-identity-${pollAddress}` convention in Poll.tsx. Storage
 * is injectable so the libs are unit-testable without a DOM.
 */
import { ed25519 } from '@noble/curves/ed25519'
import { bytesToHex, hexToBytes, randomBytes } from '@noble/hashes/utils'

export interface OrgKeypair {
  /** ed25519 seed, 32-byte hex (no 0x). */
  privKey: string
  /** ed25519 public key, 32-byte hex (no 0x). */
  pubKey: string
}

/** Minimal subset of the Web Storage API the keypair store needs. */
export type KeyStore = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>

const PREFIX = 'org-keypair-'

function storageKey(pollId: string): string {
  return `${PREFIX}${pollId.toLowerCase()}`
}

function resolveStore(store?: KeyStore): KeyStore | undefined {
  if (store) return store
  return typeof localStorage !== 'undefined' ? localStorage : undefined
}

function isValidKeypair(v: unknown): v is OrgKeypair {
  if (typeof v !== 'object' || v === null) return false
  const k = v as Record<string, unknown>
  return (
    typeof k.privKey === 'string' &&
    typeof k.pubKey === 'string' &&
    k.privKey.length === 64 &&
    k.pubKey.length === 64
  )
}

/** Generate a fresh ed25519 keypair (hex-encoded). */
export function generateOrgKeypair(): OrgKeypair {
  const priv = randomBytes(32)
  const pub = ed25519.getPublicKey(priv)
  return { privKey: bytesToHex(priv), pubKey: bytesToHex(pub) }
}

/** Derive the public key for a given private key — handy when only the private
 *  half was persisted/restored. */
export function publicKeyFor(privKey: string): string {
  return bytesToHex(ed25519.getPublicKey(hexToBytes(privKey)))
}

/** Persist a keypair for a poll. Swallows storage errors (private mode, quota). */
export function saveOrgKeypair(pollId: string, kp: OrgKeypair, store?: KeyStore): void {
  const s = resolveStore(store)
  if (!s) return
  try {
    s.setItem(storageKey(pollId), JSON.stringify(kp))
  } catch {
    // best-effort; ignore unavailable/full storage
  }
}

/** Load a poll's keypair, or null if absent/corrupt/unavailable. */
export function loadOrgKeypair(pollId: string, store?: KeyStore): OrgKeypair | null {
  const s = resolveStore(store)
  if (!s) return null
  try {
    const raw = s.getItem(storageKey(pollId))
    if (!raw) return null
    const parsed: unknown = JSON.parse(raw)
    return isValidKeypair(parsed) ? parsed : null
  } catch {
    return null
  }
}

/** Idempotent: return the poll's existing keypair or generate, persist, and
 *  return a new one. Same pollId → same key across reloads. */
export function getOrCreateOrgKeypair(pollId: string, store?: KeyStore): OrgKeypair {
  const existing = loadOrgKeypair(pollId, store)
  if (existing) return existing
  const fresh = generateOrgKeypair()
  saveOrgKeypair(pollId, fresh, store)
  return fresh
}

/** Discard a poll's keypair (e.g. "regenerate" / key compromise — Sprint 2). */
export function clearOrgKeypair(pollId: string, store?: KeyStore): void {
  const s = resolveStore(store)
  if (!s) return
  try {
    s.removeItem(storageKey(pollId))
  } catch {
    // ignore
  }
}
