import { describe, it, expect } from 'vitest'
import {
  generateOrgKeypair,
  saveOrgKeypair,
  loadOrgKeypair,
  getOrCreateOrgKeypair,
  clearOrgKeypair,
  publicKeyFor,
  type KeyStore,
} from './orgKeypair'
import { signTicket, verifyTicket, createTicketPayload } from './ticket'

/** In-memory KeyStore so the libs are testable without a DOM. */
function memStore(): KeyStore & { dump: Map<string, string> } {
  const dump = new Map<string, string>()
  return {
    dump,
    getItem: (k) => (dump.has(k) ? dump.get(k)! : null),
    setItem: (k, v) => void dump.set(k, v),
    removeItem: (k) => void dump.delete(k),
  }
}

const POLL_A = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
const POLL_B = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

describe('orgKeypair', () => {
  it('generates a keypair whose public key matches the private key', () => {
    const kp = generateOrgKeypair()
    expect(kp.privKey).toMatch(/^[0-9a-f]{64}$/)
    expect(kp.pubKey).toMatch(/^[0-9a-f]{64}$/)
    expect(publicKeyFor(kp.privKey)).toBe(kp.pubKey)
  })

  it('a generated key can sign a ticket that verifies against its public key', () => {
    const kp = generateOrgKeypair()
    const enc = signTicket(createTicketPayload(POLL_A, 1000), kp.privKey)
    expect(verifyTicket(enc, kp.pubKey, 1000).valid).toBe(true)
  })

  it('save then load returns the identical keypair', () => {
    const store = memStore()
    const kp = generateOrgKeypair()
    saveOrgKeypair(POLL_A, kp, store)
    expect(loadOrgKeypair(POLL_A, store)).toEqual(kp)
  })

  it('returns null for an unknown poll', () => {
    expect(loadOrgKeypair(POLL_A, memStore())).toBeNull()
  })

  it('getOrCreate is idempotent per poll and isolated across polls', () => {
    const store = memStore()
    const a1 = getOrCreateOrgKeypair(POLL_A, store)
    const a2 = getOrCreateOrgKeypair(POLL_A, store)
    const b1 = getOrCreateOrgKeypair(POLL_B, store)
    expect(a2).toEqual(a1) // same poll → same key
    expect(b1).not.toEqual(a1) // different poll → different key
  })

  it('returns null for a corrupt stored value without throwing', () => {
    const store = memStore()
    store.setItem('org-keypair-' + POLL_A.toLowerCase(), 'not json{')
    expect(loadOrgKeypair(POLL_A, store)).toBeNull()
    store.setItem('org-keypair-' + POLL_A.toLowerCase(), JSON.stringify({ privKey: 'short' }))
    expect(loadOrgKeypair(POLL_A, store)).toBeNull()
  })

  it('clear removes the stored key', () => {
    const store = memStore()
    const kp = generateOrgKeypair()
    saveOrgKeypair(POLL_A, kp, store)
    clearOrgKeypair(POLL_A, store)
    expect(loadOrgKeypair(POLL_A, store)).toBeNull()
  })
})
