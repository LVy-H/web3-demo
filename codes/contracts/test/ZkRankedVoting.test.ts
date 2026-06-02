import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import * as crypto from "crypto";

// Canonical module string (see docs/superpowers/specs/2026-06-02-ranked-choice-design.md).
// Used IDENTICALLY here, in scripts/deploy.ts, and in the relayer — we do NOT
// repeat M1's anon-vote/zk-anon-voting inconsistency.
const MODULE = "ranked-vote";

/** Pack a ranking (array of OPTION INDICES, most-preferred first) into the
 *  4-bit-per-slot packed value. Slot value = optionIndex + 1; slot 0 is the LSB
 *  nibble. e.g. pack([1, 0, 2]) ranks option1 > option0 > option2. */
function pack(optionIndices: number[]): bigint {
    let v = 0n;
    optionIndices.forEach((idx, slot) => {
        v |= BigInt(idx + 1) << BigInt(4 * slot);
    });
    return v;
}

describe("ZkRankedVoting", function () {
    let semaphore: any;
    let voting: any;
    let owner: any;
    let nonOwner: any;
    let tokens: string[] = [];
    let commitments: bigint[] = [];

    /** Helper: deploy a fresh ZkRankedVoting clone via PollRegistry. The bare
     *  implementation has _disableInitializers() so it can never be initialized
     *  directly — only clones produced by the registry are usable. */
    async function deployRankedVotingClone(initialOptions: string[]): Promise<any> {
        const ZkRankedVoting = await ethers.getContractFactory("ZkRankedVoting");
        const impl = await ZkRankedVoting.deploy();

        const PollRegistry = await ethers.getContractFactory("PollRegistry");
        const registry = await PollRegistry.deploy();

        await registry.registerModule(MODULE, await impl.getAddress());

        const initData = impl.interface.encodeFunctionData("initialize", [
            await semaphore.getAddress(),
            owner.address,
            initialOptions,
        ]);

        await registry.createPoll(MODULE, "Test", "Test ranked poll", initData);

        const cloneAddress = (await registry.getAllPolls())[0].pollAddress;
        return ethers.getContractAt("ZkRankedVoting", cloneAddress);
    }

    /** Like deployRankedVotingClone but returns the registry so the caller can
     *  assert on createPoll itself (e.g. the >8-options revert). */
    async function deployRegistryAndImpl(): Promise<{ registry: any; impl: any }> {
        const ZkRankedVoting = await ethers.getContractFactory("ZkRankedVoting");
        const impl = await ZkRankedVoting.deploy();
        const PollRegistry = await ethers.getContractFactory("PollRegistry");
        const registry = await PollRegistry.deploy();
        await registry.registerModule(MODULE, await impl.getAddress());
        return { registry, impl };
    }

    /** Helper: deploy Semaphore stack + default ZkRankedVoting clone for beforeEach */
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

        voting = await deployRankedVotingClone(initialOptions);

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

    /** Build a mock Semaphore proof for the given packed ranking. With
     *  MockSemaphoreVerifier the points/root are not checked — see HONESTY BAR. */
    function mockProof(opts: { ranking: bigint; nullifier: bigint; root: any; scope: bigint; message?: bigint }) {
        return {
            merkleTreeDepth: 1,
            merkleTreeRoot: opts.root,
            nullifier: opts.nullifier,
            message: opts.message ?? opts.ranking,
            scope: opts.scope,
            points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
        };
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

        it("exposes MAX_OPTIONS = 8", async function () {
            expect(await voting.MAX_OPTIONS()).to.equal(8n);
        });
    });

    // ── initialize option cap ─────────────────────────────────────────

    describe("Initialize option cap", function () {
        it("Allows exactly MAX_OPTIONS (8) options", async function () {
            const opts = Array.from({ length: 8 }, (_, i) => `Opt ${i}`);
            const poll = await deployRankedVotingClone(opts);
            expect((await poll.getOptions()).length).to.equal(8);
        });

        it("Rejects >8 options (surfaces as PollRegistry.InitFailed)", async function () {
            // PollRegistry.createPoll does `(bool ok,) = clone.call(initData); if(!ok) revert InitFailed();`
            // — it does NOT bubble the inner TooManyOptions revert, so the clone
            // path surfaces the registry's InitFailed. (The bare impl can't be
            // tested directly: _disableInitializers() makes it revert
            // InvalidInitialization first.) The behavioral guarantee — a >8-option
            // poll cannot be created — is what we assert here.
            const { registry, impl } = await deployRegistryAndImpl();
            const opts = Array.from({ length: 9 }, (_, i) => `Opt ${i}`);
            const initData = impl.interface.encodeFunctionData("initialize", [
                await semaphore.getAddress(),
                owner.address,
                opts,
            ]);
            await expect(
                registry.createPoll(MODULE, "Too many", "9 options", initData)
            ).to.be.revertedWithCustomError(registry, "InitFailed");
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
            await expect(voting.connect(nonOwner).registerVoter(commitments[0]))
                .to.be.revertedWithCustomError(voting, "OwnableUnauthorizedAccount")
                .withArgs(nonOwner.address);
        });

        it("Duplicate commitment rejected", async function () {
            await voting.registerVoter(commitments[0]);
            await expect(
                voting.registerVoter(commitments[0])
            ).to.be.revertedWithCustomError(voting, "AlreadyRegistered");
        });
    });

    // ── Voting (ranked ballots) ───────────────────────────────────────

    describe("Voting", function () {
        let group: any;
        let scope: bigint;

        beforeEach(async function () {
            await voting.registerVoters(commitments);
            group = new Group();
            commitments.forEach((c) => group.addMember(c));
            await voting.startVoting();
            scope = BigInt(await voting.getAddress());
        });

        it("Valid FULL ranking (A > B > C): first-pref tally counts only A", async function () {
            const ranking = pack([0, 1, 2]); // A > B > C  → 0x321
            await expect(voting.castVote(ranking, mockProof({ ranking, nullifier: 1n, root: group.root, scope })))
                .to.emit(voting, "VoteCast")
                .withArgs(ranking);
            // First preference only: A gets the vote, B and C do NOT.
            expect(await voting.getResults()).to.deep.equal([1n, 0n, 0n]);
        });

        it("Valid PARTIAL (prefix) ranking (B only): first-pref tally counts only B", async function () {
            const ranking = pack([1]); // rank only B (option index 1) → 0x2
            await voting.castVote(ranking, mockProof({ ranking, nullifier: 2n, root: group.root, scope }));
            expect(await voting.getResults()).to.deep.equal([0n, 1n, 0n]);
        });

        it("Lower ranks are NOT counted: a [B > A > C] ballot increments ONLY B", async function () {
            // This is THE semantic that distinguishes ranked from approval. A bug
            // that tallied every ranked option (approval-style) would make this fail.
            const ranking = pack([1, 0, 2]); // B > A > C
            await voting.castVote(ranking, mockProof({ ranking, nullifier: 3n, root: group.root, scope }));
            const results = await voting.getResults();
            expect(results).to.deep.equal([0n, 1n, 0n]); // only B, not A or C
            const sum = results.reduce((a: bigint, b: bigint) => a + b, 0n);
            expect(sum).to.equal(1n); // exactly one increment per ballot
        });

        it("First-pref tally across several ballots is correct", async function () {
            await voting.castVote(pack([0, 1]), mockProof({ ranking: pack([0, 1]), nullifier: 11n, root: group.root, scope })); // A first
            await voting.castVote(pack([2, 0]), mockProof({ ranking: pack([2, 0]), nullifier: 12n, root: group.root, scope })); // C first
            await voting.castVote(pack([0, 2, 1]), mockProof({ ranking: pack([0, 2, 1]), nullifier: 13n, root: group.root, scope })); // A first
            // First preferences: A,A,C → A=2, B=0, C=1.
            expect(await voting.getResults()).to.deep.equal([2n, 0n, 1n]);
        });

        it("VoteCast emits the EXACT packedRanking (off-chain IRV depends on it)", async function () {
            // The full ballot — not just the first pref — must be readable on-chain.
            const ranking = pack([2, 0, 1]); // C > A > B  → 0x132
            const tx = await voting.castVote(ranking, mockProof({ ranking, nullifier: 21n, root: group.root, scope }));
            const receipt = await tx.wait();
            const parsed = receipt.logs
                .map((l: any) => {
                    try {
                        return voting.interface.parseLog(l);
                    } catch {
                        return null;
                    }
                })
                .filter((p: any) => p && p.name === "VoteCast");
            expect(parsed.length).to.equal(1);
            expect(parsed[0].args[0]).to.equal(ranking); // exact packed value emitted
        });

        it("Empty ballot (0) reverts EmptyBallot, then the SAME voter retries and SUCCEEDS (no lockout)", async function () {
            const nullifier = 42n;
            await expect(
                voting.castVote(0n, mockProof({ ranking: 0n, nullifier, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "EmptyBallot");

            // Nullifier must NOT have been consumed by the rejected ballot.
            expect(await voting.verifyParticipation(nullifier)).to.equal(false);

            const ranking = pack([1]); // B
            await expect(voting.castVote(ranking, mockProof({ ranking, nullifier, root: group.root, scope })))
                .to.emit(voting, "VoteCast")
                .withArgs(ranking);
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
            expect((await voting.getResults())[1]).to.equal(1n);
        });

        it("Duplicate option in ranking reverts InvalidBallot", async function () {
            // A > A : slot0 = 1 (A), slot1 = 1 (A again) → 0x11
            const dup = (1n << 0n) | (1n << 4n);
            await expect(
                voting.castVote(dup, mockProof({ ranking: dup, nullifier: 31n, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "InvalidBallot");
        });

        it("Out-of-range option (> option count) reverts InvalidBallot", async function () {
            // options.length == 3 → valid slot values are [1, 3]. Slot value 4
            // (= option index 3) has no option.
            const oob = 4n; // slot0 = 4
            await expect(
                voting.castVote(oob, mockProof({ ranking: oob, nullifier: 32n, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "InvalidBallot");
        });

        it("Gap (empty slot then a nonzero higher slot) reverts InvalidBallot", async function () {
            // slot0 = 1 (A), slot1 = 0 (empty), slot2 = 2 (B) → 0x201. The empty
            // slot1 must mean the ballot ended; a later nonzero slot is a gap.
            const gap = (1n << 0n) | (2n << 8n);
            await expect(
                voting.castVote(gap, mockProof({ ranking: gap, nullifier: 33n, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "InvalidBallot");
        });

        it("Bits above bit 32 reverts InvalidBallot (high-bits guard, not caught by the slot loop)", async function () {
            // A well-formed low-32 prefix (slot0 = A) plus a bit at position 32.
            // The slot loop only inspects bits 0..31, so this MUST be rejected by
            // the explicit `packedRanking < (1 << 32)` guard.
            const highBits = (1n << 0n) | (1n << 32n);
            await expect(
                voting.castVote(highBits, mockProof({ ranking: highBits, nullifier: 34n, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "InvalidBallot");
        });

        it("Double-vote with the same nullifier reverts (AlreadyVoted)", async function () {
            const nullifier = 99n;
            await voting.castVote(pack([0]), mockProof({ ranking: pack([0]), nullifier, root: group.root, scope }));
            await expect(
                voting.castVote(pack([1]), mockProof({ ranking: pack([1]), nullifier, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "AlreadyVoted");
        });

        it("proof.message != packedRanking reverts (TamperedVoteSignal), then valid retry succeeds (no lockout)", async function () {
            const nullifier = 55n;
            const ranking = pack([0, 2]); // A > C
            // proof.message is a DIFFERENT well-formed ranking ⇒ TamperedVoteSignal,
            // which fires BEFORE isNullifierUsed is set ⇒ no lockout.
            await expect(
                voting.castVote(
                    ranking,
                    mockProof({ ranking, nullifier, root: group.root, scope, message: pack([1]) })
                )
            ).to.be.revertedWithCustomError(voting, "TamperedVoteSignal");
            expect(await voting.verifyParticipation(nullifier)).to.equal(false);

            // Same nullifier retries with a matching message ⇒ succeeds.
            await voting.castVote(ranking, mockProof({ ranking, nullifier, root: group.root, scope }));
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
            expect(await voting.getResults()).to.deep.equal([1n, 0n, 0n]); // first pref A
        });

        it("Wrong scope reverts (InvalidScope), then valid retry succeeds (no lockout)", async function () {
            const nullifier = 66n;
            const ranking = pack([0]);
            await expect(
                voting.castVote(ranking, mockProof({ ranking, nullifier, root: group.root, scope: 12345n }))
            ).to.be.revertedWithCustomError(voting, "InvalidScope");
            expect(await voting.verifyParticipation(nullifier)).to.equal(false);

            await voting.castVote(ranking, mockProof({ ranking, nullifier, root: group.root, scope }));
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
        });

        it("Cannot vote in Registration phase (NotInVoting)", async function () {
            const fresh = await deployRankedVotingClone(["A", "B"]);
            await expect(
                fresh.castVote(1n, mockProof({ ranking: 1n, nullifier: 1n, root: 0n, scope: BigInt(await fresh.getAddress()) }))
            ).to.be.revertedWithCustomError(fresh, "NotInVoting");
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
            await voting.castVote(pack([0]), mockProof({ ranking: pack([0]), nullifier, root: group.root, scope }));
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
        });

        it("Returns false for unused nullifier", async function () {
            expect(await voting.verifyParticipation(999n)).to.equal(false);
        });
    });

    // ── State transitions ────────────────────────────────────────────

    describe("State transitions", function () {
        it("Requires at least 2 options to start voting", async function () {
            const sparse = await deployRankedVotingClone(["Only Option"]);
            await expect(sparse.startVoting()).to.be.revertedWithCustomError(
                sparse,
                "NeedAtLeastTwoOptions"
            );
        });

        it("Requires at least 1 voter to start voting", async function () {
            await expect(voting.startVoting()).to.be.revertedWithCustomError(
                voting,
                "NeedAtLeastOneVoter"
            );
        });

        it("startVoting emits StateChanged", async function () {
            await voting.registerVoter(commitments[0]);
            await expect(voting.startVoting())
                .to.emit(voting, "StateChanged")
                .withArgs(1); // PollState.Voting
        });

        it("endVoting emits StateChanged", async function () {
            await voting.registerVoter(commitments[0]);
            await voting.startVoting();
            await expect(voting.endVoting())
                .to.emit(voting, "StateChanged")
                .withArgs(2); // PollState.Ended
        });

        it("Cannot end voting from Registration phase", async function () {
            await expect(voting.endVoting()).to.be.revertedWithCustomError(
                voting,
                "NotInVoting"
            );
        });

        it("Prevents double initialization", async function () {
            await expect(
                voting.initialize(await semaphore.getAddress(), owner.address, ["X", "Y"])
            ).to.be.revertedWithCustomError(voting, "InvalidInitialization");
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
            await voting.registerVoter(commitments[0]);
            await voting.startVoting();
            await expect(
                voting.addOption("Late Option")
            ).to.be.revertedWithCustomError(voting, "NotInRegistration");
        });

        it("Cannot exceed MAX_OPTIONS via addOption", async function () {
            const poll = await deployRankedVotingClone(Array.from({ length: 8 }, (_, i) => `Opt ${i}`));
            await expect(poll.addOption("9th")).to.be.revertedWithCustomError(poll, "TooManyOptions");
        });

        it("Non-owner cannot add option", async function () {
            await expect(voting.connect(nonOwner).addOption("Unauthorized"))
                .to.be.revertedWithCustomError(voting, "OwnableUnauthorizedAccount")
                .withArgs(nonOwner.address);
        });
    });
});
