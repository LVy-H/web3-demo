import dotenv from "dotenv";
dotenv.config();

const privateKey = process.env.RELAYER_PRIVATE_KEY;
if (!privateKey) {
    throw new Error(
        "RELAYER_PRIVATE_KEY environment variable is required. " +
        "For local dev with Hardhat, copy .env.example to .env and set the Hardhat account #0 key."
    );
}

export const config: {
    rpcUrl: string;
    privateKey: string;
    port: number;
    maxGasLimit: bigint;
    rateLimitWindowMs: number;
    rateLimitMax: number;
    // Address of the deployed PollRegistry the relayer sponsors create-poll
    // through. OPTIONAL at import (unlike privateKey) so the chainless
    // validation/guard tests can import config without a deployed stack. When
    // unset, /info reports it as null and create-poll fails fast with a clear
    // "sponsored creation isn't configured" error instead of sending a tx.
    registryAddress: string | undefined;
    // Per-IP daily cap on sponsored create-poll (Decision 3 — create is costlier
    // than vote, so it gets a tighter cap on top of the global 20/min window).
    createDailyMax: number;
    // Per-(IP, pollAddress) cap on sponsored register-voter (Decision 3 — stops
    // one IP flooding a single poll's group with junk commitments).
    registerPerPollMax: number;
} = {
    rpcUrl: process.env.RPC_URL || "http://hardhat:8545",
    privateKey,
    port: Number(process.env.PORT) || 3001,
    maxGasLimit: 5_000_000n,
    rateLimitWindowMs: 60_000,
    rateLimitMax: 20,
    registryAddress: process.env.REGISTRY_ADDRESS,
    createDailyMax: Number(process.env.CREATE_DAILY_MAX) || 5,
    registerPerPollMax: Number(process.env.REGISTER_PER_POLL_MAX) || 50,
};

/** Live reads of the sponsored-lifecycle settings (NOT the frozen `config`
 *  snapshot above). Reading these at request / createApp() time lets a test do
 *  `set env → createApp()` with no module re-import dance, and lets a deployment
 *  set REGISTRY_ADDRESS / the caps after the module first imports. */
export function getRegistryAddress(): string | undefined {
    const a = process.env.REGISTRY_ADDRESS;
    return a && a.length > 0 ? a : undefined;
}

export function getCreateDailyMax(): number {
    return Number(process.env.CREATE_DAILY_MAX) || 5;
}

export function getRegisterPerPollMax(): number {
    return Number(process.env.REGISTER_PER_POLL_MAX) || 50;
}

/** Read the optional create shared-secret at REQUEST time, not import time.
 *  Decision 3: when CREATE_SECRET is set the create-poll endpoint requires a
 *  matching X-Create-Secret header; when unset (local/dev) create is open.
 *  Reading it live (rather than baking it into the frozen `config` above) lets
 *  a test set/unset process.env.CREATE_SECRET per case without re-importing the
 *  module. NOTE: this is an operator gate on WHO can mint sponsored polls — it
 *  is NOT Sybil-resistant and does not gate voting/registration. */
export function getCreateSecret(): string | undefined {
    const s = process.env.CREATE_SECRET;
    return s && s.length > 0 ? s : undefined;
}
