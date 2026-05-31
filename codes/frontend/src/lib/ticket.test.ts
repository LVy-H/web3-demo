import { describe, it, expect } from 'vitest'
import { base64urlnopad } from '@scure/base'
import { generateOrgKeypair } from './orgKeypair'
import {
  createTicketPayload,
  signTicket,
  decodeTicket,
  verifyTicket,
  TICKET_TTL_SECONDS,
} from './ticket'

const POLL = '0x1111111111111111111111111111111111111111' as const
const NOW = 1_000_000

describe('ticket', () => {
  it('round-trips {p, n, e} through sign → decode', () => {
    const kp = generateOrgKeypair()
    const payload = createTicketPayload(POLL, NOW)
    const enc = signTicket(payload, kp.privKey)
    const decoded = decodeTicket(enc)
    expect(decoded.p).toBe(POLL)
    expect(decoded.n).toBe(payload.n)
    expect(decoded.e).toBe(NOW + TICKET_TTL_SECONDS)
  })

  it('verifies a valid, unexpired ticket', () => {
    const kp = generateOrgKeypair()
    const enc = signTicket(createTicketPayload(POLL, NOW), kp.privKey)
    const res = verifyTicket(enc, kp.pubKey, NOW)
    expect(res.valid).toBe(true)
    if (res.valid) expect(res.ticket.p).toBe(POLL)
  })

  it('rejects an expired ticket with reason "expired"', () => {
    const kp = generateOrgKeypair()
    const enc = signTicket(createTicketPayload(POLL, NOW), kp.privKey)
    const res = verifyTicket(enc, kp.pubKey, NOW + TICKET_TTL_SECONDS + 1)
    expect(res.valid).toBe(false)
    if (!res.valid) expect(res.reason).toBe('expired')
  })

  it('rejects a ticket signed by a different key with reason "badSig"', () => {
    const signer = generateOrgKeypair()
    const attacker = generateOrgKeypair()
    const enc = signTicket(createTicketPayload(POLL, NOW), signer.privKey)
    const res = verifyTicket(enc, attacker.pubKey, NOW)
    expect(res.valid).toBe(false)
    if (!res.valid) expect(res.reason).toBe('badSig')
  })

  it('rejects a tampered preimage with reason "badSig"', () => {
    const kp = generateOrgKeypair()
    const enc = signTicket(createTicketPayload(POLL, NOW), kp.privKey)
    const wire = base64urlnopad.decode(enc)
    wire[0] = wire[0]! ^ 0xff // flip a pollId byte; signature no longer matches
    const tampered = base64urlnopad.encode(wire)
    const res = verifyTicket(tampered, kp.pubKey, NOW)
    expect(res.valid).toBe(false)
    if (!res.valid) expect(res.reason).toBe('badSig')
  })

  it('rejects malformed input without throwing', () => {
    const kp = generateOrgKeypair()
    expect(verifyTicket('AAAA', kp.pubKey, NOW)).toEqual({ valid: false, reason: 'malformed' })
    expect(verifyTicket('not valid base64 @@@', kp.pubKey, NOW)).toEqual({
      valid: false,
      reason: 'malformed',
    })
  })

  it('rejects an invalid pollId at payload creation', () => {
    expect(() => createTicketPayload('0xabc', NOW)).toThrow()
  })
})
