import { describe, it, expect } from "vitest";
import { validateRankedVoteRequest } from "../src/validation";

// A poll address; its decimal form is the expected proof.scope.
const POLL = "0x00000000000000000000000000000000000000ff";
const POLL_SCOPE = BigInt(POLL).toString(); // "255"

/** Build a well-formed ranked-vote request body for a given packed ranking, with
 *  a proof whose message/scope match by default (override to test rejection). */
function makeBody(opts: {
    pollAddress?: string;
    packedRanking?: unknown;
    message?: string;
    scope?: string;
}) {
    const packedRanking = opts.packedRanking ?? 0x21; // slot0=1 (A), slot1=2 (B): B-ranked-second
    return {
        pollAddress: opts.pollAddress ?? POLL,
        packedRanking,
        proof: {
            merkleTreeDepth: 1,
            merkleTreeRoot: "123",
            nullifier: "456",
            message: opts.message ?? String(packedRanking),
            scope: opts.scope ?? POLL_SCOPE,
            points: Array(8).fill("0"),
        },
    };
}

describe("validateRankedVoteRequest", () => {
    it("accepts a valid packed ranking whose proof message+scope match", () => {
        const res = validateRankedVoteRequest(makeBody({ packedRanking: 0x321 })); // A>B>C
        expect(res.ok).toBe(true);
        if (res.ok) {
            expect(res.data.packedRanking).toBe(0x321);
            expect(res.data.pollAddress).toBe(POLL);
        }
    });

    it("rejects a non-object body", () => {
        expect(validateRankedVoteRequest(null).ok).toBe(false);
        expect(validateRankedVoteRequest("nope").ok).toBe(false);
    });

    it("rejects an invalid pollAddress", () => {
        const res = validateRankedVoteRequest(makeBody({ pollAddress: "not-an-address" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/pollAddress/);
    });

    it("rejects an empty ballot (packedRanking 0)", () => {
        const res = validateRankedVoteRequest(makeBody({ packedRanking: 0, message: "0" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/empty ballot|> 0/);
    });

    it("rejects a negative or non-integer packedRanking", () => {
        expect(validateRankedVoteRequest(makeBody({ packedRanking: -1, message: "-1" })).ok).toBe(false);
        expect(validateRankedVoteRequest(makeBody({ packedRanking: 1.5, message: "1.5" })).ok).toBe(false);
        expect(validateRankedVoteRequest(makeBody({ packedRanking: "3", message: "3" })).ok).toBe(false);
    });

    it("rejects a packedRanking that overflows 32 bits (>= 2^32)", () => {
        const big = 2 ** 32;
        const res = validateRankedVoteRequest(makeBody({ packedRanking: big, message: String(big) }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/32 bits/);
    });

    it("accepts the maximal in-range packed value (2^32 - 1)", () => {
        // The relayer only bounds the word, not slot structure — the contract
        // owns prefix/distinct/range. 2^32 - 1 fits and round-trips as a number.
        const max = 2 ** 32 - 1;
        const res = validateRankedVoteRequest(makeBody({ packedRanking: max, message: String(max) }));
        expect(res.ok).toBe(true);
    });

    it("rejects when proof.message != packedRanking (tamper guard)", () => {
        const res = validateRankedVoteRequest(makeBody({ packedRanking: 0x321, message: "3" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/message.*does not match packedRanking/);
    });

    it("rejects when proof.scope != pollAddress", () => {
        const res = validateRankedVoteRequest(makeBody({ packedRanking: 1, scope: "999999" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/scope does not match/);
    });

    it("rejects a malformed proof (points not length 8)", () => {
        const body = makeBody({ packedRanking: 1 });
        (body.proof as { points: string[] }).points = ["0", "0"];
        const res = validateRankedVoteRequest(body);
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/proof/);
    });
});
