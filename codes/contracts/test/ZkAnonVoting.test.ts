import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import * as crypto from "crypto";

describe("ZkAnonVoting", function () {
    let semaphore: any;
    let voting: any;
    let owner: any;
    let nonOwner: any;
    let tokens: string[] = [];
    let commitments: bigint[] = [];

    /** Helper: deploy Semaphore stack + a fresh ZkAnonVoting clone via initialize() */
    async function deployVoting(initialOptions: string[] = ["Option A", "Option B", "Option C"]) {
        [owner, nonOwner] = await ethers.getSigners();

        const PoseidonT3 = await ethers.getContractFactory("PoseidonT3");
        const poseidonT3 = await PoseidonT3.deploy();

        const MockVerifier = await ethers.getContractFactory("MockSemaphoreVerifier");
        const verifier = await MockVerifier.deploy();

        const Semaphore = await ethers.getContractFactory("Semaphore", {
            libraries: {
                "poseidon-solidity/PoseidonT3.sol:PoseidonT3": await poseidonT3.getAddress(),
            },
        });
        semaphore = await Semaphore.deploy(await verifier.getAddress());

        const ZkAnonVoting = await ethers.getContractFactory("ZkAnonVoting");
        voting = await ZkAnonVoting.deploy();

        // Initialize (simulates what PollRegistry.createPoll would do on the clone)
        await voting.initialize(
            await semaphore.getAddress(),
            owner.address,
            initialOptions
        );

        // Generate 3 voter identities
        tokens = [];
        commitments = [];
        for (let i = 0; i < 3; i++) {
            const pk = crypto.randomBytes(32).toString("hex");
            const identity = new Identity(pk);
            tokens.push(pk);
            commitments.push(identity.commitment);
        }
    }

    beforeEach(async function () {
        await deployVoting();
    });

    // ── IZkPoll compliance ───────────────────────────────────────────

    describe("IZkPoll compliance", function () {
        it("getState returns Registration initially", async function () {
            expect(await voting.getState()).to.equal(0); // PollState.Registration
        });

        it("getOptions returns initial options", async function () {
            const opts = await voting.getOptions();
            expect(opts).to.deep.equal(["Option A", "Option B", "Option C"]);
        });

        it("getParticipantCount starts at 0", async function () {
            expect(await voting.getParticipantCount()).to.equal(0);
        });

        it("owner returns the correct address", async function () {
            expect(await voting.owner()).to.equal(owner.address);
        });

        it("getResults returns zeroes initially", async function () {
            const results = await voting.getResults();
            expect(results.length).to.equal(3);
            for (const r of results) {
                expect(r).to.equal(0n);
            }
        });
    });

    // ── Registration ─────────────────────────────────────────────────

    describe("Registration", function () {
        it("Owner registers a single voter", async function () {
            await expect(voting.registerVoter(commitments[0]))
                .to.emit(voting, "VoterRegistered")
                .withArgs(commitments[0]);
            expect(await voting.getParticipantCount()).to.equal(1);
        });

        it("Owner batch registers voters", async function () {
            await voting.registerVoters(commitments);
            expect(await voting.getParticipantCount()).to.equal(3);
        });

        it("Non-owner cannot register", async function () {
            await expect(
                voting.connect(nonOwner).registerVoter(commitments[0])
            ).to.be.revertedWith("Not owner");
        });

        it("Duplicate commitment rejected", async function () {
            await voting.registerVoter(commitments[0]);
            await expect(
                voting.registerVoter(commitments[0])
            ).to.be.revertedWith("This identity is already registered");
        });

        it("Duplicate in batch rejected", async function () {
            const dupes = [commitments[0], commitments[0]];
            await expect(voting.registerVoters(dupes)).to.be.revertedWith(
                "Duplicate identity in batch"
            );
        });
    });

    // ── Voting ───────────────────────────────────────────────────────

    describe("Voting", function () {
        let group: any;

        beforeEach(async function () {
            await voting.registerVoters(commitments);
            group = new Group();
            commitments.forEach((c) => group.addMember(c));
            await voting.startVoting();
        });

        it("Cast vote with mock proof succeeds", async function () {
            const optionIndex = 1n;
            const scope = BigInt(await voting.getAddress());

            const mockProof = {
                merkleTreeDepth: 1,
                merkleTreeRoot: group.root,
                nullifier: 111n,
                message: optionIndex,
                scope,
                points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
            };

            await expect(voting.castVote(optionIndex, mockProof))
                .to.emit(voting, "VoteCast")
                .withArgs(optionIndex);

            const results = await voting.getResults();
            expect(results[1]).to.equal(1n);
        });

        it("Double voting rejected", async function () {
            const scope = BigInt(await voting.getAddress());
            const mockProof = {
                merkleTreeDepth: 1,
                merkleTreeRoot: group.root,
                nullifier: 222n,
                message: 0n,
                scope,
                points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
            };

            await voting.castVote(0n, mockProof);
            await expect(voting.castVote(0n, mockProof)).to.be.revertedWith(
                "You have already voted"
            );
        });

        it("Invalid option index rejected", async function () {
            const scope = BigInt(await voting.getAddress());
            const mockProof = {
                merkleTreeDepth: 1,
                merkleTreeRoot: group.root,
                nullifier: 333n,
                message: 99n,
                scope,
                points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
            };

            await expect(voting.castVote(99n, mockProof)).to.be.revertedWith(
                "Invalid option index"
            );
        });
    });

    // ── Participation verification ───────────────────────────────────

    describe("Participation verification", function () {
        it("Returns true after voting with that nullifier", async function () {
            await voting.registerVoters(commitments);
            const group = new Group();
            commitments.forEach((c) => group.addMember(c));
            await voting.startVoting();

            const scope = BigInt(await voting.getAddress());
            const nullifier = 444n;
            const mockProof = {
                merkleTreeDepth: 1,
                merkleTreeRoot: group.root,
                nullifier,
                message: 0n,
                scope,
                points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
            };

            await voting.castVote(0n, mockProof);
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
        });

        it("Returns false for unused nullifier", async function () {
            expect(await voting.verifyParticipation(999n)).to.equal(false);
        });
    });

    // ── State transitions ────────────────────────────────────────────

    describe("State transitions", function () {
        it("Requires at least 2 options to start voting", async function () {
            // Deploy with only 1 option
            const ZkAnonVoting = await ethers.getContractFactory("ZkAnonVoting");
            const sparse = await ZkAnonVoting.deploy();
            await sparse.initialize(
                await semaphore.getAddress(),
                owner.address,
                ["Only Option"]
            );

            await expect(sparse.startVoting()).to.be.revertedWith(
                "Need at least 2 options"
            );
        });

        it("Cannot vote in Registration phase", async function () {
            const scope = BigInt(await voting.getAddress());
            const mockProof = {
                merkleTreeDepth: 1,
                merkleTreeRoot: 0n,
                nullifier: 555n,
                message: 0n,
                scope,
                points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
            };

            await expect(voting.castVote(0n, mockProof)).to.be.revertedWith(
                "Not in voting phase"
            );
        });

        it("Cannot end voting from Registration phase", async function () {
            await expect(voting.endVoting()).to.be.revertedWith(
                "Not in voting phase"
            );
        });

        it("startVoting emits StateChanged", async function () {
            await expect(voting.startVoting())
                .to.emit(voting, "StateChanged")
                .withArgs(1); // PollState.Voting
        });

        it("endVoting emits StateChanged", async function () {
            await voting.startVoting();
            await expect(voting.endVoting())
                .to.emit(voting, "StateChanged")
                .withArgs(2); // PollState.Ended
        });

        it("Prevents double initialization", async function () {
            await expect(
                voting.initialize(
                    await semaphore.getAddress(),
                    owner.address,
                    ["X", "Y"]
                )
            ).to.be.revertedWith("Already initialized");
        });
    });

    // ── Admin controls ───────────────────────────────────────────────

    describe("Admin controls", function () {
        it("Owner can add option during registration", async function () {
            await voting.addOption("Option D");
            const opts = await voting.getOptions();
            expect(opts.length).to.equal(4);
            expect(opts[3]).to.equal("Option D");
        });

        it("Cannot add option after registration phase", async function () {
            await voting.startVoting();
            await expect(voting.addOption("Late Option")).to.be.revertedWith(
                "Not in registration phase"
            );
        });

        it("Non-owner cannot add option", async function () {
            await expect(
                voting.connect(nonOwner).addOption("Unauthorized")
            ).to.be.revertedWith("Not owner");
        });
    });
});
