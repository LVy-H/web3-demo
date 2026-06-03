import { describe, it, expect } from "vitest";
import { validateSurveyVoteRequest } from "../src/validation";

// A poll address; its decimal form is the expected proof.scope.
const POLL = "0x00000000000000000000000000000000000000ff";
const POLL_SCOPE = BigInt(POLL).toString(); // "255"

// A realistic survey `message`: the keccak commitment keccak256(abi.encode([2,5]))
// >> 8 (a 248-bit wide field element, < BN254 r). This is the value a real client
// binds; the relayer must ACCEPT it WITHOUT recomputing it from `answers`. Its
// exact value is irrelevant — what matters is that it is wide and non-zero, and
// that it does NOT equal String(answers). Decimal, on the wire.
const WIDE_COMMITMENT =
    "31337000000000000000000000000000000000000000000000000000000000000000000000";

/** Build a well-formed survey-vote request body for a given answer vector, with a
 *  proof whose message is a WIDE non-zero commitment (NOT String(answers)) and a
 *  matching scope by default (override either to test rejection). The default
 *  message deliberately differs from `answers` to prove the relayer never binds
 *  message to the ballot. */
function makeBody(opts: {
    pollAddress?: string;
    answers?: unknown;
    message?: string;
    scope?: string;
}) {
    const answers = opts.answers ?? ["2", "5"]; // Q0 single-choice=2, Q1 bitmask=5
    return {
        pollAddress: opts.pollAddress ?? POLL,
        answers,
        proof: {
            merkleTreeDepth: 1,
            merkleTreeRoot: "123",
            nullifier: "456",
            message: opts.message ?? WIDE_COMMITMENT,
            scope: opts.scope ?? POLL_SCOPE,
            points: Array(8).fill("0"),
        },
    };
}

describe("validateSurveyVoteRequest", () => {
    it("accepts a valid survey request (wide non-zero commitment message, matching scope)", () => {
        const res = validateSurveyVoteRequest(makeBody({}));
        expect(res.ok).toBe(true);
        if (res.ok) {
            expect(res.data.answers).toEqual(["2", "5"]);
            expect(res.data.pollAddress).toBe(POLL);
        }
    });

    it("accepts numeric answers and normalizes them to decimal strings", () => {
        const res = validateSurveyVoteRequest(makeBody({ answers: [2, 5] }));
        expect(res.ok).toBe(true);
        if (res.ok) expect(res.data.answers).toEqual(["2", "5"]);
    });

    it("rejects a non-object body", () => {
        expect(validateSurveyVoteRequest(null).ok).toBe(false);
        expect(validateSurveyVoteRequest("nope").ok).toBe(false);
    });

    it("rejects an invalid pollAddress", () => {
        const res = validateSurveyVoteRequest(makeBody({ pollAddress: "not-an-address" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/pollAddress/);
    });

    it("rejects a missing answers field", () => {
        const body = makeBody({});
        delete (body as { answers?: unknown }).answers;
        const res = validateSurveyVoteRequest(body);
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/answers/);
    });

    it("rejects an empty answers array", () => {
        const res = validateSurveyVoteRequest(makeBody({ answers: [] }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/non-empty/);
    });

    it("rejects a non-array answers field", () => {
        const res = validateSurveyVoteRequest(makeBody({ answers: "2,5" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/answers/);
    });

    it("rejects an out-of-range answer value (>= 2^256)", () => {
        const big = (1n << 256n).toString(); // exactly 2^256, just out of range
        const res = validateSurveyVoteRequest(makeBody({ answers: ["2", big] }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/index 1|2\^256/);
    });

    it("rejects a negative or non-integer answer value", () => {
        expect(validateSurveyVoteRequest(makeBody({ answers: ["2", "-1"] })).ok).toBe(false);
        expect(validateSurveyVoteRequest(makeBody({ answers: [2, 1.5] })).ok).toBe(false);
        expect(validateSurveyVoteRequest(makeBody({ answers: ["2", "0x5"] })).ok).toBe(false);
    });

    it("rejects when proof.scope != pollAddress", () => {
        const res = validateSurveyVoteRequest(makeBody({ scope: "999999" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/scope does not match/);
    });

    it("rejects a malformed proof (points not length 8)", () => {
        const body = makeBody({});
        (body.proof as { points: string[] }).points = ["0", "0"];
        const res = validateSurveyVoteRequest(body);
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/proof/);
    });

    // ── The KEY survey-specific assertions ──────────────────────────────────
    // The message is a keccak COMMITMENT the contract recomputes and binds — the
    // relayer's check is SHAPE-ONLY (non-zero in-field element), NOT
    // `message === String(answers)`. These two tests prove exactly that.

    it("rejects message = '0' (a zero commitment is never valid)", () => {
        const res = validateSurveyVoteRequest(makeBody({ message: "0" }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/non-zero field element/);
    });

    it("ACCEPTS a wide non-zero commitment message that does NOT equal String(answers)", () => {
        // This is the load-bearing survey assertion: with answers = [2, 5], the
        // message is a 248-bit commitment (NOT "2,5", NOT "2", NOT "5"). The
        // relayer accepts it precisely because it does NOT bind message to answers
        // and does NOT recompute the commitment — that is the contract's job.
        expect(WIDE_COMMITMENT).not.toBe("2");
        expect(WIDE_COMMITMENT).not.toBe(JSON.stringify(["2", "5"]));
        const res = validateSurveyVoteRequest(makeBody({ message: WIDE_COMMITMENT }));
        expect(res.ok).toBe(true);
        if (res.ok) expect(res.data.proof.message).toBe(WIDE_COMMITMENT);
    });

    it("rejects a message at or above the BN254 field order (out of field)", () => {
        // r itself is out of field ([0, r) is valid); r is just above the max
        // 248-bit commitment so this is a clean over-the-edge case.
        const R = "21888242871839275222246405745257275088548364400416034343698204186575808495617";
        const res = validateSurveyVoteRequest(makeBody({ message: R }));
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/field element/);
    });
});
