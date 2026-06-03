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
// transient PRE-broadcast errors, a per-tx timeout, and one structured log line.
//
// ── THE LOAD-BEARING INVARIANT: pre-broadcast vs post-broadcast ─────────────
//
// `doSend` is split into two phases that are NEVER conflated, because conflating
// them double-executes transactions:
//
//   PRE-broadcast  (nonce sync → populate → estimateGas → signer.sendTransaction)
//     The tx has NOT hit the mempool. A failure here means it was NEVER
//     broadcast → it is SAFE to retry. This is the ONLY place we resend: bounded
//     by MAX_RETRIES, with a nonce resync + exponential backoff between attempts.
//
//   POST-broadcast (the tx is in the mempool with a known hash + nonce)
//     The tx is LIVE. It may mine, revert, or simply be slow. We MUST NOT resend
//     it at a new nonce — doing so resyncs `getTransactionCount(addr,"pending")`,
//     which COUNTS the still-live tx, hands back N+1, and broadcasts a SECOND
//     transaction while the first is still in flight (double-execution: e.g. a
//     timed-out-but-live `createPoll` would deploy a SECOND poll). So once
//     `sendTransaction` resolves we advance the nonce, leave the retry loop for
//     good, and only WAIT (a bounded receipt-poll). Every post-broadcast outcome
//     — mined-ok, reverted, or timed-out — resets the nonce (so the NEXT send
//     re-reads `pending`: N+1 for a live/mined tx, or N for a genuinely dropped
//     tx, healing the gap) and resends NOTHING.
//
// A broadcast tx is never re-sent at a new nonce. That is the whole correctness
// property — keep it obvious to the next reader/debugger.

/** Build a tx request from the signer (a thunk that returns a populated tx).
 *  Using `contract.method.populateTransaction(...)` keeps gas estimation, nonce
 *  assignment, and retry in ONE place — callers never touch the nonce. */
export type PopulateTx = () => Promise<ethers.TransactionRequest>;

export interface SendResult {
    receipt: ethers.TransactionReceipt;
    hash: string;
    nonce: number;
}

/** Tunables for a TxManager. The singleton uses env/defaults; tests inject tiny
 *  values so the receipt-poll and backoff don't make a unit run hang. */
export interface TxManagerOptions {
    /** Total budget for the post-broadcast receipt-poll before TX_TIMEOUT. */
    timeoutMs?: number;
    /** Interval between receipt-poll attempts. */
    pollIntervalMs?: number;
    /** Base for the pre-broadcast retry backoff (delay = base * 2^attempt). */
    retryBaseMs?: number;
}

/** Errors that are worth a bounded retry (after a nonce resync). A revert is
 *  NOT here — a reverted tx is a deterministic outcome, retrying it just burns
 *  gas. We match ethers v6 error codes and the common nonce/replacement/network
 *  signatures. Only consulted on the PRE-broadcast path. */
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
// How often the post-broadcast wait polls for the receipt.
const POLL_INTERVAL_MS = Number(process.env.TX_POLL_INTERVAL_MS) || 1_500;
// Base delay for the pre-broadcast retry backoff (base * 2^attempt, capped).
const RETRY_BASE_MS = 200;
// Cap on the pre-broadcast backoff so a slow chain doesn't stall the queue.
const RETRY_BACKOFF_CAP_MS = 2_000;
// Sane gas floor so estimateGas*1.2 can't underprovision a cheap-looking call
// whose on-chain path (Semaphore verify, tree insert) costs more than the
// estimate implies. Capped above by config.maxGasLimit.
const GAS_FLOOR = 200_000n;

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

export class TxManager {
    private tail: Promise<unknown> = Promise.resolve();
    // null ⇒ "must (re)sync from chain before the next send". Set after the
    // first successful read and advanced locally on each success.
    private nextNonce: number | null = null;

    private readonly timeoutMs: number;
    private readonly pollIntervalMs: number;
    private readonly retryBaseMs: number;

    constructor(opts: TxManagerOptions = {}) {
        this.timeoutMs = opts.timeoutMs ?? TX_TIMEOUT_MS;
        this.pollIntervalMs = opts.pollIntervalMs ?? POLL_INTERVAL_MS;
        this.retryBaseMs = opts.retryBaseMs ?? RETRY_BASE_MS;
    }

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
     *  RPC-rejected tx did not (pending count re-yields the same value), and a
     *  still-live broadcast tx is also counted (pending re-yields N+1, never N —
     *  which is exactly why we must not resend a broadcast tx). */
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

    /** Force a chain resync on the next send (called after any failure, and after
     *  every post-broadcast outcome, so a gap left by a reverted/rejected/dropped
     *  tx is healed instead of stalling the queue). */
    private resetNonce(): void {
        this.nextNonce = null;
    }

    /**
     * Send ONE transaction through the global serial queue with explicit nonce
     * management, a gas buffer, bounded PRE-broadcast transient-retry, and a
     * per-tx timeout. `populate` returns the unsigned tx request (typically
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
        // ── PHASE 1: PRE-broadcast — safe to retry (the tx is NOT in the mempool
        //    until signer.sendTransaction resolves). Bounded retry + backoff. ──
        let sent: ethers.TransactionResponse | undefined;
        let nonce = 0;
        let lastErr: unknown;

        for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
            const start = Date.now();
            nonce = await this.syncNonce();
            let gasLimit = GAS_FLOOR;
            try {
                const signer = getRelayerWallet();
                // Rebuild the populated request each attempt (a resynced nonce or
                // a fresh fee may matter on retry).
                const req = await populate();
                req.nonce = nonce;

                // Gas buffer: estimateGas * 1.2 with a floor, capped by the
                // configured ceiling. estimateGas re-runs the call so a now-
                // reverting precondition surfaces here (PRE-broadcast) as a real
                // (non-transient) error — the route maps the revert name rather
                // than blindly sending with the floor and wasting gas. A transient
                // estimate error (network) falls through to the classifier in the
                // catch below.
                const est = await signer.estimateGas(req);
                const buffered = (est * 12n) / 10n;
                gasLimit = buffered > GAS_FLOOR ? buffered : GAS_FLOOR;
                if (gasLimit > config.maxGasLimit) gasLimit = config.maxGasLimit;
                req.gasLimit = gasLimit;

                // The point of no return: once this resolves the tx is LIVE in the
                // mempool. We MUST NOT re-enter this loop for it.
                sent = await signer.sendTransaction(req);

                // Broadcast succeeded → advance the local nonce immediately and
                // leave the retry loop for good.
                this.nextNonce = nonce + 1;
                console.log(`[tx] ${label} nonce=${nonce} hash=${sent.hash} broadcast`);
                break;
            } catch (err) {
                lastErr = err;
                const transient = isTransient(err);
                const willRetry = transient && attempt < MAX_RETRIES;
                console.log(
                    `[tx] fn=${label} nonce=${nonce} gasLimit=${gasLimit} hash=- status=${willRetry ? "retry" : "fail"} attempt=${attempt} latency=${Date.now() - start}ms err=${err instanceof Error ? err.message.split("\n")[0] : String(err)}`
                );
                // Pre-broadcast failure: our local nonce may be wrong (e.g. a
                // nonce-too-low classification) → resync from chain before the
                // retry OR the next queued tx. A non-transient error (a revert
                // surfaced by estimateGas) is rethrown UNWRAPPED so revert-name
                // matching upstream keeps working.
                this.resetNonce();
                if (!willRetry) {
                    throw err;
                }
                // Exponential backoff so a transient RPC blip isn't hammered with
                // zero delay; capped, and never slept after the final attempt
                // (guarded by willRetry above).
                const backoff = Math.min(
                    this.retryBaseMs * 2 ** attempt,
                    RETRY_BACKOFF_CAP_MS
                );
                if (backoff > 0) await sleep(backoff);
                // loop → syncNonce re-fetches the chain.
            }
        }

        if (!sent) {
            // Unreachable in practice (the loop throws on its last failing
            // attempt), but satisfies the type checker.
            throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
        }

        // ── PHASE 2: POST-broadcast — the tx is LIVE. NEVER resend it. Just wait
        //    for the receipt (bounded). Every outcome resets the nonce so the
        //    next send re-reads `pending`. ──
        return this.waitForReceipt(label, sent, nonce);
    }

    /** Bounded receipt-poll for an already-broadcast tx. This NEVER resends.
     *  - found, status 1 → success (a slow-but-mining tx resolves to SUCCESS,
     *    fixing the "slow tx reported as failure" bug).
     *  - found, status 0 → throw a revert error (the chain consumed the nonce).
     *  - not found by the deadline → throw a clean { code: "TX_TIMEOUT" } error.
     *  In ALL cases the nonce is reset (the next send re-reads `pending`, which
     *  correctly yields N+1 for a live/mined tx or N for a genuinely dropped one,
     *  healing any gap). A broadcast tx is never re-sent at a new nonce. */
    private async waitForReceipt(
        label: string,
        sent: ethers.TransactionResponse,
        nonce: number
    ): Promise<SendResult> {
        const provider = getProvider();
        const start = Date.now();
        try {
            // Check-then-sleep (never sleep-then-check): under automine the
            // receipt is ready as soon as sendTransaction resolves, so the live
            // e2e + concurrency tests stay fast; and the "mines on the 2nd/3rd
            // poll" semantics (null, null, receipt) only make sense check-first.
            for (;;) {
                const receipt = await provider.getTransactionReceipt(sent.hash);
                if (receipt) {
                    const status = receipt.status === 1 ? "ok" : "revert";
                    console.log(
                        `[tx] ${label} nonce=${nonce} hash=${sent.hash} status=${status} latency=${Date.now() - start}ms`
                    );
                    if (receipt.status === 1) {
                        return { receipt, hash: receipt.hash, nonce };
                    }
                    // status-0: an on-chain revert that DID consume the nonce.
                    // (A polled receipt carries no decoded revert reason — that's
                    // fine: lifecycle/vote reverts surface PRE-broadcast in
                    // estimateGas where the name is preserved for mapping.)
                    throw Object.assign(
                        new Error(`Transaction reverted on-chain (${label})`),
                        { code: "CALL_EXCEPTION", receipt }
                    );
                }
                if (Date.now() - start >= this.timeoutMs) {
                    // Not mined within the budget. The tx is still LIVE — do NOT
                    // resend it. Surface a clean timeout error; the caller's route
                    // maps it to a 5xx. The nonce reset (finally) makes the next
                    // send re-read `pending` = N+1 (this tx is counted), so we
                    // never collide with it.
                    console.log(
                        `[tx] ${label} nonce=${nonce} hash=${sent.hash} status=timeout latency=${Date.now() - start}ms`
                    );
                    throw Object.assign(
                        new Error(
                            `Transaction ${sent.hash} not mined within ${this.timeoutMs}ms`
                        ),
                        { code: "TX_TIMEOUT", hash: sent.hash, nonce }
                    );
                }
                await sleep(this.pollIntervalMs);
            }
        } finally {
            // Post-broadcast ALWAYS resyncs the next nonce from the chain: N+1 for
            // a live/mined tx (the success path advanced it to the same value, so
            // this is harmless there), or N for a genuinely dropped tx (filling
            // the gap). A broadcast tx is never re-sent at a new nonce.
            this.resetNonce();
        }
    }
}

let manager: TxManager | undefined;

/** The ONE global tx manager, shared by every endpoint and every concurrent
 *  request (a module-level singleton, like getRelayerWallet). Lazily created so
 *  tests that never send a tx don't pay for it. Uses env/default tunables. */
export function getTxManager(): TxManager {
    if (!manager) manager = new TxManager();
    return manager;
}
