import fs from "fs";
import path from "path";

/**
 * Reads compiled Hardhat artifacts and extracts ABI arrays
 * into every consumer's src/abi/ directory (the relayer; the Flutter app keeps
 * its own committed copies under codes/mobile/assets/abi/).
 *
 * Usage:  npx ts-node scripts/copyAbis.ts
 */

const ARTIFACTS_ROOT = path.resolve(__dirname, "../artifacts/contracts");

// Consumers that need contract ABIs. Skipped silently if the directory
// doesn't exist. (The Flutter app keeps its own committed copies under
// codes/mobile/assets/abi/; the React frontend is deprecated/removed.)
const ABI_TARGETS: { name: string; dir: string }[] = [
    { name: "relayer", dir: path.resolve(__dirname, "../../relayer/src/abi") },
];

// Map: output file name -> artifact path (relative to ARTIFACTS_ROOT)
const CONTRACTS: Record<string, string> = {
    "IZkPoll.json": "interfaces/IZkPoll.sol/IZkPoll.json",
    "PollRegistry.json": "PollRegistry.sol/PollRegistry.json",
    "ZkAirdrop.json": "ZkAirdrop.sol/ZkAirdrop.json",
    "ZkAnonVoting.json": "ZkAnonVoting.sol/ZkAnonVoting.json",
    "ZkBlindVoting.json": "ZkBlindVoting.sol/ZkBlindVoting.json",
};

function isConsumerPresent(targetDir: string): boolean {
    // Treat the parent (`src/`) as the signal that this consumer exists in
    // the working tree. The abi/ directory itself may be missing on a fresh
    // checkout — we'll create it.
    const parent = path.dirname(targetDir);
    return fs.existsSync(parent);
}

function main() {
    const presentTargets = ABI_TARGETS.filter((t) => {
        if (isConsumerPresent(t.dir)) {
            return true;
        }
        console.log(`Skipping ${t.name}: ${path.dirname(t.dir)} not found.`);
        return false;
    });

    if (presentTargets.length === 0) {
        console.error("ERROR: No consumer src/ directories found. Nothing to do.");
        process.exit(1);
    }

    for (const target of presentTargets) {
        if (!fs.existsSync(target.dir)) {
            fs.mkdirSync(target.dir, { recursive: true });
            console.log(`Created ${target.dir}`);
        }
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
        const serialized = JSON.stringify(abiOnly, null, 2) + "\n";

        for (const target of presentTargets) {
            const outPath = path.join(target.dir, outName);
            fs.writeFileSync(outPath, serialized);
        }

        console.log(
            `Wrote ${outName} (${artifact.abi.length} entries) → ${presentTargets
                .map((t) => t.name)
                .join(", ")}`
        );
    }

    console.log("\nDone.");
    for (const t of presentTargets) {
        console.log(`  - ${t.name}: ${t.dir}`);
    }
}

main();
