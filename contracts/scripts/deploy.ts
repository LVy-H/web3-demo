import { ethers } from "hardhat";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // 1. Deploy PoseidonT3 library
    const PoseidonT3Factory = await ethers.getContractFactory("PoseidonT3");
    const poseidonT3 = await PoseidonT3Factory.deploy();
    await poseidonT3.waitForDeployment();
    console.log("PoseidonT3 deployed to:", await poseidonT3.getAddress());

    // 2. Deploy SemaphoreVerifier
    const VerifierFactory = await ethers.getContractFactory("SemaphoreVerifier");
    const verifier = await VerifierFactory.deploy();
    await verifier.waitForDeployment();
    console.log("SemaphoreVerifier deployed to:", await verifier.getAddress());

    // 3. Deploy the Semaphore Core Contract
    const SemaphoreFactory = await ethers.getContractFactory("Semaphore", {
        libraries: {
            "poseidon-solidity/PoseidonT3.sol:PoseidonT3": await poseidonT3.getAddress()
        }
    });

    const semaphore = await SemaphoreFactory.deploy(await verifier.getAddress());
    await semaphore.waitForDeployment();
    console.log("Semaphore deployed to:", await semaphore.getAddress());

    // 4. Deploy our ZkVotingLottery contract
    const LotteryFactory = await ethers.getContractFactory("ZkVotingLottery");
    const lottery = await LotteryFactory.deploy(await semaphore.getAddress());
    await lottery.waitForDeployment();

    console.log("\n==============================================");
    console.log("ZkVotingLottery deployed to:", await lottery.getAddress());
    console.log("==============================================\n");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
