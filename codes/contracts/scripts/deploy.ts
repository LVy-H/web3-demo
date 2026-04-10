import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with:", deployer.address);
    console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH\n");

    // ── 1. Deploy PoseidonT3 library ────────────────────────────────
    const PoseidonT3Factory = await ethers.getContractFactory("PoseidonT3");
    const poseidonT3 = await PoseidonT3Factory.deploy();
    await poseidonT3.waitForDeployment();
    const poseidonAddress = await poseidonT3.getAddress();
    console.log("PoseidonT3 deployed to:", poseidonAddress);

    // ── 2. Deploy MockSemaphoreVerifier ─────────────────────────────
    const MockVerifierFactory = await ethers.getContractFactory("MockSemaphoreVerifier");
    const mockVerifier = await MockVerifierFactory.deploy();
    await mockVerifier.waitForDeployment();
    const verifierAddress = await mockVerifier.getAddress();
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

    // ── 9. Write deployed-addresses.json to frontend ────────────────
    const addressMap = {
        REGISTRY_ADDRESS: registryAddress,
        SEMAPHORE_ADDRESS: semaphoreAddress,
        ANON_VOTING_IMPL: anonVotingImplAddress,
        AIRDROP_ADDRESS: airdropAddress,
    };

    const frontendSrcDir = path.resolve(__dirname, "../../frontend/src");
    if (fs.existsSync(frontendSrcDir)) {
        fs.writeFileSync(
            path.join(frontendSrcDir, "deployed-addresses.json"),
            JSON.stringify(addressMap, null, 2) + "\n"
        );
        console.log("Saved deployed addresses to frontend/src/deployed-addresses.json");
    } else {
        console.warn("WARNING: frontend/src/ not found at", frontendSrcDir);
        console.log("Deployed addresses (copy manually):");
    }

    console.log(JSON.stringify(addressMap, null, 2));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
