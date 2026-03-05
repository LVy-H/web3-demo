import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import * as crypto from "crypto";

describe("ZkVoting Token Flow", function () {
    let semaphore: any;
    let voting: any;
    let owner: any;
    let nonOwner: any;
    let tokens: string[] = [];
    let commitments: bigint[] = [];

    beforeEach(async function () {
        [owner, nonOwner] = await ethers.getSigners();

        const PoseidonT3Factory = await ethers.getContractFactory("PoseidonT3");
        const poseidonT3 = await PoseidonT3Factory.deploy();

        const MockVerifierFactory = await ethers.getContractFactory("MockSemaphoreVerifier");
        const mockVerifier = await MockVerifierFactory.deploy();

        const SemaphoreFactory = await ethers.getContractFactory("Semaphore", {
            libraries: { "poseidon-solidity/PoseidonT3.sol:PoseidonT3": await poseidonT3.getAddress() }
        });
        semaphore = await SemaphoreFactory.deploy(await mockVerifier.getAddress());

        const ZkVotingFactoryContract = await ethers.getContractFactory("ZkVotingFactory");
        const factory = await ZkVotingFactoryContract.deploy(await semaphore.getAddress());

        // Create poll with initial options
        await factory.createPoll("Test Poll", "A description", ["Option A", "Option B", "Option C"]);
        const polls = await factory.getAllPolls();
        const pollAddress = polls[0].pollAddress;

        voting = await ethers.getContractAt("ZkVoting", pollAddress);

        // Generate 3 tokens simulating admin token generation
        tokens = [];
        commitments = [];
        for (let i = 0; i < 3; i++) {
            const pk = crypto.randomBytes(32).toString("hex");
            const identity = new Identity(pk);
            tokens.push(pk);
            commitments.push(identity.commitment);
        }
    });

    it("Should have 3 initial options", async function () {
        const opts = await voting.getOptions();
        expect(opts.length).to.equal(3);
        expect(opts[0]).to.equal("Option A");
        expect(opts[1]).to.equal("Option B");
        expect(opts[2]).to.equal("Option C");
    });

    it("Should allow owner to add options during registration", async function () {
        await voting.addOption("Option D");
        const opts = await voting.getOptions();
        expect(opts.length).to.equal(4);
        expect(opts[3]).to.equal("Option D");
    });

    it("Should reject non-owner adding options", async function () {
        await expect(
            voting.connect(nonOwner).addOption("Unauthorized")
        ).to.be.revertedWith("Not owner");
    });

    it("Should reject non-owner registering voters", async function () {
        await expect(
            voting.connect(nonOwner).registerVoter(commitments[0])
        ).to.be.revertedWith("Not owner");
    });

    it("Should batch register tokens and cast vote successfully", async function () {
        // 1. Admin bulk registers
        const tx = await voting.registerVoters(commitments);
        await tx.wait();

        const group = new Group();
        commitments.forEach(c => group.addMember(c));

        // 2. Start voting
        await voting.startVoting();

        // 3. User uses Token #2 to vote for option index 1 (Option B)
        const userIdentity = new Identity(tokens[1]);
        const optionIndex = 1n;
        const scope = BigInt(await voting.getAddress());

        const mockProof = {
            merkleTreeDepth: 1,
            merkleTreeRoot: group.root,
            nullifier: 111n,
            message: optionIndex,
            scope: scope,
            points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
        };

        await expect(voting.castVote(optionIndex, mockProof))
            .to.emit(voting, "VoteCast")
            .withArgs(optionIndex);

        expect(await voting.voteCounts(optionIndex)).to.equal(1n);
    });

    it("Should reject vote for invalid option index", async function () {
        await voting.registerVoters(commitments);
        await voting.startVoting();

        const group = new Group();
        commitments.forEach(c => group.addMember(c));

        const invalidIndex = 99n;
        const scope = BigInt(await voting.getAddress());

        const mockProof = {
            merkleTreeDepth: 1,
            merkleTreeRoot: group.root,
            nullifier: 222n,
            message: invalidIndex,
            scope: scope,
            points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
        };

        await expect(voting.castVote(invalidIndex, mockProof))
            .to.be.revertedWith("Invalid option index");
    });

    it("Should require at least 2 options to start voting", async function () {
        // Deploy a poll with only 1 option
        const ZkVotingFactoryContract = await ethers.getContractFactory("ZkVotingFactory");
        const factory2 = await ZkVotingFactoryContract.deploy(await semaphore.getAddress());
        await factory2.createPoll("Sparse Poll", "Only one option", ["Only Option"]);
        const polls = await factory2.getAllPolls();
        const sparseVoting = await ethers.getContractAt("ZkVoting", polls[0].pollAddress);

        await expect(sparseVoting.startVoting())
            .to.be.revertedWith("Need at least 2 options");
    });
});
