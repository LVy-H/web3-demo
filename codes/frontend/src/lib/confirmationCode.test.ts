import { describe, it, expect } from 'vitest'
import { hexToBytes } from '@noble/hashes/utils'
import { confirmationCode } from './confirmationCode'

const NONCE_HEX = 'aabbccddeeff0011'
const COMMITMENT = 12345678901234567890123456789012345678901234567890n

describe('confirmationCode', () => {
  it('is deterministic for the same (nonce, commitment)', () => {
    expect(confirmationCode(NONCE_HEX, COMMITMENT)).toBe(confirmationCode(NONCE_HEX, COMMITMENT))
  })

  it('always returns exactly 4 decimal digits', () => {
    for (const c of [0n, 1n, 42n, COMMITMENT, 2n ** 200n]) {
      expect(confirmationCode(NONCE_HEX, c)).toMatch(/^[0-9]{4}$/)
    }
  })

  it('voter-side and organizer-side derive the same code (hex vs bytes, bigint vs string)', () => {
    const fromHexAndBigint = confirmationCode(NONCE_HEX, COMMITMENT)
    const fromBytesAndString = confirmationCode(hexToBytes(NONCE_HEX), COMMITMENT.toString())
    expect(fromBytesAndString).toBe(fromHexAndBigint)
  })

  it('generally changes with different nonce or commitment', () => {
    const base = confirmationCode(NONCE_HEX, COMMITMENT)
    expect(confirmationCode('00bbccddeeff0011', COMMITMENT)).not.toBe(base)
    expect(confirmationCode(NONCE_HEX, COMMITMENT + 1n)).not.toBe(base)
  })

  it('rejects negative commitments', () => {
    expect(() => confirmationCode(NONCE_HEX, -1n)).toThrow()
  })
})
