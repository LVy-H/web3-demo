import { ethers } from "ethers";
import { getRelayerWallet, getProvider } from "./wallet";
import { config } from "./config";

// ── Serialized transaction manager (nonce-race fix) ─────────────────────────
//
// THE PROBLEM this exists to kill: the relayer is ONE signer shared by every
// endpoint and every concurrent HTTP request. The old code did
// `contract.method(...); await tx.wait()` per call, relying on the provider's
// per-tx `getTransactionCount("pending")` to pick the nonce. Back-to-back or
// concurrent sends raced: the provider handed out a STALE pending nonce to the
// 2nd send before the 1st was reflected, producing "Nonce too low. Expected 36
// got 35" — and `await tx.wait()` does NOT prevent it.
//
// THE FIX: a SINGLE GLOBAL serialized send-queue (a promise-chain mutex) around
// the one relayer signer, shared by ALL endpoints and ALL concurrent requests.
// Exactly one tx is in flight at a time. The nonce is managed EXPLICITLY — read
// once from the chain, incremented locally on success, and RESYNCED from the
// chain on any failure so a reverted/rejected tx never leaves a gap that stalls
// the whole queue. Each send also gets a gas-limit buffer, bounded retry on
// transient errors (with a nonce resync before each retry), a per-tx timeout,
// and one structured log line for debuggability.

/** Build a tx request from the signer (a thunk that returns a populated tx).
 *  Using `contract.method.populateTransaction(...)` keeps gas estimation, nonce
 *  assignment, and retry in ONE place — callers never touch the nonce. */
export type PopulateTx = () => Promise<ethers.TransactionRequest>;

export interface SendResult {
    receipt: ethers.TransactionReceipt;
    hash: string;
    nonce: number;
}

/** Errors that are worth a bounded retry (after a nonce resync). A revert is
 *  NOT here — a reverted tx is a deterministic outcome, retrying it just burns
 *  gas. We match ethers v6 error codes and the common nonce/replacement/network
 *  signatures. */
function isTransient(err: unknown): boolean {
    const code = (err as { code?: string })?.code;
    if (
        code === "NONCE_EXPIRED" ||
        code === "REPLACEMENT_UNDERPRICED" ||
        code === "NETWORK_ERROR" ||
        code === "TIMEOUT" ||
        code === "SERVER_ERROR"
    ) {
        return true;
    }
    const msg = (err instanceof Error ? err.message : String(err)).toLowerCase();
    return (
        msg.includes("nonce too low") ||
        msg.includes("nonce has already been used") ||
        msg.includes("replacement transaction underpriced") ||
        msg.includes("replacement fee too low") ||
        msg.includes("could not coalesce error") ||
        msg.includes("network") ||
        msg.includes("etimedout") ||
        msg.includes("econnreset") ||
        msg.includes("socket hang up")
    );
}

const MAX_RETRIES = 3;
// Per-tx timeout so a stuck send/mine never wedges the whole queue forever. The
// queue is serial, so one hung tx would otherwise block every other request.
const TX_TIMEOUT_MS = Number(process.env.TX_TIMEOUT_MS) || 60_000;
// Sane gas floor so estimateGas*1.2 can't underprovision a cheap-looking call
// whose on-chain path (Semaphore verify, tree insert) costs more than the
// estimate implies. Capped above by config.maxGasLimit.
const GAS_FLOOR = 200_000n;

class TxManager {
    private tail: Promise<unknown> = Promise.resolve();
    // null ⇒ "must (re)sync from chain before the next send". Set after the
    // first successful read and advanced locally on each success.
    private nextNonce: number | null = null;

    /** Serialize `fn` behind every other in-flight send. The `.catch` on the
     *  chained tail is load-bearing: one rejected send must NOT poison the queue
     *  (an unhandled rejection on `tail` would make every later `.then` reject). */
    private enqueue<T>(fn: () => Promise<T>): Promise<T> {
        const run = this.tail.then(fn, fn);
        // Keep the internal chain alive regardless of this run's outcome.
        this.tail = run.then(
            () => undefined,
            () => undefined
        );
        return run;
    }

    /** Read the next nonce to use. On a fresh manager (or after a failure reset
     *  it to null) this fetches the chain's pending count; otherwise it returns
     *  the locally-tracked value. Chain is the source of truth: a mined-and-
     *  reverted tx already consumed its nonce (pending count reflects it), an
     *  RPC-rejected tx did not (pending count re-yields the same value). */
    private async syncNonce(): Promise<number> {
        if (this.nextNonce === null) {
            const signer = getRelayerWallet();
            this.nextNonce = await getProvider().getTransactionCount(
                signer.address,
                "pending"
            );
        }
        return this.nextNonce;
    }

    /** Force a chain resync on the next send (called after any failure so a gap
     *  left by a reverted/rejected tx is healed instead of stalling the queue). */
    private resetNonce(): void {
        this.nextNonce = null;
    }

    /**
     * Send ONE transaction through the global serial queue with explicit nonce
     * management, a gas buffer, bounded transient-retry, and a per-tx timeout.
     * `populate` returns the unsigned tx request (typically
     * `contract.method.populateTransaction(args)`). The receipt is returned.
     *
     * IMPORTANT: on a REVERT (or any non-transient error) the ORIGINAL error
     * object is rethrown UNWRAPPED so callers' revert-name matching
     * (relay.ts `mapLifecycleRevert`) keeps working.
     */
    send(label: string, populate: PopulateTx): Promise<SendResult> {
        return this.enqueue(() => this.doSend(label, populate));
    }

    private async doSend(label: string, populate: PopulateTx): Promise<SendResult> {
        const signer = getRelayerWallet();
        const provider = getProvider();
        let lastErr: unknown;

        for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
            const start = Date.now();
            const nonce = await this.syncNonce();
            let gasLimit = GAS_FLOOR;
            try {
                // Rebuild the populated request each attempt (a resynced nonce or
                // a fresh fee may matter on retry).
                const req = await populate();
                req.nonce = nonce;

                // Gas buffer: estimateGas * 1.2 with a floor, capped by the
                // configured ceiling. estimateGas re-runs the call so a now-
                // reverting precondition surfaces here as a revert (not retried).
                try {
                    const est = await signer.estimateGas(req);
                    const buffered = (est * 12n) / 10n;
                    gasLimit = buffered > GAS_FLOOR ? buffered : GAS_FLOOR;
                    if (gasLimit > config.maxGasLimit) gasLimit = config.maxGasLimit;
                } catch (estErr) {
                    // estimateGas reverting is the contract telling us this tx
                    // WILL fail — surface it as a real (non-transient) error so
                    // the route maps the revert, rather than blindly sending with
                    // the floor and wasting gas. Transient estimate errors
                    // (network) still fall through to the retry classifier below.
                    if (!isTransient(estErr)) throw estErr;
                    throw estErr;
                }
                req.gasLimit = gasLimit;

                const sent = await signer.sendTransaction(req);

                // Per-tx timeout around mining so the serial queue can't wedge.
                const receipt = await this.waitWithTimeout(sent, provider);
                if (!receipt) {
                    throw Object.assign(new Error("Transaction mined but no receipt"), {
                        code: "SERVER_ERROR",
                    });
                }

                // Success: advance the local nonce and log the result.
                this.nextNonce = nonce + 1;
                const status = receipt.status === 1 ? "ok" : "revert";
                console.log(
                    `[tx] fn=${label} nonce=${nonce} gasLimit=${gasLimit} hash=${receipt.hash} status=${status} latency=${Date.now() - start}ms`
                );
                // A status-0 receipt is an on-chain revert that still consumed the
                // nonce; treat it as an error (callers expect a throw on failure),
                // but the nonce stays advanced (chain consumed it) — no resync.
                if (receipt.status !== 1) {
                    throw Object.assign(new Error(`Transaction reverted on-chain (${label})`), {
                        code: "CALL_EXCEPTION",
                        receipt,
                    });
                }
                return { receipt, hash: receipt.hash, nonce };
            } catch (err) {
                lastErr = err;
                const transient = isTransient(err);
                console.log(
                    `[tx] fn=${label} nonce=${nonce} gasLimit=${gasLimit} hash=- status=${transient && attempt < MAX_RETRIES ? "retry" : "fail"} attempt=${attempt} latency=${Date.now() - start}ms err=${err instanceof Error ? err.message.split("\n")[0] : String(err)}`
                );
                // Any failure means our local nonce may be wrong → resync from
                // chain before the next send (this run's retry OR the next queued
                // tx). For a non-transient error (revert) we still resync defensively
                // and rethrow the ORIGINAL error unwrapped so revert-name matching
                // upstream keeps working.
                this.resetNonce();
                if (!transient || attempt >= MAX_RETRIES) {
                    throw err;
                }
                // transient + retries left → loop (syncNonce re-fetches the chain).
            }
        }
        // Unreachable in practice (the loop throws), but satisfies the type.
        throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
    }

    /** Wait for the tx to mine, but reject if it takes longer than the per-tx
     *  timeout so the serial queue is never wedged by one stuck send. */
    private async waitWithTimeout(
        sent: ethers.TransactionResponse,
        _provider: ethers.JsonRpcProvider
    ): Promise<ethers.TransactionReceipt | null> {
        let timer: NodeJS.Timeout | undefined;
        const timeout = new Promise<never>((_, reject) => {
            timer = setTimeout(() => {
                reject(
                    Object.assign(
                        new Error(`Transaction wait timed out after ${TX_TIMEOUT_MS}ms`),
                        { code: "TIMEOUT" }
                    )
                );
            }, TX_TIMEOUT_MS);
        });
        try {
            return await Promise.race([sent.wait(), timeout]);
        } finally {
            if (timer) clearTimeout(timer);
        }
    }
}

let manager: TxManager | undefined;

/** The ONE global tx manager, shared by every endpoint and every concurrent
 *  request (a module-level singleton, like getRelayerWallet). Lazily created so
 *  tests that never send a tx don't pay for it. */
export function getTxManager(): TxManager {
    if (!manager) manager = new TxManager();
    return manager;
}
