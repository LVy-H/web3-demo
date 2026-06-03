import { describe, it, expect, vi, beforeEach } from "vitest";

// ── Failure-path unit tests for the serialized TxManager ────────────────────
//
// These mock the relayer SIGNER + PROVIDER (no chain needed → they run in CI)
// and assert the ONE load-bearing correctness property of the pre/post-broadcast
// restructure: a transaction that has been BROADCAST is NEVER re-sent. Every
// test pins `signer.sendTransaction` call count, because that count IS the bug.
//
// THE regression test is "post-broadcast TIMEOUT → exactly ONE sendTransaction
// call": before the fix a post-broadcast TIMEOUT was classified transient and
// retried, and the retry resynced the nonce from `pending` (which counts the
// still-live tx) → N+1 → a SECOND broadcast of the same logical tx. That is
// double-execution (a timed-out-but-live createPoll would deploy a 2nd poll).

// The mutable mock signer/provider — declared via vi.hoisted so the (hoisted)
// vi.mock factory can close over them. Each test resets their behaviour.
const mocks = vi.hoisted(() => {
    return {
        signer: {
            address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            estimateGas: vi.fn(),
            sendTransaction: vi.fn(),
        },
        provider: {
            getTransactionCount: vi.fn(),
            getTransactionReceipt: vi.fn(),
        },
    };
});

vi.mock("../src/wallet", () => ({
    getRelayerWallet: () => mocks.signer,
    getProvider: () => mocks.provider,
}));

// Imported AFTER the mock is registered (vi.mock is hoisted above all imports).
import { TxManager } from "../src/tx_manager";

const HASH = "0xabc0000000000000000000000000000000000000000000000000000000000001";

/** A fresh manager with tiny tunables so the receipt-poll + backoff never make
 *  the unit run hang (constructor-config, NOT env — so nothing leaks into the
 *  live chain-gated tests that share this worker's process.env). */
function makeManager() {
    return new TxManager({ timeoutMs: 120, pollIntervalMs: 10, retryBaseMs: 0 });
}

/** A minimal mined receipt with the given status. Its hash matches the broadcast
 *  tx hash (as a real receipt does — waitForReceipt returns receipt.hash). */
function receipt(status: 0 | 1, hash: string = HASH) {
    return { status, hash, logs: [] };
}

/** A populate thunk — the manager sets nonce/gasLimit on the returned object. */
const populate = async () => ({ to: "0x0000000000000000000000000000000000000001", data: "0x" });

beforeEach(() => {
    mocks.signer.estimateGas.mockReset();
    mocks.signer.sendTransaction.mockReset();
    mocks.provider.getTransactionCount.mockReset();
    mocks.provider.getTransactionReceipt.mockReset();

    // Sensible defaults: nonce starts at 5, gas estimate is cheap. Pending count
    // returns the locally-untracked truth each call — tests override as needed.
    mocks.provider.getTransactionCount.mockResolvedValue(5);
    mocks.signer.estimateGas.mockResolvedValue(100_000n);
});

describe("TxManager — post-broadcast is never re-sent (the core invariant)", () => {
    it("(REGRESSION) post-broadcast TIMEOUT → exactly ONE sendTransaction call, surfaces TX_TIMEOUT (no double-send)", async () => {
        const mgr = makeManager();
        // Broadcast succeeds once...
        mocks.signer.sendTransaction.mockResolvedValue({ hash: HASH });
        // ...but the receipt NEVER appears → the poll runs to the deadline.
        mocks.provider.getTransactionReceipt.mockResolvedValue(null);

        let caught: unknown;
        try {
            await mgr.send("createPoll", populate);
        } catch (err) {
            caught = err;
        }

        // THE assertion: the broadcast tx was NOT re-sent. Exactly one send.
        expect(mocks.signer.sendTransaction).toHaveBeenCalledTimes(1);
        // And the outcome is a clean TX_TIMEOUT — NOT a second broadcast / hash.
        expect((caught as { code?: string })?.code).toBe("TX_TIMEOUT");
        expect((caught as { hash?: string })?.hash).toBe(HASH);
    });

    it("slow-but-mines: receipt appears on the 3rd poll → SUCCESS with exactly ONE send", async () => {
        const mgr = makeManager();
        mocks.signer.sendTransaction.mockResolvedValue({ hash: HASH });
        // null, null, then a status-1 receipt (mined just after a couple polls).
        mocks.provider.getTransactionReceipt
            .mockResolvedValueOnce(null)
            .mockResolvedValueOnce(null)
            .mockResolvedValueOnce(receipt(1));

        const res = await mgr.send("createPoll", populate);

        expect(res.hash).toBe(HASH);
        expect(res.receipt.status).toBe(1);
        // Slow-but-successful resolves to SUCCESS — not reported as a failure.
        expect(mocks.signer.sendTransaction).toHaveBeenCalledTimes(1);
        expect(mocks.provider.getTransactionReceipt).toHaveBeenCalledTimes(3);
    });

    it("on-chain revert (status 0): ONE send, surfaces the revert, NO resend", async () => {
        const mgr = makeManager();
        mocks.signer.sendTransaction.mockResolvedValue({ hash: HASH });
        mocks.provider.getTransactionReceipt.mockResolvedValue(receipt(0));

        let caught: unknown;
        try {
            await mgr.send("registerVoter", populate);
        } catch (err) {
            caught = err;
        }

        expect(caught).toBeInstanceOf(Error);
        expect((caught as { code?: string })?.code).toBe("CALL_EXCEPTION");
        // A reverted-but-broadcast tx is NOT re-sent.
        expect(mocks.signer.sendTransaction).toHaveBeenCalledTimes(1);
    });
});

describe("TxManager — pre-broadcast is the ONLY place a resend is correct", () => {
    it("pre-broadcast transient (sendTransaction network error) → retries with resync+backoff, then succeeds (>1 send)", async () => {
        const mgr = makeManager();
        // First sendTransaction throws a transient network error (pre-broadcast,
        // so NOTHING hit the mempool); the second succeeds.
        mocks.signer.sendTransaction
            .mockRejectedValueOnce(Object.assign(new Error("network error"), { code: "NETWORK_ERROR" }))
            .mockResolvedValueOnce({ hash: HASH });
        mocks.provider.getTransactionReceipt.mockResolvedValue(receipt(1));

        const res = await mgr.send("createPoll", populate);

        expect(res.hash).toBe(HASH);
        // The ONLY place resend is correct: a pre-broadcast failure → >1 attempt.
        expect(mocks.signer.sendTransaction).toHaveBeenCalledTimes(2);
        // The retry resynced the nonce from the chain (pending re-read).
        expect(mocks.provider.getTransactionCount.mock.calls.length).toBeGreaterThanOrEqual(2);
    });

    it("pre-broadcast transient on estimateGas → retries (sendTransaction still reached once)", async () => {
        const mgr = makeManager();
        mocks.signer.estimateGas
            .mockRejectedValueOnce(Object.assign(new Error("could not coalesce error"), { code: "SERVER_ERROR" }))
            .mockResolvedValue(100_000n);
        mocks.signer.sendTransaction.mockResolvedValue({ hash: HASH });
        mocks.provider.getTransactionReceipt.mockResolvedValue(receipt(1));

        const res = await mgr.send("createPoll", populate);

        expect(res.hash).toBe(HASH);
        // estimateGas failed once (no broadcast), retried, then ONE broadcast.
        expect(mocks.signer.sendTransaction).toHaveBeenCalledTimes(1);
    });

    it("retry exhaustion (pre-broadcast): throws after MAX_RETRIES; queue stays usable for the next send", async () => {
        const mgr = makeManager();
        // sendTransaction ALWAYS throws a transient error → exhausts retries.
        mocks.signer.sendTransaction.mockRejectedValue(
            Object.assign(new Error("socket hang up"), { code: "NETWORK_ERROR" })
        );

        let caught: unknown;
        try {
            await mgr.send("createPoll", populate);
        } catch (err) {
            caught = err;
        }
        expect(caught).toBeInstanceOf(Error);
        // MAX_RETRIES = 3 → attempts 0..3 inclusive = 4 broadcast attempts.
        expect(mocks.signer.sendTransaction).toHaveBeenCalledTimes(4);

        // The queue is NOT poisoned: a subsequent send works.
        mocks.signer.sendTransaction.mockReset();
        mocks.signer.sendTransaction.mockResolvedValue({ hash: HASH });
        mocks.provider.getTransactionReceipt.mockResolvedValue(receipt(1));
        const ok = await mgr.send("createPoll", populate);
        expect(ok.hash).toBe(HASH);
        expect(mocks.signer.sendTransaction).toHaveBeenCalledTimes(1);
    });

    it("on-chain revert surfaced PRE-broadcast by estimateGas: ONE-or-zero send, error rethrown UNWRAPPED (no retry)", async () => {
        const mgr = makeManager();
        // estimateGas reverts with a recognizable lifecycle name — NON-transient,
        // so it is rethrown unwrapped and NOT retried, and never broadcast.
        mocks.signer.estimateGas.mockRejectedValue(
            Object.assign(new Error("execution reverted: AlreadyRegistered()"), { code: "CALL_EXCEPTION" })
        );

        let caught: unknown;
        try {
            await mgr.send("registerVoter", populate);
        } catch (err) {
            caught = err;
        }
        expect((caught as Error)?.message).toMatch(/AlreadyRegistered/);
        // A revert at estimateGas is pre-broadcast → tx was NEVER sent.
        expect(mocks.signer.sendTransaction).toHaveBeenCalledTimes(0);
    });
});

describe("TxManager — the nonce counter is never poisoned across failure paths", () => {
    it("after a post-broadcast TIMEOUT, the NEXT send re-reads pending (N+1) and succeeds at that nonce", async () => {
        const mgr = makeManager();

        // 1st send: broadcast OK, receipt never appears → TX_TIMEOUT. The live tx
        // consumed nonce 5; the chain's pending count now reflects 6.
        mocks.signer.sendTransaction.mockResolvedValueOnce({ hash: HASH });
        mocks.provider.getTransactionReceipt.mockResolvedValueOnce(null);
        mocks.provider.getTransactionCount.mockResolvedValueOnce(5); // first sync

        await expect(mgr.send("createPoll", populate)).rejects.toMatchObject({ code: "TX_TIMEOUT" });

        // 2nd send: a clean run. resetNonce forced a chain re-read → pending is 6
        // (the live tx is counted), so the next send must use nonce 6, NOT 5.
        const second = "0xdef0000000000000000000000000000000000000000000000000000000000002";
        mocks.provider.getTransactionCount.mockResolvedValueOnce(6); // re-sync after timeout
        let capturedNonce: number | undefined;
        mocks.signer.sendTransaction.mockImplementationOnce(async (req: { nonce?: number }) => {
            capturedNonce = req.nonce;
            return { hash: second };
        });
        // The 2nd tx's receipt carries the 2nd tx's hash (as a real receipt does).
        mocks.provider.getTransactionReceipt.mockResolvedValue(receipt(1, second));

        const res = await mgr.send("registerVoter", populate);
        expect(res.hash).toBe(second);
        // The next send did NOT collide with the still-live first tx's nonce.
        expect(capturedNonce).toBe(6);
    });

    it("a successful send advances the nonce; the immediate next send uses N+1 without a chain re-read mid-flight", async () => {
        const mgr = makeManager();
        // Two back-to-back successful sends. First at nonce 5, second at 6.
        const nonces: Array<number | undefined> = [];
        mocks.signer.sendTransaction.mockImplementation(async (req: { nonce?: number }) => {
            nonces.push(req.nonce);
            return { hash: HASH };
        });
        mocks.provider.getTransactionReceipt.mockResolvedValue(receipt(1));
        // Pending starts at 5; after the first send the post-broadcast resetNonce
        // forces a re-read, which now returns 6 (first tx mined/consumed it).
        mocks.provider.getTransactionCount.mockResolvedValueOnce(5).mockResolvedValueOnce(6);

        await mgr.send("a", populate);
        await mgr.send("b", populate);

        expect(nonces).toEqual([5, 6]);
    });
});
