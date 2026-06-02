import { describe, it, expect } from "vitest";
import { validateApprovalVoteRequest } from "../src/validation";

// A poll address; its decimal form is the expected proof.scope.
const POLL = "0x00000000000000000000000000000000000000ff";
const POLL_SCOPE = BigInt(POLL).toString(); // "255"

/** Build a well-formed approval-vote request body for a given bitmask, with a
 *  proof whose message/scope match by default (override to test rejection). */
function makeBody(opts: {
    pollAddress?: string;
    bitmask?: unknown;
    message?: string;
    scope?: string;
}) {
    const bitmask = opts.bitmask ?? 5;
    return {
        pollAddress: opts.pollAddress ?? POLL,
        bitmask,
        proof: {
            merkleTreeDepth: 1,
            merkleTreeRoot: "123",
            nullifier: "456",
            message: opts.message ?? String(bitmask),
            scope: opts.scope ?? POLL_SCOPE,
            points: Array(8).fill("0"),
        },
    };
}

describe("validateApprovalVoteRequest", () => {
    it("accepts a valid bitmask whose proof message+scope match", () => {
        const res = validateApprovalVoteRequest(makeBody({ bitmask: 0b101 }));
        expect(res.ok).toBe(true);
        if (res.ok) {
            expect(res.data.bitmask).toBe(0b101);
            expect(res.data.pollAddress).toBe(POLL);
        }
    });

    it("rejects a non-object body", () => {
        expect(validateApprovalVoteRequest(null).ok).toBe(false);
        expect(validateApprovalVoteRequest("nope").ok).toBe(false);
    });

    it("rejects an invalid pollAddress", () => {
        const res = validateApprovalVoteRequest(makeBody({ pollAddress: "not-an-address" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/pollAddress/);
    });

    it("rejects an empty ballot (bitmask 0)", () => {
        const res = validateApprovalVoteRequest(makeBody({ bitmask: 0, message: "0" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/empty ballot|> 0/);
    });

    it("rejects a negative or non-integer bitmask", () => {
        expect(validateApprovalVoteRequest(makeBody({ bitmask: -1, message: "-1" })).ok).toBe(false);
        expect(validateApprovalVoteRequest(makeBody({ bitmask: 1.5, message: "1.5" })).ok).toBe(false);
        expect(validateApprovalVoteRequest(makeBody({ bitmask: "3", message: "3" })).ok).toBe(false);
    });

    it("rejects a bitmask that overflows MAX_OPTIONS (>= 2^32)", () => {
        const big = 2 ** 32;
        const res = validateApprovalVoteRequest(makeBody({ bitmask: big, message: String(big) }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/32 bits/);
    });

    it("rejects when proof.message != bitmask (tamper guard)", () => {
        const res = validateApprovalVoteRequest(makeBody({ bitmask: 0b101, message: "3" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/message.*does not match bitmask/);
    });

    it("rejects when proof.scope != pollAddress", () => {
        const res = validateApprovalVoteRequest(makeBody({ bitmask: 1, scope: "999999" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/scope does not match/);
    });

    it("rejects a malformed proof (points not length 8)", () => {
        const body = makeBody({ bitmask: 1 });
        (body.proof as { points: string[] }).points = ["0", "0"];
        const res = validateApprovalVoteRequest(body);
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/proof/);
    });

    it("accepts the all-options-approved mask for a single-word poll", () => {
        // 0b111 (all of 3 options) round-trips fine as a number.
        const res = validateApprovalVoteRequest(makeBody({ bitmask: 0b111 }));
        expect(res.ok).toBe(true);
    });
});
