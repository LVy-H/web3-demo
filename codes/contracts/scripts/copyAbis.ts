import fs from "fs";
import path from "path";

/**
 * Reads compiled Hardhat artifacts and extracts ABI arrays
 * into every consumer's abi directory (the relayer + the Flutter workspace's
 * core_chain package assets — the canonical committed copies).
 *
 * Usage:  npx ts-node scripts/copyAbis.ts
 */

const ARTIFACTS_ROOT = path.resolve(__dirname, "../artifacts/contracts");

// Consumers that need contract ABIs. Skipped silently if the directory
// doesn't exist. An `only` list restricts which CONTRACTS entries a consumer
// receives (core_chain doesn't ship ZkAirdrop).
const ABI_TARGETS: { name: string; dir: string; only?: string[] }[] = [
    { name: "relayer", dir: path.resolve(__dirname, "../../relayer/src/abi") },
    {
        name: "core_chain",
        dir: path.resolve(__dirname, "../../app/packages/core_chain/assets/abi"),
        only: [
            "IZkPoll.json",
            "PollRegistry.json",
            "ZkAnonVoting.json",
            "ZkApprovalVoting.json",
            "ZkRankedVoting.json",
            "ZkQuadraticVoting.json",
            "ZkSurveyVoting.json",
            "ZkBlindVoting.json",
        ],
    },
];

// Map: output file name -> artifact path (relative to ARTIFACTS_ROOT)
const CONTRACTS: Record<string, string> = {
    "IZkPoll.json": "interfaces/IZkPoll.sol/IZkPoll.json",
    "PollRegistry.json": "PollRegistry.sol/PollRegistry.json",
    "ZkAirdrop.json": "ZkAirdrop.sol/ZkAirdrop.json",
    "ZkAnonVoting.json": "ZkAnonVoting.sol/ZkAnonVoting.json",
    "ZkApprovalVoting.json": "ZkApprovalVoting.sol/ZkApprovalVoting.json",
    "ZkRankedVoting.json": "ZkRankedVoting.sol/ZkRankedVoting.json",
    "ZkQuadraticVoting.json": "ZkQuadraticVoting.sol/ZkQuadraticVoting.json",
    "ZkSurveyVoting.json": "ZkSurveyVoting.sol/ZkSurveyVoting.json",
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

        const receivers = presentTargets.filter(
            (t) => !t.only || t.only.includes(outName)
        );
        for (const target of receivers) {
            const outPath = path.join(target.dir, outName);
            fs.writeFileSync(outPath, serialized);
        }

        console.log(
            `Wrote ${outName} (${artifact.abi.length} entries) → ${receivers
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
