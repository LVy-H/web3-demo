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
} = {
    rpcUrl: process.env.RPC_URL || "http://hardhat:8545",
    privateKey,
    port: Number(process.env.PORT) || 3001,
    maxGasLimit: 5_000_000n,
    rateLimitWindowMs: 60_000,
    rateLimitMax: 20,
};
