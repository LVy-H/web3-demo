import fs from "fs";
import path from "path";

/**
 * Reads compiled Hardhat artifacts and extracts ABI arrays
 * into the frontend src/abi/ directory.
 *
 * Usage:  npx ts-node scripts/copyAbis.ts
 */

const ARTIFACTS_ROOT = path.resolve(__dirname, "../artifacts/contracts");
const FRONTEND_ABI_DIR = path.resolve(__dirname, "../../frontend/src/abi");

// Map: output file name -> artifact path (relative to ARTIFACTS_ROOT)
const CONTRACTS: Record<string, string> = {
    "IZkPoll.json": "interfaces/IZkPoll.sol/IZkPoll.json",
    "PollRegistry.json": "PollRegistry.sol/PollRegistry.json",
    "ZkAnonVoting.json": "ZkAnonVoting.sol/ZkAnonVoting.json",
};

function main() {
    // Ensure output directory exists
    if (!fs.existsSync(FRONTEND_ABI_DIR)) {
        fs.mkdirSync(FRONTEND_ABI_DIR, { recursive: true });
        console.log("Created", FRONTEND_ABI_DIR);
    }

    for (const [outName, artifactRelPath] of Object.entries(CONTRACTS)) {
        const artifactPath = path.join(ARTIFACTS_ROOT, artifactRelPath);

        if (!fs.existsSync(artifactPath)) {
            console.error(`ERROR: Artifact not found: ${artifactPath}`);
            console.error("       Run 'npx hardhat compile' first.");
            process.exit(1);
        }

        const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf-8"));
        const abiOnly = { abi: artifact.abi };

        const outPath = path.join(FRONTEND_ABI_DIR, outName);
        fs.writeFileSync(outPath, JSON.stringify(abiOnly, null, 2) + "\n");
        console.log(`Wrote ${outName} (${artifact.abi.length} entries)`);
    }

    console.log("\nDone. ABIs written to", FRONTEND_ABI_DIR);
}

main();
