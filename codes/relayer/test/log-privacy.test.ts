// Regression tests for the privacy-by-design logging mandate (spec §5):
// the relayer must NEVER log ballot contents. These tests spy on console.log /
// console.error, relay one ballot through every vote route (success AND error
// paths), and assert the ballot value never appears in anything logged.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import request from "supertest";

// Mock the chain-facing relay layer so no node is needed. vi.mock is hoisted
// above the imports, so createApp() below picks up these stubs.
vi.mock("../src/relay", () => ({
    relayCastVote: vi.fn(async () => ({ txHash: "0xfeed" })),
    relayApprovalVote: vi.fn(async () => ({ txHash: "0xfeed" })),
    relayRankedVote: vi.fn(async () => ({ txHash: "0xfeed" })),
    relayQuadraticVote: vi.fn(async () => ({ txHash: "0xfeed" })),
    relaySurveyVote: vi.fn(async () => ({ txHash: "0xfeed" })),
    relayClaimAirdrop: vi.fn(async () => ({ txHash: "0xfeed" })),
    relayCreatePoll: vi.fn(),
    relayRegisterVoter: vi.fn(),
    relayStartVoting: vi.fn(),
    checkRelayerBalance: vi.fn(async () => ({ sufficient: true, balance: "1.0" })),
    ClientFacingError: class ClientFacingError extends Error {},
}));

import { createApp } from "../src/app";
import { relayCastVote } from "../src/relay";

const POLL = "0x00000000000000000000000000000000000000ff";
const POLL_SCOPE = BigInt(POLL).toString(); // "255"

/** A well-formed Semaphore proof whose message binds the given ballot value. */
function makeProof(message: string) {
    return {
        merkleTreeDepth: 1,
        merkleTreeRoot: "123",
        nullifier: "456",
        message,
        scope: POLL_SCOPE,
        points: Array(8).fill("0"),
    };
}

// Distinctive sentinel ballot values: none of these substrings can occur in the
// expected log lines ("[RELAY] <route> → poll=0x…ff" / "[RELAY] ✓ txHash=0xfeed"),
// so a plain containment check is a reliable leak detector.
const SENTINELS = {
    vote: 6,
    bitmask: 13,
    packedRanking: 4660, // 0x1234 → slots [4,3,2,1]
    packedAlloc: 33, //     0x21   → slots [1,2]
    answers: ["987654321", "424242424242"],
};

const BALLOT_KEY_PATTERN = /vote=|bitmask=|packedRanking=|packedAlloc=|answers=|proof=/;

let logSpy: ReturnType<typeof vi.spyOn>;
let errorSpy: ReturnType<typeof vi.spyOn>;

/** Everything logged (any level) since the spies were installed, as one string. */
function allLogged(): string {
    return [...logSpy.mock.calls, ...errorSpy.mock.calls]
        .map((args) => args.map((a) => String(a)).join(" "))
        .join("\n");
}

function expectNoBallotInLogs(...sentinels: string[]) {
    const logged = allLogged();
    expect(logged).not.toMatch(BALLOT_KEY_PATTERN);
    for (const s of sentinels) {
        expect(logged).not.toContain(s);
    }
}

beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
});

afterEach(() => {
    vi.restoreAllMocks();
});

describe("relay routes never log ballot contents", () => {
    it("POST /api/relay/vote logs the poll but not the vote", async () => {
        const res = await request(createApp()).post("/api/relay/vote").send({
            pollAddress: POLL,
            vote: SENTINELS.vote,
            proof: makeProof(String(SENTINELS.vote)),
        });
        expect(res.status).toBe(200);
        expect(allLogged()).toContain(`poll=${POLL}`); // log stays operationally useful
        expectNoBallotInLogs(String(SENTINELS.vote));
    });

    it("POST /api/relay/approval-vote logs the poll but not the bitmask", async () => {
        const res = await request(createApp()).post("/api/relay/approval-vote").send({
            pollAddress: POLL,
            bitmask: SENTINELS.bitmask,
            proof: makeProof(String(SENTINELS.bitmask)),
        });
        expect(res.status).toBe(200);
        expectNoBallotInLogs(String(SENTINELS.bitmask));
    });

    it("POST /api/relay/ranked-vote logs the poll but not the packed ranking", async () => {
        const res = await request(createApp()).post("/api/relay/ranked-vote").send({
            pollAddress: POLL,
            packedRanking: SENTINELS.packedRanking,
            proof: makeProof(String(SENTINELS.packedRanking)),
        });
        expect(res.status).toBe(200);
        expectNoBallotInLogs(String(SENTINELS.packedRanking));
    });

    it("POST /api/relay/quadratic-vote logs the poll but not the packed allocation", async () => {
        const res = await request(createApp()).post("/api/relay/quadratic-vote").send({
            pollAddress: POLL,
            packedAlloc: SENTINELS.packedAlloc,
            proof: makeProof(String(SENTINELS.packedAlloc)),
        });
        expect(res.status).toBe(200);
        expectNoBallotInLogs(String(SENTINELS.packedAlloc));
    });

    it("POST /api/relay/survey-vote logs the poll but not the answer vector", async () => {
        const res = await request(createApp()).post("/api/relay/survey-vote").send({
            pollAddress: POLL,
            answers: SENTINELS.answers,
            proof: makeProof("12345"), // survey message is a keccak commitment (shape-only check)
        });
        expect(res.status).toBe(200);
        expectNoBallotInLogs(...SENTINELS.answers);
    });

    it("the /vote ERROR path logs the failure but not the ballot", async () => {
        vi.mocked(relayCastVote).mockRejectedValueOnce(
            new Error("Poll is not in voting phase")
        );
        const res = await request(createApp()).post("/api/relay/vote").send({
            pollAddress: POLL,
            vote: SENTINELS.vote,
            proof: makeProof(String(SENTINELS.vote)),
        });
        expect(res.status).toBe(500);
        expect(errorSpy).toHaveBeenCalled(); // failure is still logged…
        expectNoBallotInLogs(String(SENTINELS.vote)); // …without the ballot
    });
});
