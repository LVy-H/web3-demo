import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("ZkBlindVoting", function () {
    let voting: any;
    let owner: any;
    let voter1: any;
    let voter2: any;
    let voter3: any;
    let nonVoter: any;

    const REVEAL_DURATION = 3600; // 1 hour

    /** Helper: deploy a fresh ZkBlindVoting instance */
    async function deployVoting(
        initialOptions: string[] = ["Option A", "Option B", "Option C"],
        revealDuration: number = REVEAL_DURATION
    ) {
        [owner, voter1, voter2, voter3, nonVoter] = await ethers.getSigners();

        const ZkBlindVoting = await ethers.getContractFactory("ZkBlindVoting");
        voting = await ZkBlindVoting.deploy();

        await voting.initialize(owner.address, initialOptions, revealDuration);
    }

    /** Helper: compute commit hash matching the contract's keccak256(abi.encodePacked(optionIndex, salt)) */
    function computeCommitHash(optionIndex: bigint | number, salt: string): string {
        return ethers.solidityPackedKeccak256(
            ["uint256", "bytes32"],
            [optionIndex, salt]
        );
    }

    /** Helper: generate a random salt */
    function randomSalt(): string {
        return ethers.hexlify(ethers.randomBytes(32));
    }

    beforeEach(async function () {
        await deployVoting();
    });

    // ── IZkPoll compliance ──────────────────────────────────────────

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

        it("verifyParticipation returns false for non-voter", async function () {
            const key = BigInt(voter1.address);
            expect(await voting.verifyParticipation(key)).to.equal(false);
        });
    });

    // ── Registration ────────────────────────────────────────────────

    describe("Registration", function () {
        it("Voter registers successfully", async function () {
            await expect(voting.connect(voter1).register())
                .to.emit(voting, "VoterRegistered")
                .withArgs(voter1.address);
            expect(await voting.getParticipantCount()).to.equal(1);
            expect(await voting.isRegistered(voter1.address)).to.equal(true);
        });

        it("Rejects double registration", async function () {
            await voting.connect(voter1).register();
            await expect(
                voting.connect(voter1).register()
            ).to.be.revertedWith("Already registered");
        });

        it("Rejects registration after voting starts", async function () {
            await voting.connect(voter1).register();
            await voting.startVoting();
            await expect(
                voting.connect(voter2).register()
            ).to.be.revertedWith("Not in registration phase");
        });

        it("Multiple voters can register", async function () {
            await voting.connect(voter1).register();
            await voting.connect(voter2).register();
            await voting.connect(voter3).register();
            expect(await voting.getParticipantCount()).to.equal(3);
        });
    });

    // ── Voting (commit) ─────────────────────────────────────────────

    describe("Voting (commit)", function () {
        let salt1: string;
        let commitHash1: string;

        beforeEach(async function () {
            await voting.connect(voter1).register();
            await voting.connect(voter2).register();
            salt1 = randomSalt();
            commitHash1 = computeCommitHash(0, salt1);
            await voting.startVoting();
        });

        it("Registered voter commits a vote", async function () {
            await expect(voting.connect(voter1).commitVote(commitHash1))
                .to.emit(voting, "VoteCommitted")
                .withArgs(voter1.address);

            expect(await voting.hasVoted(voter1.address)).to.equal(true);
        });

        it("Rejects commit from unregistered voter", async function () {
            const salt = randomSalt();
            const hash = computeCommitHash(0, salt);
            await expect(
                voting.connect(nonVoter).commitVote(hash)
            ).to.be.revertedWith("Not registered");
        });

        it("Rejects double commit", async function () {
            await voting.connect(voter1).commitVote(commitHash1);
            const salt2 = randomSalt();
            const hash2 = computeCommitHash(1, salt2);
            await expect(
                voting.connect(voter1).commitVote(hash2)
            ).to.be.revertedWith("Already committed");
        });

        it("Rejects commit in Registration phase", async function () {
            // Deploy a new instance that stays in Registration
            const ZkBlindVoting = await ethers.getContractFactory("ZkBlindVoting");
            const fresh = await ZkBlindVoting.deploy();
            await fresh.initialize(owner.address, ["A", "B"], REVEAL_DURATION);

            const salt = randomSalt();
            const hash = computeCommitHash(0, salt);
            await expect(
                fresh.connect(voter1).commitVote(hash)
            ).to.be.revertedWith("Not in voting phase");
        });

        it("Rejects commit in Ended phase", async function () {
            await voting.endVoting();
            const salt = randomSalt();
            const hash = computeCommitHash(0, salt);
            await expect(
                voting.connect(voter1).commitVote(hash)
            ).to.be.revertedWith("Not in voting phase");
        });

        it("Rejects empty commit hash", async function () {
            await expect(
                voting.connect(voter1).commitVote(ethers.ZeroHash)
            ).to.be.revertedWith("Empty commit hash");
        });

        it("verifyParticipation returns true after commit", async function () {
            await voting.connect(voter1).commitVote(commitHash1);
            const key = BigInt(voter1.address);
            expect(await voting.verifyParticipation(key)).to.equal(true);
        });
    });

    // ── State transitions ───────────────────────────────────────────

    describe("State transitions", function () {
        it("startVoting requires >= 2 options", async function () {
            const ZkBlindVoting = await ethers.getContractFactory("ZkBlindVoting");
            const sparse = await ZkBlindVoting.deploy();
            await sparse.initialize(owner.address, ["Only Option"], REVEAL_DURATION);
            // Need a voter
            await sparse.connect(voter1).register();
            await expect(sparse.startVoting()).to.be.revertedWith(
                "Need at least 2 options"
            );
        });

        it("startVoting requires >= 1 voter", async function () {
            await expect(voting.startVoting()).to.be.revertedWith(
                "Need at least 1 voter"
            );
        });

        it("startVoting emits StateChanged", async function () {
            await voting.connect(voter1).register();
            await expect(voting.startVoting())
                .to.emit(voting, "StateChanged")
                .withArgs(1); // PollState.Voting
        });

        it("endVoting sets revealDeadline", async function () {
            await voting.connect(voter1).register();
            await voting.startVoting();

            const tx = await voting.endVoting();
            const block = await ethers.provider.getBlock(tx.blockNumber);
            const expectedDeadline = block!.timestamp + REVEAL_DURATION;

            expect(await voting.getRevealDeadline()).to.equal(expectedDeadline);
        });

        it("endVoting emits StateChanged", async function () {
            await voting.connect(voter1).register();
            await voting.startVoting();
            await expect(voting.endVoting())
                .to.emit(voting, "StateChanged")
                .withArgs(2); // PollState.Ended
        });

        it("Cannot end voting from Registration phase", async function () {
            await expect(voting.endVoting()).to.be.revertedWith(
                "Not in voting phase"
            );
        });

        it("Only owner can startVoting", async function () {
            await voting.connect(voter1).register();
            await expect(
                voting.connect(voter1).startVoting()
            ).to.be.revertedWith("Not owner");
        });

        it("Only owner can endVoting", async function () {
            await voting.connect(voter1).register();
            await voting.startVoting();
            await expect(
                voting.connect(voter1).endVoting()
            ).to.be.revertedWith("Not owner");
        });

        it("Prevents double initialization", async function () {
            await expect(
                voting.initialize(owner.address, ["X", "Y"], 100)
            ).to.be.revertedWith("Already initialized");
        });
    });

    // ── Reveal ──────────────────────────────────────────────────────

    describe("Reveal", function () {
        let salt1: string;
        let salt2: string;

        beforeEach(async function () {
            // Register voters
            await voting.connect(voter1).register();
            await voting.connect(voter2).register();

            // Start voting
            await voting.startVoting();

            // Voters commit
            salt1 = randomSalt();
            salt2 = randomSalt();
            const hash1 = computeCommitHash(0, salt1); // voter1 votes for option 0
            const hash2 = computeCommitHash(1, salt2); // voter2 votes for option 1
            await voting.connect(voter1).commitVote(hash1);
            await voting.connect(voter2).commitVote(hash2);

            // End voting (starts reveal window)
            await voting.endVoting();
        });

        it("Reveal with correct hash succeeds", async function () {
            await expect(voting.connect(voter1).revealVote(0, salt1))
                .to.emit(voting, "VoteRevealed")
                .withArgs(voter1.address, 0);

            expect(await voting.hasRevealed(voter1.address)).to.equal(true);

            const results = await voting.getResults();
            expect(results[0]).to.equal(1n);
        });

        it("Reveal with wrong salt reverts", async function () {
            const wrongSalt = randomSalt();
            await expect(
                voting.connect(voter1).revealVote(0, wrongSalt)
            ).to.be.revertedWith("Hash mismatch");
        });

        it("Reveal with wrong option index reverts", async function () {
            await expect(
                voting.connect(voter1).revealVote(1, salt1)
            ).to.be.revertedWith("Hash mismatch");
        });

        it("Reveal after deadline reverts", async function () {
            await time.increase(REVEAL_DURATION + 1);
            await expect(
                voting.connect(voter1).revealVote(0, salt1)
            ).to.be.revertedWith("Reveal deadline passed");
        });

        it("Double reveal reverts", async function () {
            await voting.connect(voter1).revealVote(0, salt1);
            await expect(
                voting.connect(voter1).revealVote(0, salt1)
            ).to.be.revertedWith("Already revealed");
        });

        it("Reveal with invalid option index reverts", async function () {
            // Commit a hash for an out-of-range option
            // We'll test with a voter who hasn't committed for a valid index
            // Actually, voter1 committed for index 0, so trying index 99 gives hash mismatch
            await expect(
                voting.connect(voter1).revealVote(99, salt1)
            ).to.be.revertedWith("Invalid option index");
        });

        it("Reveal by non-committer reverts", async function () {
            await expect(
                voting.connect(nonVoter).revealVote(0, salt1)
            ).to.be.revertedWith("No commit found");
        });

        it("Reveal during Voting phase reverts", async function () {
            // Deploy fresh instance, keep in Voting
            const ZkBlindVoting = await ethers.getContractFactory("ZkBlindVoting");
            const fresh = await ZkBlindVoting.deploy();
            await fresh.initialize(owner.address, ["A", "B"], REVEAL_DURATION);
            await fresh.connect(voter1).register();
            await fresh.startVoting();
            const salt = randomSalt();
            const hash = computeCommitHash(0, salt);
            await fresh.connect(voter1).commitVote(hash);

            await expect(
                fresh.connect(voter1).revealVote(0, salt)
            ).to.be.revertedWith("Not in ended phase");
        });
    });

    // ── Finalize ────────────────────────────────────────────────────

    describe("Finalize", function () {
        let salt1: string;
        let salt2: string;

        beforeEach(async function () {
            await voting.connect(voter1).register();
            await voting.connect(voter2).register();
            await voting.connect(voter3).register();

            await voting.startVoting();

            salt1 = randomSalt();
            salt2 = randomSalt();
            const salt3 = randomSalt();
            const hash1 = computeCommitHash(0, salt1);
            const hash2 = computeCommitHash(0, salt2);
            const hash3 = computeCommitHash(2, salt3);
            await voting.connect(voter1).commitVote(hash1);
            await voting.connect(voter2).commitVote(hash2);
            await voting.connect(voter3).commitVote(hash3);

            await voting.endVoting();
        });

        it("Owner finalizes after deadline", async function () {
            // Reveal some votes
            await voting.connect(voter1).revealVote(0, salt1);
            await voting.connect(voter2).revealVote(0, salt2);
            // voter3 does NOT reveal

            // Advance past deadline
            await time.increase(REVEAL_DURATION + 1);

            await expect(voting.finalizeResults())
                .to.emit(voting, "ResultsFinalized");

            expect(await voting.isFinalized()).to.equal(true);
        });

        it("Cannot finalize before deadline", async function () {
            await expect(voting.finalizeResults()).to.be.revertedWith(
                "Reveal deadline not passed"
            );
        });

        it("Cannot finalize twice", async function () {
            await time.increase(REVEAL_DURATION + 1);
            await voting.finalizeResults();
            await expect(voting.finalizeResults()).to.be.revertedWith(
                "Already finalized"
            );
        });

        it("Only owner can finalize", async function () {
            await time.increase(REVEAL_DURATION + 1);
            await expect(
                voting.connect(voter1).finalizeResults()
            ).to.be.revertedWith("Not owner");
        });

        it("Results match revealed votes, unrevealed excluded", async function () {
            // voter1 and voter2 both voted for option 0
            await voting.connect(voter1).revealVote(0, salt1);
            await voting.connect(voter2).revealVote(0, salt2);
            // voter3 committed for option 2 but does NOT reveal

            await time.increase(REVEAL_DURATION + 1);
            await voting.finalizeResults();

            const results = await voting.getResults();
            expect(results[0]).to.equal(2n); // Option A: 2 votes
            expect(results[1]).to.equal(0n); // Option B: 0 votes
            expect(results[2]).to.equal(0n); // Option C: 0 votes (voter3 didn't reveal)
        });

        it("Cannot reveal after finalization", async function () {
            await time.increase(REVEAL_DURATION + 1);
            await voting.finalizeResults();

            // Even though voter1 hasn't revealed, finalization blocks it
            await expect(
                voting.connect(voter1).revealVote(0, salt1)
            ).to.be.revertedWith("Reveal deadline passed");
        });
    });

    // ── Full flow ───────────────────────────────────────────────────

    describe("Full flow: 3 voters, 2 reveal, finalize", function () {
        it("End-to-end commit-reveal blind voting", async function () {
            // 1. Registration
            await voting.connect(voter1).register();
            await voting.connect(voter2).register();
            await voting.connect(voter3).register();
            expect(await voting.getParticipantCount()).to.equal(3);

            // 2. Start voting
            await voting.startVoting();
            expect(await voting.getState()).to.equal(1); // Voting

            // 3. All 3 voters commit
            const salt1 = randomSalt();
            const salt2 = randomSalt();
            const salt3 = randomSalt();

            // voter1 → Option A (0), voter2 → Option B (1), voter3 → Option A (0)
            const hash1 = computeCommitHash(0, salt1);
            const hash2 = computeCommitHash(1, salt2);
            const hash3 = computeCommitHash(0, salt3);

            await voting.connect(voter1).commitVote(hash1);
            await voting.connect(voter2).commitVote(hash2);
            await voting.connect(voter3).commitVote(hash3);

            // Results should be all zeros (nothing revealed yet)
            let results = await voting.getResults();
            expect(results[0]).to.equal(0n);
            expect(results[1]).to.equal(0n);
            expect(results[2]).to.equal(0n);

            // 4. End voting
            await voting.endVoting();
            expect(await voting.getState()).to.equal(2); // Ended

            // 5. voter1 and voter2 reveal; voter3 does NOT
            await voting.connect(voter1).revealVote(0, salt1);
            await voting.connect(voter2).revealVote(1, salt2);

            // Results reflect only revealed votes
            results = await voting.getResults();
            expect(results[0]).to.equal(1n); // Option A: 1 (voter1)
            expect(results[1]).to.equal(1n); // Option B: 1 (voter2)
            expect(results[2]).to.equal(0n); // Option C: 0

            // 6. Advance past reveal deadline and finalize
            await time.increase(REVEAL_DURATION + 1);
            await voting.finalizeResults();

            expect(await voting.isFinalized()).to.equal(true);

            // Final results: voter3's unrevealed vote is excluded
            results = await voting.getResults();
            expect(results[0]).to.equal(1n); // Option A: 1
            expect(results[1]).to.equal(1n); // Option B: 1
            expect(results[2]).to.equal(0n); // Option C: 0
        });
    });

    // ── Admin controls ──────────────────────────────────────────────

    describe("Admin controls", function () {
        it("Owner can add option during registration", async function () {
            await voting.addOption("Option D");
            const opts = await voting.getOptions();
            expect(opts.length).to.equal(4);
            expect(opts[3]).to.equal("Option D");
        });

        it("Cannot add option after registration phase", async function () {
            await voting.connect(voter1).register();
            await voting.startVoting();
            await expect(voting.addOption("Late Option")).to.be.revertedWith(
                "Not in registration phase"
            );
        });

        it("Non-owner cannot add option", async function () {
            await expect(
                voting.connect(nonVoter).addOption("Unauthorized")
            ).to.be.revertedWith("Not owner");
        });

        it("getOptionCount returns correct count", async function () {
            expect(await voting.getOptionCount()).to.equal(3);
            await voting.addOption("Option D");
            expect(await voting.getOptionCount()).to.equal(4);
        });

        it("getVoters returns registered voters", async function () {
            await voting.connect(voter1).register();
            await voting.connect(voter2).register();
            const voterList = await voting.getVoters();
            expect(voterList.length).to.equal(2);
            expect(voterList[0]).to.equal(voter1.address);
            expect(voterList[1]).to.equal(voter2.address);
        });
    });
});
