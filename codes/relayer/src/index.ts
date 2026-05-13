import express from "express";
import cors from "cors";
import rateLimit from "express-rate-limit";
import { config } from "./config";
import { getRelayerInfo } from "./wallet";
import { relayCastVote, relayClaimAirdrop, checkRelayerBalance } from "./relay";
import { validateVoteRequest, validateClaimRequest } from "./validation";

const app = express();

// Trust first proxy hop so express-rate-limit sees the real client IP
// when running behind cloudflared / nginx / docker network.
app.set('trust proxy', 1);

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

// ── Start ───────────────────────────────────────────────────────────────
app.listen(config.port, "0.0.0.0", () => {
    console.log(`\n================================================`);
    console.log(`  Relayer Service running on port ${config.port}`);
    console.log(`  RPC: ${config.rpcUrl}`);
    console.log(`================================================\n`);

    getRelayerInfo().then((info) => {
        console.log(`  Relayer address: ${info.address}`);
        console.log(`  Balance: ${info.balance} ETH`);
        console.log(`  Rate limit: ${config.rateLimitMax} req/min\n`);
    });
});
