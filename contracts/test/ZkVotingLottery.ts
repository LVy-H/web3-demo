import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";

/**
 * Builds a dummy SemaphoreProof struct for use in local Hardhat tests.
 *
 * The MockSemaphoreVerifier always returns true, so the ZK points can be zeros.
 * The merkleTreeRoot MUST match the on-chain root (computed off-chain with the
 * same @semaphore-protocol/group library that mirrors the on-chain IMT).
 *
 * @param merkleTreeRoot - Off-chain Merkle root matching the on-chain group state.
 * @param nullifier      - Unique identifier for this proof; used to prevent double-use.
 * @param message        - The signal/message encoded as a uint256.
 * @param scope          - The domain-separator scope encoded as a uint256.
 * @param depth          - Merkle tree depth (1 for a single-member group).
 */
function buildMockProof(
    merkleTreeRoot: bigint,
    nullifier: bigint,
    message: bigint,
    scope: bigint,
    depth: number = 1
) {
    return {
        merkleTreeDepth: depth,
        merkleTreeRoot,
        nullifier,
        message,
        scope,
        points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
    };
}

describe("ZkVotingLottery", function () {
    let semaphore: any;
    let lottery: any;
    let owner: any;
    let voter1: Identity;
    let voter2: Identity;

    beforeEach(async function () {
        [owner] = await ethers.getSigners();

        // 1. Deploy PoseidonT3 library (required by Semaphore's IncrementalMerkleTree)
        const PoseidonT3Factory = await ethers.getContractFactory("PoseidonT3");
        const poseidonT3 = await PoseidonT3Factory.deploy();

        // 2. Deploy MockSemaphoreVerifier (always returns true – test-only)
        const MockVerifierFactory = await ethers.getContractFactory("MockSemaphoreVerifier");
        const mockVerifier = await MockVerifierFactory.deploy();

        // 3. Deploy the Semaphore contract using the mock verifier
        const SemaphoreFactory = await ethers.getContractFactory("Semaphore", {
            libraries: {
                "poseidon-solidity/PoseidonT3.sol:PoseidonT3": await poseidonT3.getAddress()
            }
        });
        semaphore = await SemaphoreFactory.deploy(await mockVerifier.getAddress());

        // 4. Deploy our ZkVotingLottery contract
        const LotteryFactory = await ethers.getContractFactory("ZkVotingLottery");
        lottery = await LotteryFactory.deploy(await semaphore.getAddress());

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

    it("Should reject registration during voting phase", async function () {
        await lottery.startVoting();
        await expect(lottery.registerVoter(voter1.commitment))
            .to.be.revertedWith("Not in registration phase");
    });

    it("Should reject double voting via nullifier reuse", async function () {
        await lottery.registerVoter(voter1.commitment);

        const group = new Group();
        group.addMember(voter1.commitment);

        await lottery.startVoting();

        const scope = BigInt(await lottery.getAddress());
        const root = group.root;
        const nullifier = 111n;

        const proof = buildMockProof(root, nullifier, 1n, scope);

        await lottery.castVote(1, proof);

        // Second vote with the same nullifier must revert
        await expect(lottery.castVote(1, proof))
            .to.be.revertedWith("You have already voted");
    });

    it("Should execute a full ZK voting, lottery, and prize-claim flow", async function () {
        // ── Phase 1: Registration ──────────────────────────────────────────────
        await lottery.registerVoter(voter1.commitment);

        // Mirror the on-chain group state in JavaScript so roots match
        const group = new Group();
        group.addMember(voter1.commitment);

        // ── Phase 2: Voting ────────────────────────────────────────────────────
        await lottery.startVoting();

        const candidateId = 1n;
        const contractAddress = await lottery.getAddress();

        // scope must equal uint256(uint160(address(this))) as required by castVote
        const voteScope = BigInt(contractAddress);
        const merkleRoot = group.root;

        // Unique nullifier for the vote proof (arbitrary in mock tests)
        const voteNullifier = 42n;
        const voteProof = buildMockProof(merkleRoot, voteNullifier, candidateId, voteScope);

        await expect(lottery.castVote(candidateId, voteProof))
            .to.emit(lottery, "VoteCast")
            .withArgs(candidateId);

        expect(await lottery.voteCounts(candidateId)).to.equal(1n);
        expect(await lottery.isNullifierUsed(voteNullifier)).to.be.true;

        // ── Phase 3: End voting & draw lottery ────────────────────────────────
        await lottery.endVotingAndDrawLottery();

        const winningNullifier = await lottery.winningNullifier();
        expect(winningNullifier).to.equal(voteNullifier);

        // ── Phase 4: Claim prize ───────────────────────────────────────────────
        const claimScope = BigInt(ethers.keccak256(ethers.toUtf8Bytes("CLAIM_PRIZE_SCOPE")));
        const receiver = owner.address;
        const claimMessage = BigInt(receiver);

        // Claim proof uses a separate nullifier (different scope → different proof)
        const claimNullifier = 99n;
        const claimProof = buildMockProof(merkleRoot, claimNullifier, claimMessage, claimScope);

        await expect(lottery.claimPrize(receiver, claimProof))
            .to.emit(lottery, "PrizeClaimed")
            .withArgs(receiver, claimNullifier);

        expect(await lottery.prizeClaimed()).to.be.true;
    });
});

