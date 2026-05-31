// Vitest setupFile — runs before any test module is imported. config.ts throws
// at import if RELAYER_PRIVATE_KEY is unset, so set a throwaway key here. This
// is the well-known public Hardhat account #0 key (no real value); it is only
// needed so the app/config modules import — the ticket tests never send a tx.
process.env.RELAYER_PRIVATE_KEY =
    process.env.RELAYER_PRIVATE_KEY ||
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
process.env.RPC_URL = process.env.RPC_URL || "http://127.0.0.1:8545";
