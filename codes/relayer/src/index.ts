import { config } from "./config";
import { getRelayerInfo } from "./wallet";
import { createApp } from "./app";

const app = createApp();

app.listen(config.port, "0.0.0.0", () => {
    console.log(`\n================================================`);
    console.log(`  Relayer Service running on port ${config.port}`);
    console.log(`  RPC: ${config.rpcUrl}`);
    console.log(`================================================\n`);

    getRelayerInfo()
        .then((info) => {
            console.log(`  Relayer address: ${info.address}`);
            console.log(`  Balance: ${info.balance} ETH`);
            console.log(`  Rate limit: ${config.rateLimitMax} req/min\n`);
        })
        .catch((err: unknown) => {
            const message = err instanceof Error ? err.message : String(err);
            console.error("Startup failed:", message);
            process.exit(1);
        });
});
