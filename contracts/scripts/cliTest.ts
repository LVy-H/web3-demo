import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import { generateProof } from "@semaphore-protocol/proof";

async function runVotingTest(admin: any, voter: any, zkVotingAddress: string) {
    console.log("\n--- Starting ZkVoting End-to-End Test ---");
    const ZkVoting = await ethers.getContractFactory("ZkVoting");
    const voting = ZkVoting.attach(zkVotingAddress) as any;

    const voterIdentity = new Identity();
    const group = new Group();
    console.log("1. Generated Voter Identity");

    // Registration
    let tx = await voting.connect(voter).registerVoter(voterIdentity.commitment);
    await tx.wait();
    group.addMember(voterIdentity.commitment);
    console.log("2. Registered Voter Commitment On-chain");

    // Start
    tx = await voting.connect(admin).startVoting();
    await tx.wait();
    console.log("3. Admin Started Voting Phase");

    // ZK Vote
    const candidateId = 1;
    const scope = zkVotingAddress;
    const proof = await generateProof(voterIdentity, group, candidateId, scope);

    const voteStruct = {
        merkleTreeDepth: proof.merkleTreeDepth,
        merkleTreeRoot: proof.merkleTreeRoot,
        nullifier: proof.nullifier,
        message: proof.message,
        scope: proof.scope,
        points: proof.points
    };

    tx = await voting.connect(voter).castVote(candidateId, voteStruct);
    await tx.wait();
    console.log("4. Vote Cast Anonymously via ZK Proof!");

    const count = await voting.voteCounts(candidateId);
    console.log(`   Candidate ${candidateId} Votes: ${count.toString()}`);

    // End
    tx = await voting.connect(admin).endVoting();
    await tx.wait();
    console.log("5. Voting Ended.");
}

async function runAirdropTest(admin: any, member: any, zkAirdropAddress: string) {
    console.log("\n--- Starting ZkAirdrop End-to-End Test ---");
    const ZkAirdrop = await ethers.getContractFactory("ZkAirdrop");
    const airdrop = ZkAirdrop.attach(zkAirdropAddress) as any;

    const memberIdentity = new Identity();
    const group = new Group();
    console.log("1. Generated Member Identity");

    // Registration
    let tx = await airdrop.connect(member).registerMember(memberIdentity.commitment);
    await tx.wait();
    group.addMember(memberIdentity.commitment);
    console.log("2. Registered Member Commitment On-chain");

    // Start
    tx = await airdrop.connect(admin).startAirdrop();
    await tx.wait();
    console.log("3. Admin Started Airdrop Claiming Phase");

    // Claim
    const freshAddress = ethers.Wallet.createRandom().address;
    const scope = zkAirdropAddress; // the contract requires proof.scope == address(this)
    const signal = BigInt(freshAddress);

    // Member generates proof of belonging to the whitelist to claim funds to `freshAddress`
    const proof = await generateProof(memberIdentity, group, signal, scope);

    const claimStruct = {
        merkleTreeDepth: proof.merkleTreeDepth,
        merkleTreeRoot: proof.merkleTreeRoot,
        nullifier: proof.nullifier,
        message: proof.message,
        scope: proof.scope,
        points: proof.points
    };

    // Any account can relay this transaction
    tx = await airdrop.connect(admin).claimAirdrop(freshAddress, claimStruct);
    await tx.wait();
    console.log(`4. Successfully Claimed Airdrop to fresh anonymous address: ${freshAddress}`);

    const isUsed = await airdrop.isNullifierUsed(proof.nullifier);
    console.log(`   Nullifier specifically marked as used to prevent double claiming: ${isUsed}`);
}

async function main() {
    console.log("Preparing test environment...");
    const [admin, user1, user2] = await ethers.getSigners();

    // Use the latest deployment artifacts
    // In a pure hardhat environment, we could deploy in memory, but we'll fetch from local node
    // for consistency with the user's previous workflows.

    // We will deploy fresh instances for these tests specifically so we don't worry about hardcoded addresses
    console.log("Deploying fresh contracts for tests...");

    const PoseidonT3Factory = await ethers.getContractFactory("PoseidonT3");
    const poseidonT3 = await PoseidonT3Factory.deploy();

    const SemaphoreVerifierFactory = await ethers.getContractFactory("MockSemaphoreVerifier");
    const verifier = await SemaphoreVerifierFactory.deploy();

    const SemaphoreFactory = await ethers.getContractFactory("Semaphore", {
        libraries: { "poseidon-solidity/PoseidonT3.sol:PoseidonT3": await poseidonT3.getAddress() }
    });
    const semaphore = await SemaphoreFactory.deploy(await verifier.getAddress());

    const ZkVotingFactory = await ethers.getContractFactory("ZkVoting");
    const votingContract = await ZkVotingFactory.deploy(await semaphore.getAddress());

    const ZkAirdropFactory = await ethers.getContractFactory("ZkAirdrop");
    const claimAmount = ethers.parseEther("1.0");
    const airdropContract = await ZkAirdropFactory.deploy(await semaphore.getAddress(), claimAmount);
    await admin.sendTransaction({ to: await airdropContract.getAddress(), value: ethers.parseEther("5.0") });

    // Run tests
    await runVotingTest(admin, user1, await votingContract.getAddress());
    await runAirdropTest(admin, user2, await airdropContract.getAddress());

    console.log("\n--- All Tests Passed for Separated Contracts ---");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
