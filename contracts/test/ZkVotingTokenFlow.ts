import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import { generateProof } from "@semaphore-protocol/proof";
import * as crypto from "crypto";

describe("ZkVoting Token Flow", function () {
    let semaphore: any;
    let voting: any;
    let owner: any;
    let tokens: string[] = [];
    let commitments: bigint[] = [];

    beforeEach(async function () {
        [owner] = await ethers.getSigners();

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

        await factory.createPoll("Test Poll", "A description");
        const polls = await factory.getAllPolls();
        const pollAddress = polls[0].pollAddress;

        voting = await ethers.getContractAt("ZkVoting", pollAddress);

        // Generate 3 tokens simulating `generateTokens.ts`
        tokens = [];
        commitments = [];
        for (let i = 0; i < 3; i++) {
            const pk = crypto.randomBytes(32).toString("hex");
            const identity = new Identity(pk);
            tokens.push(pk);
            commitments.push(identity.commitment);
        }
    });

    it("Should batch register tokens and cast vote successfully", async function () {
        // 1. Admin bulk registers
        const tx = await voting.registerVoters(commitments);
        await tx.wait();

        const group = new Group();
        commitments.forEach(c => group.addMember(c));

        // 2. Start voting
        await voting.startVoting();

        // 3. User uses Token #2 to vote
        const userIdentity = new Identity(tokens[1]); // using the hex private key
        const candidateId = 2n;
        const scope = BigInt(await voting.getAddress());

        // We build the actual proof structure required by castVote.
        // Because we are using MockSemaphoreVerifier, it doesn't really matter for validity,
        // but it tests the logic of hashing and struct packing.
        const mockProof = {
            merkleTreeDepth: 1, // irrelevant for mock
            merkleTreeRoot: group.root,
            nullifier: 111n, // random mock
            message: candidateId,
            scope: scope,
            points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
        };

        await expect(voting.castVote(candidateId, mockProof))
            .to.emit(voting, "VoteCast")
            .withArgs(candidateId);

        expect(await voting.voteCounts(candidateId)).to.equal(1n);
    });
});
