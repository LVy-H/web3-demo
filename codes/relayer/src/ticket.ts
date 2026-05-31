/**
 * Server-side ticket verification (S1.2).
 *
 * Byte layout MUST stay identical to codes/frontend/src/lib/ticket.ts — it is
 * the cross-client contract (spec §2.5). Wire form is
 * base64url-nopad( preimage(32) ‖ ed25519 sig(64) ), preimage being
 * [ pollId 20 ][ nonce 8 ][ expiresAt uint32 BE 4 ]. We use Node's Buffer
 * base64url (URL-safe, unpadded — byte-compatible with @scure/base
 * base64urlnopad) so the relayer needs no extra base64 dependency.
 *
 * The organizer's PUBLIC key (registered via /tickets/issue) is the only thing
 * trusted here; the private key never leaves the organizer's browser.
 */
import { ed25519 } from "@noble/curves/ed25519";

const ADDR_BYTES = 20;
const NONCE_BYTES = 8;
const EXP_BYTES = 4;
const PREIMAGE_BYTES = ADDR_BYTES + NONCE_BYTES + EXP_BYTES; // 32
const WIRE_BYTES = PREIMAGE_BYTES + 64; // + ed25519 sig

export interface DecodedTicket {
    p: string; // 0x-prefixed poll address
    n: string; // nonce hex
    e: number; // expiry, unix seconds
}

export type TicketInvalidReason = "malformed" | "badSig" | "expired";

export type VerifyResult =
    | { valid: true; ticket: DecodedTicket }
    | { valid: false; reason: TicketInvalidReason; ticket?: DecodedTicket };

function hexToBytes(h: string): Uint8Array {
    return Uint8Array.from(Buffer.from(h.replace(/^0x/i, ""), "hex"));
}

function decodeWire(encoded: string): Uint8Array | null {
    const wire = Uint8Array.from(Buffer.from(encoded, "base64url"));
    return wire.length === WIRE_BYTES ? wire : null;
}

/** Parse wire → ticket fields. Throws on malformed length. No signature check. */
export function decodeTicket(encoded: string): DecodedTicket {
    const wire = decodeWire(encoded);
    if (!wire) throw new Error("malformed ticket");
    const addr = wire.subarray(0, ADDR_BYTES);
    const nonce = wire.subarray(ADDR_BYTES, ADDR_BYTES + NONCE_BYTES);
    const e = new DataView(
        wire.buffer,
        wire.byteOffset + ADDR_BYTES + NONCE_BYTES,
        EXP_BYTES
    ).getUint32(0, false);
    return {
        p: "0x" + Buffer.from(addr).toString("hex"),
        n: Buffer.from(nonce).toString("hex"),
        e,
    };
}

/** Signature-only check (ignores expiry). Used at redeem time, which can happen
 *  after the 30s TTL once the organizer confirms face-to-face. */
export function verifyTicketSignature(encoded: string, pubKeyHex: string): boolean {
    const wire = decodeWire(encoded);
    if (!wire) return false;
    try {
        return ed25519.verify(
            wire.subarray(PREIMAGE_BYTES, WIRE_BYTES),
            wire.subarray(0, PREIMAGE_BYTES),
            hexToBytes(pubKeyHex)
        );
    } catch {
        return false;
    }
}

/** Full verification: signature + freshness. Used at the `pending` step where
 *  the ticket must still be within its TTL. `now` is injectable for tests. */
export function verifyTicket(
    encoded: string,
    pubKeyHex: string,
    now: number = Math.floor(Date.now() / 1000)
): VerifyResult {
    const wire = decodeWire(encoded);
    if (!wire) return { valid: false, reason: "malformed" };
    if (!verifyTicketSignature(encoded, pubKeyHex)) {
        return { valid: false, reason: "badSig" };
    }
    const ticket = decodeTicket(encoded);
    if (ticket.e <= now) return { valid: false, reason: "expired", ticket };
    return { valid: true, ticket };
}
