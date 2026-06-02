import { ethers, network } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
    const networkName = network.name;
    const chainId = Number((await ethers.provider.getNetwork()).chainId);
    const useRealVerifier = process.env.USE_REAL_VERIFIER === "true";
    const isPublicNetwork = networkName !== "hardhat" && networkName !== "localhost";

    console.log(`\nNetwork: ${networkName} (chainId=${chainId})`);

    // ── Refuse mock verifier on any non-local network ───────────────
    // The MockSemaphoreVerifier accepts ANY proof. Deploying it to a
    // public network would let attackers submit garbage proofs.
    if (isPublicNetwork && !useRealVerifier) {
        throw new Error(
            `Refusing to deploy MockSemaphoreVerifier on public network "${networkName}". ` +
            `Set USE_REAL_VERIFIER=true (and complete P4-23 wiring) before deploying to a public chain.`
        );
    }

    if (!useRealVerifier) {
        console.log("\n" + "═".repeat(70));
        console.log("  ⚠  WARNING: deploying with MockSemaphoreVerifier");
        console.log("     ZK proofs will be ACCEPTED WITHOUT VERIFICATION.");
        console.log("     Use this only for local development. NEVER on a public network.");
        console.log("     For real Groth16 verification, run: USE_REAL_VERIFIER=true npm run deploy:local");
        console.log("═".repeat(70) + "\n");
    }

    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with:", deployer.address);
    console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH\n");

    // ── 1. Deploy PoseidonT3 library ────────────────────────────────
    const PoseidonT3Factory = await ethers.getContractFactory("PoseidonT3");
    const poseidonT3 = await PoseidonT3Factory.deploy();
    await poseidonT3.waitForDeployment();
    const poseidonAddress = await poseidonT3.getAddress();
    console.log("PoseidonT3 deployed to:", poseidonAddress);

    // ── 2. Deploy verifier (Mock by default, real Groth16 when USE_REAL_VERIFIER=true) ──
    let verifierAddress: string;
    if (useRealVerifier) {
        // TODO(P4-23): wire real SemaphoreVerifier. Requires:
        //   1. A stub source under contracts/ that imports
        //      "@semaphore-protocol/contracts/base/SemaphoreVerifier.sol"
        //      so hardhat compiles the artifact (currently not pulled in by any
        //      source under ./contracts/, so getContractFactory("SemaphoreVerifier")
        //      would fail at runtime).
        //   2. SNARK artifact bundling (P4-24) so generated proofs actually verify.
        throw new Error(
            "USE_REAL_VERIFIER=true is not yet wired. See P4-23 / P4-24 in docs/improvements/findings.md."
        );
    }
    const MockVerifierFactory = await ethers.getContractFactory("MockSemaphoreVerifier");
    const mockVerifier = await MockVerifierFactory.deploy();
    await mockVerifier.waitForDeployment();
    verifierAddress = await mockVerifier.getAddress();
    console.log("MockSemaphoreVerifier deployed to:", verifierAddress);

    // ── 3. Deploy Semaphore (linked to PoseidonT3, using MockVerifier) ──
    const SemaphoreFactory = await ethers.getContractFactory("Semaphore", {
        libraries: {
            "poseidon-solidity/PoseidonT3.sol:PoseidonT3": poseidonAddress,
        },
    });
    const semaphore = await SemaphoreFactory.deploy(verifierAddress);
    await semaphore.waitForDeployment();
    const semaphoreAddress = await semaphore.getAddress();
    console.log("Semaphore deployed to:", semaphoreAddress);

    // ── 4. Deploy PollRegistry ──────────────────────────────────────
    const PollRegistryFactory = await ethers.getContractFactory("PollRegistry");
    const pollRegistry = await PollRegistryFactory.deploy();
    await pollRegistry.waitForDeployment();
    const registryAddress = await pollRegistry.getAddress();
    console.log("PollRegistry deployed to:", registryAddress);

    // ── 5. Deploy ZkAnonVoting implementation (bare, uninitialized) ─
    const ZkAnonVotingFactory = await ethers.getContractFactory("ZkAnonVoting");
    const zkAnonVotingImpl = await ZkAnonVotingFactory.deploy();
    await zkAnonVotingImpl.waitForDeployment();
    const anonVotingImplAddress = await zkAnonVotingImpl.getAddress();
    console.log("ZkAnonVoting (impl) deployed to:", anonVotingImplAddress);

    // ── 6. Register "anon-vote" module in PollRegistry ──────────────
    const regTx = await pollRegistry.registerModule("anon-vote", anonVotingImplAddress);
    await regTx.wait();
    console.log('Registered "anon-vote" module in PollRegistry');

    // ── 6b. Deploy ZkBlindVoting implementation (bare, uninitialized) ─
    const ZkBlindVotingFactory = await ethers.getContractFactory("ZkBlindVoting");
    const zkBlindVotingImpl = await ZkBlindVotingFactory.deploy();
    await zkBlindVotingImpl.waitForDeployment();
    const blindVotingImplAddress = await zkBlindVotingImpl.getAddress();
    console.log("ZkBlindVoting (impl) deployed to:", blindVotingImplAddress);

    // ── 6c. Register "blind-vote" module in PollRegistry ────────────
    const regBlindTx = await pollRegistry.registerModule("blind-vote", blindVotingImplAddress);
    await regBlindTx.wait();
    console.log('Registered "blind-vote" module in PollRegistry');

    // ── 6d. Deploy ZkApprovalVoting implementation (bare, uninitialized) ─
    const ZkApprovalVotingFactory = await ethers.getContractFactory("ZkApprovalVoting");
    const zkApprovalVotingImpl = await ZkApprovalVotingFactory.deploy();
    await zkApprovalVotingImpl.waitForDeployment();
    const approvalVotingImplAddress = await zkApprovalVotingImpl.getAddress();
    console.log("ZkApprovalVoting (impl) deployed to:", approvalVotingImplAddress);

    // ── 6e. Register "approval-vote" module in PollRegistry ─────────
    // Canonical module string "approval-vote" — used IDENTICALLY in the test
    // harness and the relayer (we do NOT repeat M1's anon-vote/zk-anon-voting split).
    const regApprovalTx = await pollRegistry.registerModule("approval-vote", approvalVotingImplAddress);
    await regApprovalTx.wait();
    console.log('Registered "approval-vote" module in PollRegistry');

    console.log("\n==============================================");

    // ── 7. Deploy ZkAirdrop (unchanged) ─────────────────────────────
    const claimAmount = ethers.parseEther("1.0");
    const ZkAirdropFactory = await ethers.getContractFactory("ZkAirdrop");
    const zkAirdrop = await ZkAirdropFactory.deploy(semaphoreAddress, claimAmount);
    await zkAirdrop.waitForDeployment();
    const airdropAddress = await zkAirdrop.getAddress();
    console.log("ZkAirdrop deployed to:", airdropAddress);

    // ── 8. Fund ZkAirdrop with 10 ETH ──────────────────────────────
    const fundTx = await deployer.sendTransaction({
        to: airdropAddress,
        value: ethers.parseEther("10.0"),
    });
    await fundTx.wait();
    console.log("ZkAirdrop funded with 10 ETH");

    console.log("==============================================\n");
    console.log(`Network: ${networkName} (chainId=${chainId})`);

    // ── 9. Write deployed-addresses.json (neutral location) ──────────
    // The file is chainId-keyed so multiple networks can coexist in one file.
    // Lives under codes/contracts/ (not the deprecated frontend) — the dev-stack
    // and demo-poll script read it from here.
    const networkEntry = {
        REGISTRY_ADDRESS: registryAddress,
        SEMAPHORE_ADDRESS: semaphoreAddress,
        ANON_VOTING_IMPL: anonVotingImplAddress,
        BLIND_VOTING_IMPL: blindVotingImplAddress,
        APPROVAL_VOTING_IMPL: approvalVotingImplAddress,
        AIRDROP_ADDRESS: airdropAddress,
    };

    const addressesPath = path.resolve(__dirname, "../deployed-addresses.json");
    // Merge with existing entries so deploying to one network does not wipe others.
    let existing: Record<string, unknown> = {};
    if (fs.existsSync(addressesPath)) {
        try {
            existing = JSON.parse(fs.readFileSync(addressesPath, "utf-8"));
        } catch {
            existing = {};
        }
    }
    const merged = { ...existing, [String(chainId)]: networkEntry };
    fs.writeFileSync(addressesPath, JSON.stringify(merged, null, 2) + "\n");
    console.log(`Saved deployed addresses to codes/contracts/deployed-addresses.json (chainId ${chainId})`);

    console.log(JSON.stringify({ [String(chainId)]: networkEntry }, null, 2));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
