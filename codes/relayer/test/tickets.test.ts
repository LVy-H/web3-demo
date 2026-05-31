import { describe, it, expect, beforeEach } from "vitest";
import request from "supertest";
import { ed25519 } from "@noble/curves/ed25519";
import { randomBytes } from "@noble/hashes/utils";
import { createApp } from "../src/app";
import {
    __resetTicketStore,
    validateIssueRequest,
    validatePendingRequest,
} from "../src/tickets";
import { verifyTicket } from "../src/ticket";

const POLL_A = "0x1111111111111111111111111111111111111111";
const POLL_B = "0x2222222222222222222222222222222222222222";

/** Build + sign a ticket with the identical byte layout as the frontend
 *  (codes/frontend/src/lib/ticket.ts). Used to drive the relayer's verify. */
function makeKeypair() {
    const priv = randomBytes(32);
    const pub = ed25519.getPublicKey(priv);
    return { priv, pubHex: Buffer.from(pub).toString("hex") };
}

function signTicket(pollId: string, nonceHex: string, expiry: number, priv: Uint8Array): string {
    const addr = Buffer.from(pollId.replace(/^0x/i, ""), "hex"); // 20
    const nonce = Buffer.from(nonceHex, "hex"); // 8
    const exp = Buffer.alloc(4);
    exp.writeUInt32BE(expiry, 0);
    const preimage = Buffer.concat([addr, nonce, exp]); // 32
    const sig = ed25519.sign(new Uint8Array(preimage), priv); // 64
    return Buffer.concat([preimage, Buffer.from(sig)]).toString("base64url");
}

const FUTURE = Math.floor(Date.now() / 1000) + 3600;
const PAST = Math.floor(Date.now() / 1000) - 10;

describe("ticket verify (server-side)", () => {
    it("accepts a valid, unexpired, correctly-signed ticket", () => {
        const kp = makeKeypair();
        const enc = signTicket(POLL_A, "aabbccddeeff0011", FUTURE, kp.priv);
        const res = verifyTicket(enc, kp.pubHex);
        expect(res.valid).toBe(true);
        if (res.valid) expect(res.ticket.n).toBe("aabbccddeeff0011");
    });

    it("rejects an expired ticket", () => {
        const kp = makeKeypair();
        const enc = signTicket(POLL_A, "aabbccddeeff0011", PAST, kp.priv);
        const res = verifyTicket(enc, kp.pubHex);
        expect(res.valid).toBe(false);
        if (!res.valid) expect(res.reason).toBe("expired");
    });

    it("rejects a wrong-key signature", () => {
        const signer = makeKeypair();
        const attacker = makeKeypair();
        const enc = signTicket(POLL_A, "aabbccddeeff0011", FUTURE, signer.priv);
        const res = verifyTicket(enc, attacker.pubHex);
        expect(res.valid).toBe(false);
        if (!res.valid) expect(res.reason).toBe("badSig");
    });

    it("rejects malformed input", () => {
        const kp = makeKeypair();
        expect(verifyTicket("AAAA", kp.pubHex).valid).toBe(false);
    });
});

describe("validators", () => {
    it("validateIssueRequest rejects bad pollId / pubKey, accepts valid", () => {
        expect(validateIssueRequest({ pollId: "nope", orgPubKey: "a".repeat(64) }).ok).toBe(false);
        expect(validateIssueRequest({ pollId: POLL_A, orgPubKey: "xyz" }).ok).toBe(false);
        expect(validateIssueRequest({ pollId: POLL_A, orgPubKey: "a".repeat(64) }).ok).toBe(true);
    });

    it("validatePendingRequest requires a 4-digit code and decimal commitment", () => {
        const base = { pollId: POLL_A, ticket: "x", ephemeralIdentityCommitment: "123", confirmationCode: "0427" };
        expect(validatePendingRequest(base).ok).toBe(true);
        expect(validatePendingRequest({ ...base, confirmationCode: "42" }).ok).toBe(false);
        expect(validatePendingRequest({ ...base, ephemeralIdentityCommitment: "0xabc" }).ok).toBe(false);
        const { confirmationCode: _omit, ...noCode } = base;
        void _omit;
        expect(validatePendingRequest(noCode).ok).toBe(false);
    });
});

describe("ticket endpoints (integration)", () => {
    const app = createApp();
    let kp: ReturnType<typeof makeKeypair>;

    beforeEach(() => {
        __resetTicketStore();
        kp = makeKeypair();
    });

    async function issue(pollId: string) {
        return request(app).post("/api/relay/tickets/issue").send({ pollId, orgPubKey: kp.pubHex });
    }

    it("pending requires the org pubkey to be issued first", async () => {
        const enc = signTicket(POLL_A, "1122334455667788", FUTURE, kp.priv);
        const res = await request(app)
            .post("/api/relay/tickets/pending")
            .send({ pollId: POLL_A, ticket: enc, ephemeralIdentityCommitment: "42", confirmationCode: "0427" });
        expect(res.status).toBe(400);
    });

    it("accepts a fresh ticket into the queue after issue; rejects an expired one", async () => {
        await issue(POLL_A);

        const fresh = signTicket(POLL_A, "1122334455667788", FUTURE, kp.priv);
        const ok = await request(app)
            .post("/api/relay/tickets/pending")
            .send({ pollId: POLL_A, ticket: fresh, ephemeralIdentityCommitment: "42", confirmationCode: "0427" });
        expect(ok.status).toBe(200);
        expect(ok.body.status).toBe("pending");

        const stale = signTicket(POLL_A, "99aabbccddeeff00", PAST, kp.priv);
        const bad = await request(app)
            .post("/api/relay/tickets/pending")
            .send({ pollId: POLL_A, ticket: stale, ephemeralIdentityCommitment: "43", confirmationCode: "1234" });
        expect(bad.status).toBe(400);
    });

    it("queue returns only the requested poll's pending voters", async () => {
        await issue(POLL_A);
        await issue(POLL_B);
        await request(app)
            .post("/api/relay/tickets/pending")
            .send({
                pollId: POLL_A,
                ticket: signTicket(POLL_A, "1122334455667788", FUTURE, kp.priv),
                ephemeralIdentityCommitment: "42",
                confirmationCode: "0427",
            });

        const a = await request(app).get("/api/relay/tickets/queue").query({ pollId: POLL_A });
        expect(a.status).toBe(200);
        expect(a.body.voters).toHaveLength(1);
        expect(a.body.voters[0].confirmationCode).toBe("0427");

        const b = await request(app).get("/api/relay/tickets/queue").query({ pollId: POLL_B });
        expect(b.body.voters).toHaveLength(0);
    });

    it("redeem consumes a ticket exactly once (replay rejected) and confirms the queue entry", async () => {
        await issue(POLL_A);
        const enc = signTicket(POLL_A, "1122334455667788", FUTURE, kp.priv);
        await request(app)
            .post("/api/relay/tickets/pending")
            .send({ pollId: POLL_A, ticket: enc, ephemeralIdentityCommitment: "42", confirmationCode: "0427" });

        const first = await request(app).post("/api/relay/tickets/redeem").send({ pollId: POLL_A, ticket: enc });
        expect(first.status).toBe(200);

        const replay = await request(app).post("/api/relay/tickets/redeem").send({ pollId: POLL_A, ticket: enc });
        expect(replay.status).toBe(409);

        // After redeem the voter is no longer "pending" in the queue.
        const q = await request(app).get("/api/relay/tickets/queue").query({ pollId: POLL_A });
        expect(q.body.voters).toHaveLength(0);
    });
});
