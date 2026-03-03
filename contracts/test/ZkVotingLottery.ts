import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import { generateProof } from "@semaphore-protocol/proof";

describe("ZkVotingLottery", function () {
    let semaphore: any;
    let lottery: any;
    let owner: any;
    let voter1: Identity;
    let voter2: Identity;

    beforeEach(async function () {
        [owner] = await ethers.getSigners();

        // 1. Deploy PoseidonT3 library
        const PoseidonT3Factory = await ethers.getContractFactory("PoseidonT3");
        const poseidonT3 = await PoseidonT3Factory.deploy();

        // 1.5. Deploy SemaphoreVerifier
        const VerifierFactory = await ethers.getContractFactory("SemaphoreVerifier");
        const verifier = await VerifierFactory.deploy();

        // 2. Deploy the original Semaphore contract with linked lib and verifier
        const SemaphoreFactory = await ethers.getContractFactory("Semaphore", {
            libraries: {
                "poseidon-solidity/PoseidonT3.sol:PoseidonT3": await poseidonT3.getAddress()
            }
        });
        // Semaphore V4 constructor takes ISemaphoreVerifier address
        semaphore = await SemaphoreFactory.deploy(await verifier.getAddress());

        // 3. Deploy our ZkVotingLottery contract
        const LotteryFactory = await ethers.getContractFactory("ZkVotingLottery");
        lottery = await LotteryFactory.deploy(await semaphore.getAddress());

        // Initial voters identities
        voter1 = new Identity("secret1");
        voter2 = new Identity("secret2");
    });

    it("Should allow voters to register in the registration phase", async function () {
        await expect(lottery.registerVoter(voter1.commitment))
            .to.emit(lottery, "VoterRegistered")
            .withArgs(voter1.commitment);

        await expect(lottery.registerVoter(voter2.commitment))
            .to.emit(lottery, "VoterRegistered")
            .withArgs(voter2.commitment);
    });

    it("Should execute a full ZK voting and claim flow", async function () {
        // Phase 1: Registration
        await lottery.registerVoter(voter1.commitment);

        // We must track the group off-chain exactly as it is on-chain to generate valid proofs
        const group = new Group();
        group.addMember(voter1.commitment);

        // Phase 2: Voting
        await lottery.startVoting();

        const candidateId = 1;
        // The "message/signal" is the vote itself in our implementation
        const signal = candidateId;

        // Generate ZK proof off-chain
        const expectedScope = await lottery.getAddress();

        // In V4: generateProof(identity, group, message, scope)
        const fullProof = await generateProof(voter1, group, signal, expectedScope);

        // fullProof is an object of type SemaphoreProof which exactly matches the ISemaphore.SemaphoreProof struct
        // Struct: { merkleTreeDepth, merkleTreeRoot, nullifier, message, scope, points: [...] }
        const contractProofParams = {
            merkleTreeDepth: fullProof.merkleTreeDepth,
            merkleTreeRoot: fullProof.merkleTreeRoot,
            nullifier: fullProof.nullifier,
            message: fullProof.message,
            scope: fullProof.scope,
            points: fullProof.points
        };

        // Submit the vote on-chain
        await expect(
            lottery.castVote(
                signal,
                contractProofParams
            )
        ).to.emit(lottery, "VoteCast").withArgs(candidateId);

        expect(await lottery.voteCounts(candidateId)).to.equal(1);
        expect(await lottery.isNullifierUsed(fullProof.nullifier)).to.be.true;

        // Phase 3: Lottery and Prizes
        await lottery.endVotingAndDrawLottery();

        const winningNullifier = await lottery.winningNullifier();
        expect(winningNullifier).to.equal(fullProof.nullifier);

        // Phase 4: Claiming Prize
        const claimScope = BigInt(ethers.keccak256(ethers.toUtf8Bytes("CLAIM_PRIZE_SCOPE")));
        const claimReceiverAddress = owner.address;
        const claimSignal = BigInt(claimReceiverAddress);

        const claimProof = await generateProof(voter1, group, claimSignal, claimScope);

        const contractClaimProofParams = {
            merkleTreeDepth: claimProof.merkleTreeDepth,
            merkleTreeRoot: claimProof.merkleTreeRoot,
            nullifier: claimProof.nullifier,
            message: claimProof.message,
            scope: claimProof.scope,
            points: claimProof.points
        };

        await expect(
            lottery.claimPrize(
                claimReceiverAddress,
                contractClaimProofParams
            )
        ).to.emit(lottery, "PrizeClaimed").withArgs(claimReceiverAddress, claimProof.nullifier);
    });
});
