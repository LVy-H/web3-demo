import { describe, it, expect } from "vitest";
import { validateQuadraticVoteRequest } from "../src/validation";

// A poll address; its decimal form is the expected proof.scope.
const POLL = "0x00000000000000000000000000000000000000ff";
const POLL_SCOPE = BigInt(POLL).toString(); // "255"

/** Build a well-formed quadratic-vote request body for a given packed allocation,
 *  with a proof whose message/scope match by default (override to test rejection). */
function makeBody(opts: {
    pollAddress?: string;
    packedAlloc?: unknown;
    message?: string;
    scope?: string;
}) {
    const packedAlloc = opts.packedAlloc ?? 0x0a; // slot0 = 10 votes on option 0 (cost 100)
    return {
        pollAddress: opts.pollAddress ?? POLL,
        packedAlloc,
        proof: {
            merkleTreeDepth: 1,
            merkleTreeRoot: "123",
            nullifier: "456",
            message: opts.message ?? String(packedAlloc),
            scope: opts.scope ?? POLL_SCOPE,
            points: Array(8).fill("0"),
        },
    };
}

describe("validateQuadraticVoteRequest", () => {
    it("accepts a valid packed allocation whose proof message+scope match", () => {
        // slot0 = 6, slot1 = 8 → cost 36+64 = 100 (within CREDITS). 0x86 = 134.
        const res = validateQuadraticVoteRequest(makeBody({ packedAlloc: 0x86 }));
        expect(res.ok).toBe(true);
        if (res.ok) {
            expect(res.data.packedAlloc).toBe(0x86);
            expect(res.data.pollAddress).toBe(POLL);
        }
    });

    it("rejects a non-object body", () => {
        expect(validateQuadraticVoteRequest(null).ok).toBe(false);
        expect(validateQuadraticVoteRequest("nope").ok).toBe(false);
    });

    it("rejects an invalid pollAddress", () => {
        const res = validateQuadraticVoteRequest(makeBody({ pollAddress: "not-an-address" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/pollAddress/);
    });

    it("rejects an empty ballot (packedAlloc 0)", () => {
        const res = validateQuadraticVoteRequest(makeBody({ packedAlloc: 0, message: "0" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/empty ballot|> 0/);
    });

    it("rejects a negative or non-integer packedAlloc", () => {
        expect(validateQuadraticVoteRequest(makeBody({ packedAlloc: -1, message: "-1" })).ok).toBe(false);
        expect(validateQuadraticVoteRequest(makeBody({ packedAlloc: 1.5, message: "1.5" })).ok).toBe(false);
        expect(validateQuadraticVoteRequest(makeBody({ packedAlloc: "3", message: "3" })).ok).toBe(false);
    });

    it("rejects a packedAlloc that overflows 32 bits (>= 2^32)", () => {
        const big = 2 ** 32;
        const res = validateQuadraticVoteRequest(makeBody({ packedAlloc: big, message: String(big) }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/32 bits/);
    });

    it("accepts the maximal in-range packed value (2^32 - 1)", () => {
        // The relayer only bounds the word, not the quadratic budget — the contract
        // owns Σvᵢ² ≤ CREDITS and the ghost-slot rule. 2^32 - 1 fits as a number.
        const max = 2 ** 32 - 1;
        const res = validateQuadraticVoteRequest(makeBody({ packedAlloc: max, message: String(max) }));
        expect(res.ok).toBe(true);
    });

    it("rejects when proof.message != packedAlloc (tamper guard)", () => {
        const res = validateQuadraticVoteRequest(makeBody({ packedAlloc: 0x86, message: "3" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/message.*does not match packedAlloc/);
    });

    it("rejects when proof.scope != pollAddress", () => {
        const res = validateQuadraticVoteRequest(makeBody({ packedAlloc: 1, scope: "999999" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/scope does not match/);
    });

    it("rejects a malformed proof (points not length 8)", () => {
        const body = makeBody({ packedAlloc: 1 });
        (body.proof as { points: string[] }).points = ["0", "0"];
        const res = validateQuadraticVoteRequest(body);
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/proof/);
    });
});
