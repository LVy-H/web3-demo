import { Identity } from "@semaphore-protocol/identity";
import * as fs from "fs";
import * as path from "path";

async function main() {
    const numTokens = 5; // Generate 5 invite tokens for testing
    console.log(`Generating ${numTokens} Invite Tokens...`);

    const tokens = [];
    const commitments = [];

    for (let i = 0; i < numTokens; i++) {
        // The Identity is created using a random string. We will use a secure random hex string.
        const privateKeyBytes = new Uint8Array(32);
        crypto.getRandomValues(privateKeyBytes);
        const privateKeyHex = Buffer.from(privateKeyBytes).toString("hex");

        const identity = new Identity(privateKeyHex);

        tokens.push(privateKeyHex);
        commitments.push(identity.commitment.toString());
    }

    console.log("\n--- ADMIN EYES ONLY ---");
    console.log("Distribute these Invite Tokens privately to voters:");
    tokens.forEach((t, i) => console.log(`Voter ${i + 1}: ${t}`));
    console.log("-----------------------\n");

    const outputPath = path.join(__dirname, "invite-tokens.json");
    fs.writeFileSync(
        outputPath,
        JSON.stringify({ tokens, commitments }, null, 2)
    );

    console.log(
        `Saved tokens and commitments to ${outputPath}`
    );
    console.log(
        "You can now batch-register these commitments using the deploy script or admin tools."
    );
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
