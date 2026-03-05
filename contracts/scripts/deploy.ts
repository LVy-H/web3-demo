import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // 1. Deploy Poseidon library
    const PoseidonT3Factory = await ethers.getContractFactory("PoseidonT3");
    const poseidonT3 = await PoseidonT3Factory.deploy();

    // 2. Deploy Semaphore verifier
    const SemaphoreVerifierFactory = await ethers.getContractFactory("MockSemaphoreVerifier");
    const semaphoreVerifier = await SemaphoreVerifierFactory.deploy();
    const verifierAddress = await semaphoreVerifier.getAddress();
    console.log("SemaphoreVerifier deployed to:", verifierAddress);

    // 3. Deploy Semaphore core utilizing Poseidon
    const SemaphoreFactory = await ethers.getContractFactory("Semaphore", {
        libraries: {
            "poseidon-solidity/PoseidonT3.sol:PoseidonT3": await poseidonT3.getAddress(),
        },
    });
    const semaphore = await SemaphoreFactory.deploy(verifierAddress);
    const semaphoreAddress = await semaphore.getAddress();
    console.log("Semaphore deployed to:", semaphoreAddress);

    console.log("\n==============================================");

    // 4. Deploy ZkVotingFactory
    const ZkVotingFactoryContract = await ethers.getContractFactory("ZkVotingFactory");
    const zkVotingFactory = await ZkVotingFactoryContract.deploy(semaphoreAddress);
    console.log("ZkVotingFactory deployed to:", await zkVotingFactory.getAddress());

    // 5. Deploy ZkAirdrop
    // Providing 1 ETH as the airdrop claim amount per person
    const claimAmount = ethers.parseEther("1.0");
    const ZkAirdropFactory = await ethers.getContractFactory("ZkAirdrop");
    const zkAirdrop = await ZkAirdropFactory.deploy(semaphoreAddress, claimAmount);
    console.log("ZkAirdrop deployed to:", await zkAirdrop.getAddress());

    // Fund the airdrop contract with 10 ETH total pool
    const fundTx = await deployer.sendTransaction({
        to: await zkAirdrop.getAddress(),
        value: ethers.parseEther("10.0")
    });
    await fundTx.wait();
    console.log("ZkAirdrop funded with 10 ETH");

    console.log("==============================================\n");

    // Output dynamically generated addresses
    const frontendSrcDir = path.join(__dirname, "../frontend/src");
    if (fs.existsSync(frontendSrcDir)) {
        const addressMap = {
            FACTORY_ADDRESS: await zkVotingFactory.getAddress(),
            AIRDROP_ADDRESS: await zkAirdrop.getAddress(),
        };
        fs.writeFileSync(
            path.join(frontendSrcDir, "deployed-addresses.json"),
            JSON.stringify(addressMap, null, 2)
        );
        console.log("Saved dynamically generated addresses to frontend/src/deployed-addresses.json");
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
