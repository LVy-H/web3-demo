import express from "express";
import cors from "cors";
import rateLimit from "express-rate-limit";
import { config, getCreateSecret, getRegistryAddress, getCreateDailyMax, getRegisterPerPollMax } from "./config";
import { relayCastVote, relayApprovalVote, relayRankedVote, relayQuadraticVote, relaySurveyVote, relayClaimAirdrop, relayCreatePoll, relayRegisterVoter, relayStartVoting, checkRelayerBalance } from "./relay";
import { getRelayerInfo, getRelayerWallet } from "./wallet";
import { validateVoteRequest, validateApprovalVoteRequest, validateRankedVoteRequest, validateQuadraticVoteRequest, validateSurveyVoteRequest, validateClaimRequest, validateCreatePollRequest, validateRegisterVoterRequest, validateStartVotingRequest } from "./validation";
import { createTicketRouter } from "./tickets";

/** Build the Express app WITHOUT listening, so tests (supertest) can import it
 *  and the bootstrap (index.ts) can add app.listen separately. */
export function createApp(): express.Express {
    const app = express();

    // Trust first proxy hop so express-rate-limit sees the real client IP
    // when running behind cloudflared / nginx / docker network.
    app.set("trust proxy", 1);

    app.use(cors());
    app.use(express.json());

    const limiter = rateLimit({
        windowMs: config.rateLimitWindowMs,
        max: config.rateLimitMax,
        standardHeaders: true,
        legacyHeaders: false,
        message: { error: "Too many requests. Please wait before trying again." },
    });
    app.use("/api/relay", limiter);

    // ── Abuse guards for the sponsored lifecycle (Decision 3) ───────────────
    // Constructed INSIDE createApp() so each app instance (and each test) starts
    // with clean in-memory counters. These are additive to the global limiter
    // above; the relayer pays gas for create/register, so they get tighter,
    // purpose-specific caps. NOTE: in-memory ⇒ they reset on process restart and
    // are per-instance (not shared across replicas). This is a LIGHT guard that
    // keeps a casual abuser from draining the relayer — it is NOT Sybil-resistant
    // (see the spec's "Honesty / trade-offs"). A production deployment needs more.

    // create-poll: a tight per-IP DAILY cap on top of the global 20/min window,
    // so one IP can't mint hundreds of sponsored polls (each costs the relayer
    // gas). Default 5/day/IP (config.createDailyMax).
    const createLimiter = rateLimit({
        windowMs: 24 * 60 * 60 * 1000, // 1 day
        max: getCreateDailyMax(),
        standardHeaders: true,
        legacyHeaders: false,
        message: { error: "Daily sponsored-poll creation limit reached. Try again tomorrow." },
    });

    // register-voter: a per-(IP, pollAddress) cap so one IP can't flood a single
    // poll's group with thousands of junk commitments. Keyed on ip + the poll the
    // body targets (express.json() has already parsed the body at this point).
    const registerLimiter = rateLimit({
        windowMs: 24 * 60 * 60 * 1000, // 1 day
        max: getRegisterPerPollMax(),
        standardHeaders: true,
        legacyHeaders: false,
        keyGenerator: (req) => {
            const ip = req.ip ?? "unknown";
            const poll =
                req.body && typeof req.body === "object" && typeof (req.body as Record<string, unknown>).pollAddress === "string"
                    ? ((req.body as Record<string, unknown>).pollAddress as string).toLowerCase()
                    : "no-poll";
            return `${ip}:${poll}`;
        },
        message: { error: "Too many join attempts for this poll from your network. Please wait." },
    });

    // ── POST /api/relay/vote ────────────────────────────────────────────────
    app.post("/api/relay/vote", async (req, res) => {
        try {
            const validation = validateVoteRequest(req.body);
            if (!validation.ok) {
                res.status(400).json({ error: validation.error });
                return;
            }

            const balanceCheck = await checkRelayerBalance();
            if (!balanceCheck.sufficient) {
                res.status(503).json({
                    error: "Relayer has insufficient funds to pay gas",
                    balance: balanceCheck.balance,
                });
                return;
            }

            const { pollAddress, vote, proof } = validation.data;
            console.log(`[RELAY] castVote → poll=${pollAddress} vote=${vote}`);

            const result = await relayCastVote(pollAddress, vote, proof);
            console.log(`[RELAY] ✓ txHash=${result.txHash}`);

            res.json({ success: true, txHash: result.txHash });
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(`[RELAY] ✗ castVote error:`, message);
            res.status(500).json({ error: "Internal relayer error" });
        }
    });

    // ── POST /api/relay/approval-vote ───────────────────────────────────────
    // Approval ballots (module "approval-vote"): the vote is a bitmask, and the
    // tally increments every approved option. Separate from /vote so the anon
    // single-option path is untouched.
    app.post("/api/relay/approval-vote", async (req, res) => {
        try {
            const validation = validateApprovalVoteRequest(req.body);
            if (!validation.ok) {
                res.status(400).json({ error: validation.error });
                return;
            }

            const balanceCheck = await checkRelayerBalance();
            if (!balanceCheck.sufficient) {
                res.status(503).json({
                    error: "Relayer has insufficient funds to pay gas",
                    balance: balanceCheck.balance,
                });
                return;
            }

            const { pollAddress, bitmask, proof } = validation.data;
            console.log(`[RELAY] approvalVote → poll=${pollAddress} bitmask=${bitmask}`);

            const result = await relayApprovalVote(pollAddress, bitmask, proof);
            console.log(`[RELAY] ✓ txHash=${result.txHash}`);

            res.json({ success: true, txHash: result.txHash });
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(`[RELAY] ✗ approvalVote error:`, message);
            res.status(500).json({ error: "Internal relayer error" });
        }
    });

    // ── POST /api/relay/ranked-vote ─────────────────────────────────────────
    // Ranked-choice ballots (module "ranked-vote"): the vote is a PACKED RANKING
    // (4-bit rank slots). The contract tallies round-1 first preferences only and
    // emits the full ballot; the IRV winner is computed OFF-CHAIN. Separate from
    // /vote and /approval-vote so those paths are untouched.
    app.post("/api/relay/ranked-vote", async (req, res) => {
        try {
            const validation = validateRankedVoteRequest(req.body);
            if (!validation.ok) {
                res.status(400).json({ error: validation.error });
                return;
            }

            const balanceCheck = await checkRelayerBalance();
            if (!balanceCheck.sufficient) {
                res.status(503).json({
                    error: "Relayer has insufficient funds to pay gas",
                    balance: balanceCheck.balance,
                });
                return;
            }

            const { pollAddress, packedRanking, proof } = validation.data;
            console.log(`[RELAY] rankedVote → poll=${pollAddress} packedRanking=${packedRanking}`);

            const result = await relayRankedVote(pollAddress, packedRanking, proof);
            console.log(`[RELAY] ✓ txHash=${result.txHash}`);

            res.json({ success: true, txHash: result.txHash });
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(`[RELAY] ✗ rankedVote error:`, message);
            res.status(500).json({ error: "Internal relayer error" });
        }
    });

    // ── POST /api/relay/quadratic-vote ──────────────────────────────────────
    // Quadratic ballots (module "quadratic-vote"): the vote is a PACKED ALLOCATION
    // (4-bit vote-count slots). The voter spends a uniform CREDITS budget where
    // casting vᵢ votes for option i costs vᵢ²; the contract enforces Σvᵢ² ≤ CREDITS
    // and tallies the votes per option. getResults() is the authoritative outcome.
    // Separate from /vote, /approval-vote, and /ranked-vote so those are untouched.
    app.post("/api/relay/quadratic-vote", async (req, res) => {
        try {
            const validation = validateQuadraticVoteRequest(req.body);
            if (!validation.ok) {
                res.status(400).json({ error: validation.error });
                return;
            }

            const balanceCheck = await checkRelayerBalance();
            if (!balanceCheck.sufficient) {
                res.status(503).json({
                    error: "Relayer has insufficient funds to pay gas",
                    balance: balanceCheck.balance,
                });
                return;
            }

            const { pollAddress, packedAlloc, proof } = validation.data;
            console.log(`[RELAY] quadraticVote → poll=${pollAddress} packedAlloc=${packedAlloc}`);

            const result = await relayQuadraticVote(pollAddress, packedAlloc, proof);
            console.log(`[RELAY] ✓ txHash=${result.txHash}`);

            res.json({ success: true, txHash: result.txHash });
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(`[RELAY] ✗ quadraticVote error:`, message);
            res.status(500).json({ error: "Internal relayer error" });
        }
    });

    // ── POST /api/relay/survey-vote ─────────────────────────────────────────
    // Survey ballots (module "survey-vote"): the vote is the FULL answer VECTOR
    // (`answers`: one uint256 word per question, in question order). The Semaphore
    // `message` is a keccak COMMITMENT — keccak256(abi.encode(answers)) >> 8 — that
    // the CONTRACT recomputes from calldata and binds. The relayer does NOT
    // recompute the commitment and does NOT bind message to answers (re-deriving it
    // in JS risks a Dart/JS/Solidity mismatch); its message check is SHAPE-ONLY (a
    // non-zero in-field element). Separate from the single-value paths above so
    // /vote, /approval-vote, /ranked-vote, /quadratic-vote are untouched.
    app.post("/api/relay/survey-vote", async (req, res) => {
        try {
            const validation = validateSurveyVoteRequest(req.body);
            if (!validation.ok) {
                res.status(400).json({ error: validation.error });
                return;
            }

            const balanceCheck = await checkRelayerBalance();
            if (!balanceCheck.sufficient) {
                res.status(503).json({
                    error: "Relayer has insufficient funds to pay gas",
                    balance: balanceCheck.balance,
                });
                return;
            }

            const { pollAddress, answers, proof } = validation.data;
            console.log(`[RELAY] surveyVote → poll=${pollAddress} answers=[${answers.join(",")}]`);

            const result = await relaySurveyVote(pollAddress, answers, proof);
            console.log(`[RELAY] ✓ txHash=${result.txHash}`);

            res.json({ success: true, txHash: result.txHash });
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(`[RELAY] ✗ surveyVote error:`, message);
            res.status(500).json({ error: "Internal relayer error" });
        }
    });

    // ── POST /api/relay/claim-airdrop ───────────────────────────────────────
    app.post("/api/relay/claim-airdrop", async (req, res) => {
        try {
            const validation = validateClaimRequest(req.body);
            if (!validation.ok) {
                res.status(400).json({ error: validation.error });
                return;
            }

            const balanceCheck = await checkRelayerBalance();
            if (!balanceCheck.sufficient) {
                res.status(503).json({
                    error: "Relayer has insufficient funds",
                    balance: balanceCheck.balance,
                });
                return;
            }

            const { airdropAddress, receiver, proof } = validation.data;
            console.log(`[RELAY] claimAirdrop → airdrop=${airdropAddress} receiver=${receiver}`);

            const result = await relayClaimAirdrop(airdropAddress, receiver, proof);
            console.log(`[RELAY] ✓ txHash=${result.txHash}`);

            res.json({ success: true, txHash: result.txHash });
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(`[RELAY] ✗ claimAirdrop error:`, message);
            res.status(500).json({ error: "Internal relayer error" });
        }
    });

    // ── GET /api/relay/info ─────────────────────────────────────────────────
    // Sponsored-lifecycle discovery: returns the relayer's SIGNER ADDRESS (the
    // client bakes this as the `owner` word inside initData so the relayer owns —
    // and can register/start — the poll) and the PollRegistry address. A separate
    // endpoint from /status (which stays byte-for-byte unchanged); this one does
    // not hit the chain (no balance read) so it's a cheap, cacheable lookup.
    app.get("/api/relay/info", (_req, res) => {
        try {
            const address = getRelayerWallet().address;
            res.json({
                relayer: address,
                registry: getRegistryAddress() ?? null,
            });
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(`[RELAY] ✗ info error:`, message);
            res.status(500).json({ error: "Internal relayer error" });
        }
    });

    // ── POST /api/relay/create-poll ─────────────────────────────────────────
    // Sponsored, wallet-free poll creation (Decision 1A custodial / 0B windowed).
    // The relayer clones + initializes a poll via PollRegistry.createPoll, paying
    // gas. The poll's owner (inside initData) MUST be the relayer — enforced in
    // validateCreatePollRequest and REJECTED (400) otherwise, so nobody can make
    // the relayer deploy a poll it can't run. Guard order: global limiter (above)
    // → daily create cap → optional X-Create-Secret → validation → balance → tx.
    app.post("/api/relay/create-poll", createLimiter, async (req, res) => {
        try {
            // Optional operator gate (Decision 3): when CREATE_SECRET is set, the
            // client must send a matching X-Create-Secret header. Read at request
            // time so a deployment can rotate it without an import. When unset
            // (local/dev), create is open. This is NOT Sybil-resistant.
            const secret = getCreateSecret();
            if (secret !== undefined) {
                const provided = req.header("X-Create-Secret");
                if (provided !== secret) {
                    res.status(401).json({ error: "Missing or invalid create secret" });
                    return;
                }
            }

            if (!getRegistryAddress()) {
                res.status(503).json({
                    error: "Sponsored poll creation isn't configured on this relayer.",
                });
                return;
            }

            const validation = validateCreatePollRequest(req.body, getRelayerWallet().address);
            if (!validation.ok) {
                res.status(400).json({ error: validation.error });
                return;
            }

            const balanceCheck = await checkRelayerBalance();
            if (!balanceCheck.sufficient) {
                res.status(503).json({
                    error: "Sponsored creation is temporarily paused (relayer is low on funds).",
                    balance: balanceCheck.balance,
                });
                return;
            }

            const { moduleType, title, description, initData } = validation.data;
            console.log(`[RELAY] createPoll → module=${moduleType} title=${JSON.stringify(title)}`);

            const result = await relayCreatePoll(moduleType, title, description, initData);
            console.log(`[RELAY] ✓ poll=${result.pollAddress} txHash=${result.txHash}`);

            res.json({ success: true, pollAddress: result.pollAddress, txHash: result.txHash });
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(`[RELAY] ✗ createPoll error:`, message);
            res.status(500).json({ error: "Could not create the poll. Please try again." });
        }
    });

    // ── POST /api/relay/register-voter ──────────────────────────────────────
    // Sponsored, wallet-free join (Decision 2A). The relayer (owner) registers a
    // voter's identity commitment, paying gas. Under 0B this only works while the
    // poll is in Registration — a clear "joining is closed" error otherwise.
    // Idempotent if the commitment is already a member. Guard: global limiter →
    // per-(IP, pollAddress) cap → validation → balance → tx.
    app.post("/api/relay/register-voter", registerLimiter, async (req, res) => {
        try {
            const validation = validateRegisterVoterRequest(req.body);
            if (!validation.ok) {
                res.status(400).json({ error: validation.error });
                return;
            }

            const balanceCheck = await checkRelayerBalance();
            if (!balanceCheck.sufficient) {
                res.status(503).json({
                    error: "Relayer has insufficient funds to pay gas",
                    balance: balanceCheck.balance,
                });
                return;
            }

            const { pollAddress, identityCommitment } = validation.data;
            console.log(`[RELAY] registerVoter → poll=${pollAddress}`);

            const result = await relayRegisterVoter(pollAddress, identityCommitment);
            console.log(`[RELAY] ✓ registered (already=${result.alreadyRegistered}) txHash=${result.txHash}`);

            res.json({
                success: true,
                txHash: result.txHash,
                alreadyRegistered: result.alreadyRegistered,
            });
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(`[RELAY] ✗ registerVoter error:`, message);
            // The relay step already maps contract reverts to clean copy; surface
            // the "joining is closed" / "already registered" wording to the user.
            res.status(400).json({ error: message });
        }
    });

    // ── POST /api/relay/start-voting ────────────────────────────────────────
    // Sponsored "Open voting" action (0B). The relayer (owner) flips the poll
    // Registration → Voting, paying gas. The needs-≥1-voter / wrong-state reverts
    // are surfaced as clear messages. Guard: global limiter → validation →
    // balance → tx.
    app.post("/api/relay/start-voting", async (req, res) => {
        try {
            const validation = validateStartVotingRequest(req.body);
            if (!validation.ok) {
                res.status(400).json({ error: validation.error });
                return;
            }

            const balanceCheck = await checkRelayerBalance();
            if (!balanceCheck.sufficient) {
                res.status(503).json({
                    error: "Relayer has insufficient funds to pay gas",
                    balance: balanceCheck.balance,
                });
                return;
            }

            const { pollAddress } = validation.data;
            console.log(`[RELAY] startVoting → poll=${pollAddress}`);

            const result = await relayStartVoting(pollAddress);
            console.log(`[RELAY] ✓ txHash=${result.txHash}`);

            res.json({ success: true, txHash: result.txHash });
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(`[RELAY] ✗ startVoting error:`, message);
            res.status(400).json({ error: message });
        }
    });

    // ── GET /api/relay/status ───────────────────────────────────────────────
    app.get("/api/relay/status", async (_req, res) => {
        try {
            const info = await getRelayerInfo();
            res.json({
                relayer: info.address,
                balance: info.balance,
                rateLimitPerMinute: config.rateLimitMax,
            });
        } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            console.error(`[RELAY] ✗ status error:`, message);
            res.status(500).json({ error: "Internal relayer error" });
        }
    });

    // ── Live Meeting Vote: ticket queue (S1.2) ──────────────────────────────
    app.use("/api/relay/tickets", createTicketRouter());

    return app;
}
