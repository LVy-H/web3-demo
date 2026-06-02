import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import * as crypto from "crypto";

// Canonical module string (see docs/superpowers/specs/2026-06-02-approval-voting-design.md).
// Used IDENTICALLY here, in scripts/deploy.ts, and in the relayer — we do NOT
// repeat M1's anon-vote/zk-anon-voting inconsistency.
const MODULE = "approval-vote";

describe("ZkApprovalVoting", function () {
    let semaphore: any;
    let voting: any;
    let owner: any;
    let nonOwner: any;
    let tokens: string[] = [];
    let commitments: bigint[] = [];

    /** Helper: deploy a fresh ZkApprovalVoting clone via PollRegistry. The bare
     *  implementation has _disableInitializers() so it can never be initialized
     *  directly — only clones produced by the registry are usable. */
    async function deployApprovalVotingClone(initialOptions: string[]): Promise<any> {
        const ZkApprovalVoting = await ethers.getContractFactory("ZkApprovalVoting");
        const impl = await ZkApprovalVoting.deploy();

        const PollRegistry = await ethers.getContractFactory("PollRegistry");
        const registry = await PollRegistry.deploy();

        await registry.registerModule(MODULE, await impl.getAddress());

        const initData = impl.interface.encodeFunctionData("initialize", [
            await semaphore.getAddress(),
            owner.address,
            initialOptions,
        ]);

        await registry.createPoll(MODULE, "Test", "Test approval poll", initData);

        const cloneAddress = (await registry.getAllPolls())[0].pollAddress;
        return ethers.getContractAt("ZkApprovalVoting", cloneAddress);
    }

    /** Like deployApprovalVotingClone but returns the registry so the caller can
     *  assert on createPoll itself (e.g. the >32-options revert). */
    async function deployRegistryAndImpl(): Promise<{ registry: any; impl: any }> {
        const ZkApprovalVoting = await ethers.getContractFactory("ZkApprovalVoting");
        const impl = await ZkApprovalVoting.deploy();
        const PollRegistry = await ethers.getContractFactory("PollRegistry");
        const registry = await PollRegistry.deploy();
        await registry.registerModule(MODULE, await impl.getAddress());
        return { registry, impl };
    }

    /** Helper: deploy Semaphore stack + default ZkApprovalVoting clone for beforeEach */
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

        voting = await deployApprovalVotingClone(initialOptions);

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

    /** Build a mock Semaphore proof for the given bitmask. With
     *  MockSemaphoreVerifier the points/root are not checked — see HONESTY BAR. */
    function mockProof(opts: { bitmask: bigint; nullifier: bigint; root: any; scope: bigint; message?: bigint }) {
        return {
            merkleTreeDepth: 1,
            merkleTreeRoot: opts.root,
            nullifier: opts.nullifier,
            message: opts.message ?? opts.bitmask,
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

        it("exposes MAX_OPTIONS = 32", async function () {
            expect(await voting.MAX_OPTIONS()).to.equal(32n);
        });
    });

    // ── initialize option cap ─────────────────────────────────────────

    describe("Initialize option cap", function () {
        it("Allows exactly MAX_OPTIONS (32) options", async function () {
            const opts = Array.from({ length: 32 }, (_, i) => `Opt ${i}`);
            const poll = await deployApprovalVotingClone(opts);
            expect((await poll.getOptions()).length).to.equal(32);
        });

        it("Rejects >32 options (surfaces as PollRegistry.InitFailed)", async function () {
            // PollRegistry.createPoll does `(bool ok,) = clone.call(initData); if(!ok) revert InitFailed();`
            // — it does NOT bubble the inner TooManyOptions revert, so the clone
            // path surfaces the registry's InitFailed. (The bare impl can't be
            // tested directly: _disableInitializers() makes it revert
            // InvalidInitialization first.) The behavioral guarantee — a >32-option
            // poll cannot be created — is what we assert here.
            const { registry, impl } = await deployRegistryAndImpl();
            const opts = Array.from({ length: 33 }, (_, i) => `Opt ${i}`);
            const initData = impl.interface.encodeFunctionData("initialize", [
                await semaphore.getAddress(),
                owner.address,
                opts,
            ]);
            await expect(
                registry.createPoll(MODULE, "Too many", "33 options", initData)
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

    // ── Voting (approval ballots) ─────────────────────────────────────

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

        it("Approve a single option (bitmask 0b001 = A)", async function () {
            const bitmask = 0b001n;
            await expect(voting.castVote(bitmask, mockProof({ bitmask, nullifier: 1n, root: group.root, scope })))
                .to.emit(voting, "VoteCast")
                .withArgs(bitmask);
            const results = await voting.getResults();
            expect(results).to.deep.equal([1n, 0n, 0n]);
        });

        it("Approve a subset (bitmask 0b101 = A and C)", async function () {
            const bitmask = 0b101n;
            await voting.castVote(bitmask, mockProof({ bitmask, nullifier: 2n, root: group.root, scope }));
            const results = await voting.getResults();
            expect(results).to.deep.equal([1n, 0n, 1n]);
        });

        it("Approve all options (bitmask 0b111)", async function () {
            const bitmask = 0b111n;
            await voting.castVote(bitmask, mockProof({ bitmask, nullifier: 3n, root: group.root, scope }));
            const results = await voting.getResults();
            expect(results).to.deep.equal([1n, 1n, 1n]);
        });

        it("Empty ballot (0) reverts, then the SAME voter retries with a valid ballot and SUCCEEDS (no lockout)", async function () {
            const nullifier = 42n;
            await expect(
                voting.castVote(0n, mockProof({ bitmask: 0n, nullifier, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "EmptyBallot");

            // Nullifier must NOT have been consumed by the rejected ballot.
            expect(await voting.verifyParticipation(nullifier)).to.equal(false);

            const bitmask = 0b010n;
            await expect(voting.castVote(bitmask, mockProof({ bitmask, nullifier, root: group.root, scope })))
                .to.emit(voting, "VoteCast")
                .withArgs(bitmask);
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
            expect((await voting.getResults())[1]).to.equal(1n);
        });

        it("Out-of-range bit reverts, then valid retry succeeds (no lockout)", async function () {
            const nullifier = 77n;
            // options.length == 3 → valid range is [1, 8). 0b1000 (=8) sets bit 3
            // which has no option.
            const bad = 0b1000n;
            await expect(
                voting.castVote(bad, mockProof({ bitmask: bad, nullifier, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "InvalidBallot");
            expect(await voting.verifyParticipation(nullifier)).to.equal(false);

            const bitmask = 0b011n;
            await voting.castVote(bitmask, mockProof({ bitmask, nullifier, root: group.root, scope }));
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
            expect(await voting.getResults()).to.deep.equal([1n, 1n, 0n]);
        });

        it("Double-vote with the same nullifier reverts (AlreadyVoted)", async function () {
            const nullifier = 99n;
            await voting.castVote(0b001n, mockProof({ bitmask: 0b001n, nullifier, root: group.root, scope }));
            await expect(
                voting.castVote(0b010n, mockProof({ bitmask: 0b010n, nullifier, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "AlreadyVoted");
        });

        it("proof.message != bitmask reverts (TamperedVoteSignal)", async function () {
            const bitmask = 0b101n;
            await expect(
                voting.castVote(
                    bitmask,
                    mockProof({ bitmask, nullifier: 5n, root: group.root, scope, message: 0b011n })
                )
            ).to.be.revertedWithCustomError(voting, "TamperedVoteSignal");
        });

        it("Wrong scope reverts (InvalidScope)", async function () {
            const bitmask = 0b001n;
            await expect(
                voting.castVote(bitmask, mockProof({ bitmask, nullifier: 6n, root: group.root, scope: 12345n }))
            ).to.be.revertedWithCustomError(voting, "InvalidScope");
        });

        it("Cannot vote in Registration phase (NotInVoting)", async function () {
            const fresh = await deployApprovalVotingClone(["A", "B"]);
            await expect(
                fresh.castVote(0b01n, mockProof({ bitmask: 0b01n, nullifier: 1n, root: 0n, scope: BigInt(await fresh.getAddress()) }))
            ).to.be.revertedWithCustomError(fresh, "NotInVoting");
        });

        it("getResults: per-option approval sum can EXCEED the voter count", async function () {
            // 3 registered voters. Each approves multiple options.
            await voting.castVote(0b111n, mockProof({ bitmask: 0b111n, nullifier: 201n, root: group.root, scope })); // all
            await voting.castVote(0b101n, mockProof({ bitmask: 0b101n, nullifier: 202n, root: group.root, scope })); // A, C
            await voting.castVote(0b010n, mockProof({ bitmask: 0b010n, nullifier: 203n, root: group.root, scope })); // B

            const results = await voting.getResults();
            // A: voters 1,2 → 2 ; B: voters 1,3 → 2 ; C: voters 1,2 → 2
            expect(results).to.deep.equal([2n, 2n, 2n]);

            const sum = results.reduce((a: bigint, b: bigint) => a + b, 0n);
            const voterCount = await voting.getParticipantCount();
            expect(sum).to.equal(6n);
            expect(sum).to.be.greaterThan(voterCount); // 6 approvals across 3 voters
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
            await voting.castVote(0b001n, mockProof({ bitmask: 0b001n, nullifier, root: group.root, scope }));
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
        });

        it("Returns false for unused nullifier", async function () {
            expect(await voting.verifyParticipation(999n)).to.equal(false);
        });
    });

    // ── State transitions ────────────────────────────────────────────

    describe("State transitions", function () {
        it("Requires at least 2 options to start voting", async function () {
            const sparse = await deployApprovalVotingClone(["Only Option"]);
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

        it("Non-owner cannot add option", async function () {
            await expect(voting.connect(nonOwner).addOption("Unauthorized"))
                .to.be.revertedWithCustomError(voting, "OwnableUnauthorizedAccount")
                .withArgs(nonOwner.address);
        });
    });
});
