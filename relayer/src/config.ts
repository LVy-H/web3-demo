import dotenv from "dotenv";
dotenv.config();

export const config = {
    rpcUrl: process.env.RPC_URL || "http://127.0.0.1:8545",
    privateKey:
        process.env.RELAYER_PRIVATE_KEY ||
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    port: Number(process.env.PORT) || 3001,
    maxGasLimit: 5_000_000n,
    rateLimitWindowMs: 60_000,
    rateLimitMax: 20,
};
