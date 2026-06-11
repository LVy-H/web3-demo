import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import * as crypto from "crypto";

// Canonical module string (see docs/superpowers/specs/2026-06-03-quadratic-voting-design.md).
// Used IDENTICALLY here, in scripts/deploy.ts, and in the relayer — we do NOT
// repeat M1's anon-vote/zk-anon-voting inconsistency.
const MODULE = "quadratic-vote";

/** Pack an allocation (array of vote counts, slot 0 = option 0) into the
 *  4-bit-per-slot packed value. votes[i] = number of votes for option i (cost
 *  votes[i]²); slot 0 is the LSB nibble. e.g. pack([10]) spends 10 votes on
 *  option 0 (cost 100); pack([6, 8]) spends 6 on opt0 and 8 on opt1 (cost 100). */
function pack(votes: number[]): bigint {
    let v = 0n;
    votes.forEach((n, slot) => {
        v |= BigInt(n) << BigInt(4 * slot);
    });
    return v;
}

describe("ZkQuadraticVoting", function () {
    let semaphore: any;
    let voting: any;
    let owner: any;
    let nonOwner: any;
    let tokens: string[] = [];
    let commitments: bigint[] = [];

    /** Helper: deploy a fresh ZkQuadraticVoting clone via PollRegistry. The bare
     *  implementation has _disableInitializers() so it can never be initialized
     *  directly — only clones produced by the registry are usable. */
    async function deployQuadraticVotingClone(initialOptions: string[]): Promise<any> {
        const ZkQuadraticVoting = await ethers.getContractFactory("ZkQuadraticVoting");
        const impl = await ZkQuadraticVoting.deploy();

        const PollRegistry = await ethers.getContractFactory("PollRegistry");
        const registry = await PollRegistry.deploy();

        await registry.registerModule(MODULE, await impl.getAddress());

        const initData = impl.interface.encodeFunctionData("initialize", [
            await semaphore.getAddress(),
            owner.address,
            initialOptions,
            0, // resultsPolicy: sealed-until-close (default)
        ]);

        await registry.createPoll(MODULE, "Test", "Test quadratic poll", initData);

        const cloneAddress = (await registry.getAllPolls())[0].pollAddress;
        return ethers.getContractAt("ZkQuadraticVoting", cloneAddress);
    }

    /** Like deployQuadraticVotingClone but returns the registry so the caller can
     *  assert on createPoll itself (e.g. the >8-options revert). */
    async function deployRegistryAndImpl(): Promise<{ registry: any; impl: any }> {
        const ZkQuadraticVoting = await ethers.getContractFactory("ZkQuadraticVoting");
        const impl = await ZkQuadraticVoting.deploy();
        const PollRegistry = await ethers.getContractFactory("PollRegistry");
        const registry = await PollRegistry.deploy();
        await registry.registerModule(MODULE, await impl.getAddress());
        return { registry, impl };
    }

    /** Helper: deploy Semaphore stack + default ZkQuadraticVoting clone for beforeEach */
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

        voting = await deployQuadraticVotingClone(initialOptions);

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

    /** Build a mock Semaphore proof for the given packed allocation. With
     *  MockSemaphoreVerifier the points/root are not checked — see HONESTY BAR. */
    function mockProof(opts: { alloc: bigint; nullifier: bigint; root: any; scope: bigint; message?: bigint }) {
        return {
            merkleTreeDepth: 1,
            merkleTreeRoot: opts.root,
            nullifier: opts.nullifier,
            message: opts.message ?? opts.alloc,
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

        it("exposes MAX_OPTIONS = 8 and CREDITS = 100", async function () {
            expect(await voting.MAX_OPTIONS()).to.equal(8n);
            expect(await voting.CREDITS()).to.equal(100n);
        });
    });

    // ── initialize option cap ─────────────────────────────────────────

    describe("Initialize option cap", function () {
        it("Allows exactly MAX_OPTIONS (8) options", async function () {
            const opts = Array.from({ length: 8 }, (_, i) => `Opt ${i}`);
            const poll = await deployQuadraticVotingClone(opts);
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
                0, // resultsPolicy: sealed-until-close (default)
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

    // ── Voting (quadratic ballots) ────────────────────────────────────

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

        it("Spreading the full budget (Σvᵢ² == 100, e.g. 6+8) passes and tallies the VOTES", async function () {
            const alloc = pack([6, 8]); // 6²+8² = 36+64 = 100 (exactly CREDITS)
            await expect(voting.castVote(alloc, mockProof({ alloc, nullifier: 1n, root: group.root, scope })))
                .to.emit(voting, "VoteCast")
                .withArgs(alloc);
            // Tally adds the VOTES (6, 8), NOT the cost (36, 64).
            expect(await voting.getResults()).to.deep.equal([6n, 8n, 0n]);
        });

        it("Σvᵢ² == 101 reverts OverBudget", async function () {
            // 6²+8²+1² = 36+64+1 = 101 — one credit over the 100 budget.
            const alloc = pack([6, 8, 1]);
            await expect(
                voting.castVote(alloc, mockProof({ alloc, nullifier: 2n, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "OverBudget");
        });

        it("A single option at v=10 (cost 100) passes", async function () {
            const alloc = pack([10]); // 10² = 100 = CREDITS
            await voting.castVote(alloc, mockProof({ alloc, nullifier: 3n, root: group.root, scope }));
            expect(await voting.getResults()).to.deep.equal([10n, 0n, 0n]);
        });

        it("A single option at v=11 (cost 121) reverts OverBudget", async function () {
            const alloc = pack([11]); // 11² = 121 > 100. (11 fits in 4 bits — the
            // budget, not the encoding, is what rejects it.)
            await expect(
                voting.castVote(alloc, mockProof({ alloc, nullifier: 4n, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "OverBudget");
        });

        it("A nonzero slot at index >= options.length reverts InvalidBallot (ghost-slot rule)", async function () {
            // options.length == 3 → slots 0,1,2 are real; slot 3 is a ghost.
            // pack [0,0,0,1] puts 1 vote in the non-existent option 3.
            const alloc = pack([0, 0, 0, 1]);
            await expect(
                voting.castVote(alloc, mockProof({ alloc, nullifier: 5n, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "InvalidBallot");
        });

        it("Empty ballot (all slots 0) reverts EmptyBallot", async function () {
            await expect(
                voting.castVote(0n, mockProof({ alloc: 0n, nullifier: 6n, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "EmptyBallot");
        });

        it("Bits above bit 32 reverts InvalidBallot (high-bits guard) — 8-option poll", async function () {
            // With 8 options the ghost-slot loop runs zero iterations, so ONLY the
            // explicit `packedAlloc < (1 << 32)` guard catches bits ≥ 32. Use a
            // valid in-budget low-32 ballot (1 vote on opt0) plus a bit at pos 32.
            const poll = await deployQuadraticVotingClone(Array.from({ length: 8 }, (_, i) => `Opt ${i}`));
            await poll.registerVoters(commitments);
            await poll.startVoting();
            const pScope = BigInt(await poll.getAddress());
            const highBits = (1n << 0n) | (1n << 32n);
            await expect(
                poll.castVote(highBits, mockProof({ alloc: highBits, nullifier: 7n, root: group.root, scope: pScope }))
            ).to.be.revertedWithCustomError(poll, "InvalidBallot");
        });

        it("A 0-vote slot among real options is allowed (0 is a valid allocation)", async function () {
            // 0 on opt0, 3 on opt1, 0 on opt2 → cost 9, non-empty. Slot value 0 for
            // a REAL option is fine (unlike a ghost slot). Tally: only opt1.
            const alloc = pack([0, 3, 0]);
            await voting.castVote(alloc, mockProof({ alloc, nullifier: 8n, root: group.root, scope }));
            expect(await voting.getResults()).to.deep.equal([0n, 3n, 0n]);
        });

        it("OverBudget reverts, then the SAME voter retries with a valid ballot and SUCCEEDS (no lockout)", async function () {
            const nullifier = 42n;
            const over = pack([10, 1]); // 100+1 = 101 > 100
            await expect(
                voting.castVote(over, mockProof({ alloc: over, nullifier, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "OverBudget");
            // Nullifier must NOT have been consumed by the rejected ballot.
            expect(await voting.verifyParticipation(nullifier)).to.equal(false);

            const ok = pack([10]); // exactly 100
            await expect(voting.castVote(ok, mockProof({ alloc: ok, nullifier, root: group.root, scope })))
                .to.emit(voting, "VoteCast")
                .withArgs(ok);
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
            expect(await voting.getResults()).to.deep.equal([10n, 0n, 0n]);
        });

        it("Ghost-slot InvalidBallot reverts, then the SAME voter retries and SUCCEEDS (no lockout)", async function () {
            const nullifier = 43n;
            const ghost = pack([0, 0, 0, 5]); // vote in non-existent option 3
            await expect(
                voting.castVote(ghost, mockProof({ alloc: ghost, nullifier, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "InvalidBallot");
            expect(await voting.verifyParticipation(nullifier)).to.equal(false);

            const ok = pack([4, 0, 4]); // 16+16 = 32 ≤ 100
            await voting.castVote(ok, mockProof({ alloc: ok, nullifier, root: group.root, scope }));
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
            expect(await voting.getResults()).to.deep.equal([4n, 0n, 4n]);
        });

        it("Double-vote with the same nullifier reverts (AlreadyVoted)", async function () {
            const nullifier = 99n;
            await voting.castVote(pack([3]), mockProof({ alloc: pack([3]), nullifier, root: group.root, scope }));
            await expect(
                voting.castVote(pack([0, 3]), mockProof({ alloc: pack([0, 3]), nullifier, root: group.root, scope }))
            ).to.be.revertedWithCustomError(voting, "AlreadyVoted");
        });

        it("proof.message != packedAlloc reverts (TamperedVoteSignal), then valid retry succeeds (no lockout)", async function () {
            const nullifier = 55n;
            const alloc = pack([5, 5]); // 25+25 = 50 ≤ 100
            // proof.message is a DIFFERENT well-formed allocation ⇒ TamperedVoteSignal,
            // which fires BEFORE isNullifierUsed is set ⇒ no lockout.
            await expect(
                voting.castVote(
                    alloc,
                    mockProof({ alloc, nullifier, root: group.root, scope, message: pack([1]) })
                )
            ).to.be.revertedWithCustomError(voting, "TamperedVoteSignal");
            expect(await voting.verifyParticipation(nullifier)).to.equal(false);

            // Same nullifier retries with a matching message ⇒ succeeds.
            await voting.castVote(alloc, mockProof({ alloc, nullifier, root: group.root, scope }));
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
            expect(await voting.getResults()).to.deep.equal([5n, 5n, 0n]);
        });

        it("Wrong scope reverts (InvalidScope), then valid retry succeeds (no lockout)", async function () {
            const nullifier = 66n;
            const alloc = pack([7]); // 49 ≤ 100
            await expect(
                voting.castVote(alloc, mockProof({ alloc, nullifier, root: group.root, scope: 12345n }))
            ).to.be.revertedWithCustomError(voting, "InvalidScope");
            expect(await voting.verifyParticipation(nullifier)).to.equal(false);

            await voting.castVote(alloc, mockProof({ alloc, nullifier, root: group.root, scope }));
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
        });

        it("getResults sums VOTES per option correctly across 3 voters", async function () {
            // Voter 1: (5, 5, 0)  cost 50  → A+5, B+5
            // Voter 2: (0, 8, 6)  cost 100 → B+8, C+6
            // Voter 3: (10, 0, 0) cost 100 → A+10
            // Totals: A = 5+10 = 15, B = 5+8 = 13, C = 6.
            await voting.castVote(pack([5, 5, 0]), mockProof({ alloc: pack([5, 5, 0]), nullifier: 101n, root: group.root, scope }));
            await voting.castVote(pack([0, 8, 6]), mockProof({ alloc: pack([0, 8, 6]), nullifier: 102n, root: group.root, scope }));
            await voting.castVote(pack([10, 0, 0]), mockProof({ alloc: pack([10, 0, 0]), nullifier: 103n, root: group.root, scope }));
            expect(await voting.getResults()).to.deep.equal([15n, 13n, 6n]);
        });

        it("VoteCast emits the EXACT packedAlloc", async function () {
            const alloc = pack([3, 4, 5]); // 9+16+25 = 50 ≤ 100
            const tx = await voting.castVote(alloc, mockProof({ alloc, nullifier: 21n, root: group.root, scope }));
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
            expect(parsed[0].args[0]).to.equal(alloc); // exact packed value emitted
        });

        it("Cannot vote in Registration phase (NotInVoting)", async function () {
            const fresh = await deployQuadraticVotingClone(["A", "B"]);
            await expect(
                fresh.castVote(1n, mockProof({ alloc: 1n, nullifier: 1n, root: 0n, scope: BigInt(await fresh.getAddress()) }))
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
            const alloc = pack([2]);
            await voting.castVote(alloc, mockProof({ alloc, nullifier, root: group.root, scope }));
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
        });

        it("Returns false for unused nullifier", async function () {
            expect(await voting.verifyParticipation(999n)).to.equal(false);
        });
    });

    // ── State transitions ────────────────────────────────────────────

    describe("State transitions", function () {
        it("Requires at least 2 options to start voting", async function () {
            const sparse = await deployQuadraticVotingClone(["Only Option"]);
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
                voting.initialize(await semaphore.getAddress(), owner.address, ["X", "Y"], 0)
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
            const poll = await deployQuadraticVotingClone(Array.from({ length: 8 }, (_, i) => `Opt ${i}`));
            await expect(poll.addOption("9th")).to.be.revertedWithCustomError(poll, "TooManyOptions");
        });

        it("Non-owner cannot add option", async function () {
            await expect(voting.connect(nonOwner).addOption("Unauthorized"))
                .to.be.revertedWithCustomError(voting, "OwnableUnauthorizedAccount")
                .withArgs(nonOwner.address);
        });
    });
    // ── R4 privacy defaults: resultsPolicy ──────────────────────────

    describe("resultsPolicy (R4 privacy defaults)", function () {
        it("defaults to sealed-until-close (0) in the standard fixture", async function () {
            expect(await voting.resultsPolicy()).to.equal(0);
        });

        /** Fresh registry + impl so the fixture's poll stays untouched. */
        async function freshRegistry() {
            const Impl = await ethers.getContractFactory("ZkQuadraticVoting");
            const impl = await Impl.deploy();
            const Registry = await ethers.getContractFactory("PollRegistry");
            const registry = await Registry.deploy();
            await registry.registerModule(MODULE, await impl.getAddress());
            return { registry, impl };
        }

        it("round-trips the live-public opt-in (1)", async function () {
            const { registry, impl } = await freshRegistry();
            const initData = impl.interface.encodeFunctionData("initialize", [
                await semaphore.getAddress(),
                owner.address,
                ["Yes", "No"],
                1, // resultsPolicy: live-public (creation-time opt-in)
            ]);
            await registry.createPoll(MODULE, "Live results", "", initData);
            const addr = (await registry.getAllPolls())[0].pollAddress;
            const live = await ethers.getContractAt("ZkQuadraticVoting", addr);
            expect(await live.resultsPolicy()).to.equal(1);
        });

        it("rejects an out-of-range policy (surfaces as registry InitFailed)", async function () {
            const { registry, impl } = await freshRegistry();
            const initData = impl.interface.encodeFunctionData("initialize", [
                await semaphore.getAddress(),
                owner.address,
                ["Yes", "No"],
                2, // invalid: only 0 (sealed) and 1 (live) exist
            ]);
            await expect(
                registry.createPoll(MODULE, "Bad policy", "", initData)
            ).to.be.revertedWithCustomError(registry, "InitFailed");
        });
    });

});
