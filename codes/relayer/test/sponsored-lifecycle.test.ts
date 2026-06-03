import { describe, it, expect, afterEach } from "vitest";
import request from "supertest";
import { ethers } from "ethers";
import { createApp } from "../src/app";
import {
    validateCreatePollRequest,
    validateRegisterVoterRequest,
    validateStartVotingRequest,
    SPONSORED_MODULE_TYPES,
} from "../src/validation";

// The relayer signer address for the throwaway Hardhat account #0 key set in
// test/setup.ts. Every sponsored poll must be owned by THIS address.
const RELAYER = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const SEMAPHORE = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
const SOMEONE_ELSE = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"; // Hardhat acct #1
const POLL = "0x00000000000000000000000000000000000000ff";

/** Encode a real `initialize(address semaphore, address owner, string[] options)`
 *  call exactly as the Flutter client does (web3dart `encodeCall`) — selector +
 *  ABI args. `owner` is the load-bearing 2nd word the relayer validates. */
function encodeAnonInitData(owner: string, options = ["Yes", "No"]): string {
    const iface = new ethers.Interface(["function initialize(address,address,string[])"]);
    return iface.encodeFunctionData("initialize", [SEMAPHORE, owner, options]);
}

/** Encode the SURVEY initialize shape `initialize(address,address,bytes)` — the
 *  owner is STILL the 2nd word, proving the decode is module-agnostic. */
function encodeSurveyInitData(owner: string): string {
    const iface = new ethers.Interface(["function initialize(address,address,bytes)"]);
    return iface.encodeFunctionData("initialize", [SEMAPHORE, owner, "0x1234"]);
}

// ── 1. Pure validator unit tests (no app, no chain) ─────────────────────────

describe("validateCreatePollRequest", () => {
    it("accepts a well-formed request whose initData owner == relayer", () => {
        const res = validateCreatePollRequest(
            {
                moduleType: "anon-vote",
                title: "Lunch?",
                description: "Where to eat",
                initData: encodeAnonInitData(RELAYER),
            },
            RELAYER
        );
        expect(res.ok).toBe(true);
        if (res.ok) expect(res.data.moduleType).toBe("anon-vote");
    });

    it("accepts a relayer-owned poll regardless of address checksum casing", () => {
        const res = validateCreatePollRequest(
            {
                moduleType: "anon-vote",
                title: "x",
                description: "",
                initData: encodeAnonInitData(RELAYER.toLowerCase()),
            },
            RELAYER
        );
        expect(res.ok).toBe(true);
    });

    it("accepts the survey initialize shape (owner is still the 2nd word)", () => {
        const res = validateCreatePollRequest(
            {
                moduleType: "survey-vote",
                title: "Survey",
                description: "",
                initData: encodeSurveyInitData(RELAYER),
            },
            RELAYER
        );
        expect(res.ok).toBe(true);
    });

    // THE load-bearing security test: a poll owned by anyone but the relayer is
    // REJECTED so the relayer never pays gas for a poll it can't register/start.
    it("REJECTS when the initData owner word is NOT the relayer", () => {
        const res = validateCreatePollRequest(
            {
                moduleType: "anon-vote",
                title: "x",
                description: "",
                initData: encodeAnonInitData(SOMEONE_ELSE),
            },
            RELAYER
        );
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/owner|relayer/i);
    });

    it("rejects an unknown moduleType before any gas is spent", () => {
        const res = validateCreatePollRequest(
            {
                moduleType: "blind-vote", // not offered in the sponsored flow
                title: "x",
                description: "",
                initData: encodeAnonInitData(RELAYER),
            },
            RELAYER
        );
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/Unknown moduleType/);
    });

    it("rejects an empty title", () => {
        const res = validateCreatePollRequest(
            { moduleType: "anon-vote", title: "   ", description: "", initData: encodeAnonInitData(RELAYER) },
            RELAYER
        );
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/title/);
    });

    it("rejects an over-long title (anti-bloat cap)", () => {
        const res = validateCreatePollRequest(
            { moduleType: "anon-vote", title: "a".repeat(201), description: "", initData: encodeAnonInitData(RELAYER) },
            RELAYER
        );
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/title/);
    });

    it("rejects an over-long description (anti-bloat cap)", () => {
        const res = validateCreatePollRequest(
            { moduleType: "anon-vote", title: "ok", description: "d".repeat(2001), initData: encodeAnonInitData(RELAYER) },
            RELAYER
        );
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/description/);
    });

    it("rejects non-hex / too-short initData", () => {
        for (const bad of ["not-hex", "0xZZ", "0x1234", "", "0xabc"]) {
            const res = validateCreatePollRequest(
                { moduleType: "anon-vote", title: "ok", description: "", initData: bad },
                RELAYER
            );
            expect(res.ok).toBe(false);
        }
    });

    it("rejects initData with a dirty (non-address) owner word", () => {
        // selector + a semaphore word + a word with the high bytes set (not a
        // clean left-padded address) ⇒ AbiCoder rejects it.
        const dirty = "0x11223344" + "00".repeat(32) + "ff".repeat(32);
        const res = validateCreatePollRequest(
            { moduleType: "anon-vote", title: "ok", description: "", initData: dirty },
            RELAYER
        );
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/initData/);
    });

    it("rejects a non-object body", () => {
        expect(validateCreatePollRequest(null, RELAYER).ok).toBe(false);
        expect(validateCreatePollRequest("nope", RELAYER).ok).toBe(false);
    });

    it("exposes the canonical sponsored module allow-list (no blind-vote)", () => {
        expect([...SPONSORED_MODULE_TYPES]).toEqual([
            "anon-vote",
            "approval-vote",
            "ranked-vote",
            "quadratic-vote",
            "survey-vote",
        ]);
        expect((SPONSORED_MODULE_TYPES as readonly string[]).includes("blind-vote")).toBe(false);
    });
});

describe("validateRegisterVoterRequest", () => {
    const COMMITMENT = "12345678901234567890";

    it("accepts a valid pollAddress + non-zero in-field commitment", () => {
        const res = validateRegisterVoterRequest({ pollAddress: POLL, identityCommitment: COMMITMENT });
        expect(res.ok).toBe(true);
        if (res.ok) expect(res.data.identityCommitment).toBe(COMMITMENT);
    });

    it("rejects an invalid pollAddress", () => {
        const res = validateRegisterVoterRequest({ pollAddress: "nope", identityCommitment: COMMITMENT });
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/pollAddress/);
    });

    it("rejects a zero commitment", () => {
        const res = validateRegisterVoterRequest({ pollAddress: POLL, identityCommitment: "0" });
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/field element/);
    });

    it("rejects a commitment at/above the BN254 field order", () => {
        const R = "21888242871839275222246405745257275088548364400416034343698204186575808495617";
        const res = validateRegisterVoterRequest({ pollAddress: POLL, identityCommitment: R });
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/field element/);
    });

    it("rejects a non-decimal / hex commitment", () => {
        for (const bad of ["0x5", "abc", "-1", "1.5", ""]) {
            expect(validateRegisterVoterRequest({ pollAddress: POLL, identityCommitment: bad }).ok).toBe(false);
        }
    });

    it("rejects a non-object body", () => {
        expect(validateRegisterVoterRequest(null).ok).toBe(false);
    });
});

describe("validateStartVotingRequest", () => {
    it("accepts a valid pollAddress", () => {
        const res = validateStartVotingRequest({ pollAddress: POLL });
        expect(res.ok).toBe(true);
        if (res.ok) expect(res.data.pollAddress).toBe(POLL);
    });

    it("rejects an invalid pollAddress", () => {
        const res = validateStartVotingRequest({ pollAddress: "nope" });
        expect(res.ok).toBe(false);
        if (!res.ok) expect(res.error).toMatch(/pollAddress/);
    });

    it("rejects a non-object body", () => {
        expect(validateStartVotingRequest(null).ok).toBe(false);
    });
});

// ── 2. Route + abuse-guard tests via supertest (no chain) ───────────────────
//
// These exercise the routing, the create-secret gate, and the per-IP / per-poll
// caps. They set REGISTRY_ADDRESS so create-poll gets PAST the "not configured"
// guard and reaches the secret/validation layers (which return BEFORE any chain
// call, so no node is needed). createApp() builds fresh in-memory counters each
// time, so the caps are deterministic per app instance.

describe("sponsored-lifecycle routes + abuse guards", () => {
    const ORIGINAL_REGISTRY = process.env.REGISTRY_ADDRESS;
    const ORIGINAL_SECRET = process.env.CREATE_SECRET;
    const ORIGINAL_REG_CAP = process.env.REGISTER_PER_POLL_MAX;

    // A real registry address is irrelevant for these tests — the requests are
    // rejected at the secret/validation layer before any tx. We set it only so
    // the route doesn't 503 "not configured".
    const REGISTRY = "0x5FbDB2315678afecb367f032d93F642f64180aa3";

    function restore(key: string, original: string | undefined) {
        if (original === undefined) delete process.env[key];
        else process.env[key] = original;
    }
    afterEach(() => {
        restore("REGISTRY_ADDRESS", ORIGINAL_REGISTRY);
        restore("CREATE_SECRET", ORIGINAL_SECRET);
        restore("REGISTER_PER_POLL_MAX", ORIGINAL_REG_CAP);
    });

    /** Build a fresh app. config getters read env LIVE (getRegistryAddress /
     *  getCreateSecret / getRegisterPerPollMax), and createApp() builds fresh
     *  in-memory limiter counters, so `set env → newApp()` needs NO module
     *  re-import. Each test starts with create open (CREATE_SECRET cleared) and
     *  the registry configured unless it overrides them first. */
    function newApp() {
        delete process.env.CREATE_SECRET;
        process.env.REGISTRY_ADDRESS = REGISTRY;
        return createApp();
    }

    it("GET /api/relay/info returns the relayer + registry addresses", async () => {
        const app = newApp();
        const res = await request(app).get("/api/relay/info");
        expect(res.status).toBe(200);
        expect(ethers.getAddress(res.body.relayer)).toBe(RELAYER);
        expect(ethers.getAddress(res.body.registry)).toBe(ethers.getAddress(REGISTRY));
    });

    it("GET /api/relay/info reports registry=null when REGISTRY_ADDRESS is unset", async () => {
        delete process.env.REGISTRY_ADDRESS;
        delete process.env.CREATE_SECRET;
        const app = createApp();
        const res = await request(app).get("/api/relay/info");
        expect(res.status).toBe(200);
        expect(res.body.registry).toBeNull();
    });

    it("create-poll 503s when no registry is configured", async () => {
        delete process.env.REGISTRY_ADDRESS;
        delete process.env.CREATE_SECRET;
        const app = createApp();
        const res = await request(app)
            .post("/api/relay/create-poll")
            .send({ moduleType: "anon-vote", title: "x", description: "", initData: encodeAnonInitData(RELAYER) });
        expect(res.status).toBe(503);
        expect(res.body.error).toMatch(/isn't configured/i);
    });

    it("create-poll rejects (400) when the initData owner != relayer", async () => {
        const app = newApp();
        const res = await request(app)
            .post("/api/relay/create-poll")
            .send({
                moduleType: "anon-vote",
                title: "x",
                description: "",
                initData: encodeAnonInitData(SOMEONE_ELSE),
            });
        expect(res.status).toBe(400);
        expect(res.body.error).toMatch(/owner|relayer/i);
    });

    it("create-poll rejects (400) an unknown moduleType", async () => {
        const app = newApp();
        const res = await request(app)
            .post("/api/relay/create-poll")
            .send({
                moduleType: "totally-made-up",
                title: "x",
                description: "",
                initData: encodeAnonInitData(RELAYER),
            });
        expect(res.status).toBe(400);
        expect(res.body.error).toMatch(/moduleType/);
    });

    it("create-poll is OPEN when CREATE_SECRET is unset (request passes the secret gate)", async () => {
        const app = newApp(); // newApp deletes CREATE_SECRET
        // Owner != relayer ⇒ we expect a 400 from VALIDATION, proving we passed
        // the secret gate (a 401 would mean the gate blocked us).
        const res = await request(app)
            .post("/api/relay/create-poll")
            .send({
                moduleType: "anon-vote",
                title: "x",
                description: "",
                initData: encodeAnonInitData(SOMEONE_ELSE),
            });
        expect(res.status).toBe(400);
        expect(res.status).not.toBe(401);
    });

    it("create-poll requires X-Create-Secret when CREATE_SECRET is set", async () => {
        const app = newApp();
        process.env.CREATE_SECRET = "s3cret"; // read live by getCreateSecret()
        const body = {
            moduleType: "anon-vote",
            title: "x",
            description: "",
            initData: encodeAnonInitData(RELAYER),
        };
        // Missing header ⇒ 401
        const noHeader = await request(app).post("/api/relay/create-poll").send(body);
        expect(noHeader.status).toBe(401);
        // Wrong header ⇒ 401
        const wrong = await request(app)
            .post("/api/relay/create-poll")
            .set("X-Create-Secret", "nope")
            .send(body);
        expect(wrong.status).toBe(401);
        // Correct header ⇒ passes the gate (then hits balance/chain → 5xx, NOT 401)
        const right = await request(app)
            .post("/api/relay/create-poll")
            .set("X-Create-Secret", "s3cret")
            .send(body);
        expect(right.status).not.toBe(401);
    });

    it("create-poll enforces a per-IP daily cap (Decision 3)", async () => {
        // CREATE_DAILY_MAX defaults to 5. The 6th create from one IP is capped
        // (429) regardless of body validity (the limiter counts all attempts).
        const app = newApp();
        const body = {
            moduleType: "anon-vote",
            title: "x",
            description: "",
            initData: encodeAnonInitData(SOMEONE_ELSE), // 400 at validation, still counts
        };
        for (let i = 0; i < 5; i++) {
            const r = await request(app).post("/api/relay/create-poll").send(body);
            expect(r.status).not.toBe(429);
        }
        const capped = await request(app).post("/api/relay/create-poll").send(body);
        expect(capped.status).toBe(429);
    });

    it("register-voter enforces a per-(IP, pollAddress) cap (Decision 3)", async () => {
        // Lower REGISTER_PER_POLL_MAX via env; getRegisterPerPollMax() reads it
        // LIVE at createApp(), so no module re-import is needed.
        process.env.REGISTER_PER_POLL_MAX = "3";
        const app = newApp();

        const body = { pollAddress: POLL, identityCommitment: "12345" };
        for (let i = 0; i < 3; i++) {
            const r = await request(app).post("/api/relay/register-voter").send(body);
            expect(r.status).not.toBe(429);
        }
        const capped = await request(app).post("/api/relay/register-voter").send(body);
        expect(capped.status).toBe(429);

        // A DIFFERENT poll from the same IP is a different key ⇒ not capped.
        const otherPoll = await request(app)
            .post("/api/relay/register-voter")
            .send({ pollAddress: "0x1111111111111111111111111111111111111111", identityCommitment: "12345" });
        expect(otherPoll.status).not.toBe(429);
    });

    it("register-voter rejects (400) a bad commitment before any chain call", async () => {
        const app = newApp();
        const res = await request(app)
            .post("/api/relay/register-voter")
            .send({ pollAddress: POLL, identityCommitment: "0" });
        expect(res.status).toBe(400);
        expect(res.body.error).toMatch(/field element/);
    });

    it("start-voting rejects (400) an invalid pollAddress before any chain call", async () => {
        const app = newApp();
        const res = await request(app).post("/api/relay/start-voting").send({ pollAddress: "nope" });
        expect(res.status).toBe(400);
        expect(res.body.error).toMatch(/pollAddress/);
    });

    it("does NOT touch the existing /status route or the 5 vote routes (smoke)", async () => {
        const app = newApp();
        // /status still exists and is distinct from /info.
        const status = await request(app).get("/api/relay/status");
        // It hits the chain for a balance read; in this no-guaranteed-node env it
        // may 200 (node up) or 500 (no node) — either way the route EXISTS (not 404).
        expect(status.status).not.toBe(404);
        // The vote route still exists and validates (400 on empty body, not 404).
        const vote = await request(app).post("/api/relay/vote").send({});
        expect(vote.status).toBe(400);
    });
});

// ── 3. The money test: full wallet-free lifecycle e2e (chain-gated) ─────────
//
// This drives the REAL sponsored loop end-to-end with NO wallet and NO
// dev-signer: create-poll (anon, owner=relayer) → register-voter (a test
// commitment) → start-voting → vote (existing path) → assert the on-chain tally.
//
// It runs ONLY when REGISTRY_ADDRESS points at a deployed PollRegistry whose
// modules are registered and whose owner is the relayer signer (the throwaway
// Hardhat acct #0 key from setup.ts) — i.e. a `npm run deploy:local` stack on
// RPC_URL. The existing relayer test harness is validation-only and does NOT
// stand up a chain (test/setup.ts only sets env vars), so in CI / this env the
// suite reports a clean SKIP rather than a vacuous pass. The MockSemaphoreVerifier
// deployed locally accepts ANY proof, so dummy proof points suffice as long as
// message==String(vote), scope==BigInt(pollAddress), and the nullifier is fresh.
describe.runIf(!!process.env.REGISTRY_ADDRESS)("wallet-free lifecycle e2e (live chain)", () => {
    it("create → register → start → vote, fully sponsored, asserts the tally", async () => {
        const mod = await import("../src/app");
        const app = mod.createApp();
        const { ethers: E } = await import("ethers");

        // 1. CREATE — owner = relayer, fetched from /info (the client never needs
        //    its own wallet; it just asks the relayer who to set as owner).
        const info = await request(app).get("/api/relay/info");
        const relayerAddr: string = info.body.relayer;
        const iface = new E.Interface(["function initialize(address,address,string[])"]);
        const RPC = process.env.RPC_URL || "http://127.0.0.1:8545";
        const provider = new E.JsonRpcProvider(RPC);
        // The semaphore address baked into initData must be the one the deployed
        // modules use; we read it back from the created poll, so any value the
        // module's initialize accepts works — we pass the deployed Semaphore via
        // SEMAPHORE_ADDRESS if provided, else fall back to the registry's known one.
        const semaphore = process.env.SEMAPHORE_ADDRESS || SEMAPHORE;
        const initData = iface.encodeFunctionData("initialize", [semaphore, relayerAddr, ["Yes", "No"]]);

        const created = await request(app)
            .post("/api/relay/create-poll")
            .send({ moduleType: "anon-vote", title: "e2e poll", description: "", initData });
        expect(created.status).toBe(200);
        const pollAddress: string = created.body.pollAddress;
        expect(E.isAddress(pollAddress)).toBe(true);

        // 2. REGISTER — a test identity commitment (any non-zero in-field value;
        //    the mock verifier doesn't bind it to a real Semaphore identity).
        const commitment = "1111111111111111111111111111111111111111";
        const reg = await request(app)
            .post("/api/relay/register-voter")
            .send({ pollAddress, identityCommitment: commitment });
        expect(reg.status).toBe(200);

        // 3. START VOTING — the creator's "Open voting" action.
        const start = await request(app).post("/api/relay/start-voting").send({ pollAddress });
        expect(start.status).toBe(200);

        // 4. VOTE — the EXISTING sponsored path. With the mock verifier any proof
        //    is accepted; the relayer's own validators require message==vote and
        //    scope==BigInt(poll).
        const vote = 1; // "No"
        const scope = E.toBigInt(pollAddress).toString();
        const voteRes = await request(app)
            .post("/api/relay/vote")
            .send({
                pollAddress,
                vote,
                proof: {
                    merkleTreeDepth: 1,
                    merkleTreeRoot: "1",
                    nullifier: "999",
                    message: String(vote),
                    scope,
                    points: Array(8).fill("0"),
                },
            });
        expect(voteRes.status).toBe(200);

        // 5. ASSERT THE ON-CHAIN TALLY — option 1 ("No") should have 1 vote.
        const poll = new E.Contract(
            pollAddress,
            ["function getResults() view returns (uint256[])"],
            provider
        );
        const results: bigint[] = await poll.getResults();
        expect(Number(results[vote])).toBe(1);
    }, 60_000);
});
