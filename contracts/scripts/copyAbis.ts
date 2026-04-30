import fs from "fs";
import path from "path";

const ARTIFACTS_ROOT = path.resolve(__dirname, "../artifacts/contracts");
const FRONTEND_ABI_DIR = path.resolve(__dirname, "../frontend/src/abi");
const RELAYER_ABI_DIR = path.resolve(__dirname, "../relayer/abi");
// In Docker: /app/scripts/../relayer/abi = /app/relayer/abi (volume-mounted from ./relayer/src/abi)

const CONTRACTS: Record<string, string> = {
    "IZkPoll.json": "interfaces/IZkPoll.sol/IZkPoll.json",
    "PollRegistry.json": "PollRegistry.sol/PollRegistry.json",
    "ZkAnonVoting.json": "ZkAnonVoting.sol/ZkAnonVoting.json",
    "ZkBlindVoting.json": "ZkBlindVoting.sol/ZkBlindVoting.json",
    "ZkAirdrop.json": "ZkAirdrop.sol/ZkAirdrop.json",
};

function writeAbis(outputDir: string, label: string) {
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
        console.log(`Created ${outputDir}`);
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

        const outPath = path.join(outputDir, outName);
        fs.writeFileSync(outPath, JSON.stringify(abiOnly, null, 2) + "\n");
        console.log(`  ${outName} (${artifact.abi.length} entries)`);
    }

    console.log(`  -> ${label} done.\n`);
}

function main() {
    console.log("Copying ABIs to frontend...");
    writeAbis(FRONTEND_ABI_DIR, "frontend");

    console.log("Copying ABIs to relayer...");
    writeAbis(RELAYER_ABI_DIR, "relayer");

    console.log("All ABIs written.");
}

main();
