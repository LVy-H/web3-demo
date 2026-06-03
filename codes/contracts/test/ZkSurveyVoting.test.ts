import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import * as crypto from "crypto";

// Canonical module string (see docs/superpowers/specs/2026-06-03-survey-voting-design.md).
// Used IDENTICALLY here, in scripts/deploy.ts, and in the relayer — we do NOT
// repeat M1's anon-vote/zk-anon-voting inconsistency.
const MODULE = "survey-vote";

// ── HONESTY BAR ────────────────────────────────────────────────────────────
// These tests run against MockSemaphoreVerifier, whose verifyProof ALWAYS
// returns true. So this suite proves the SERIALIZATION / commitment-recompute /
// per-question validation / per-question tally LOGIC — the abi.encode layout
// match (ethers === Solidity), the keccak256(abi.encode(answers)) >> 8 recompute
// equalling the bound message, per-question validation, the per-question tally,
// nullifier single-use, scope/message binding, the no-lockout retry, and the
// SurveyVoteCast emission — but it does NOT prove real SNARK validity. Identical
// honesty bound to M1/M2/M3/QV; real Groth16 verification is gated behind
// USE_REAL_VERIFIER (P4-23/P4-24).

const QType = { SingleChoice: 0, MultiSelect: 1 } as const;

const coder = ethers.AbiCoder.defaultAbiCoder();

/** The survey ballot commitment: message = keccak256(abi.encode(answers)) >> 8.
 *  This is the JS/ethers half of Gate 2 — `coder.encode(['uint256[]'], [a])`
 *  produces the canonical offset+length+words layout that Solidity's
 *  `abi.encode(uint256[])` reproduces byte-for-byte. If they ever diverged this
 *  value would not equal the contract's on-chain recompute and every cast would
 *  revert TamperedVoteSignal. */
const surveyMsg = (a: (number | bigint)[]): bigint =>
    BigInt(ethers.keccak256(coder.encode(["uint256[]"], [a]))) >> 8n;

/** ABI-encode a Question[] (the survey's initData blob). Each question is a
 *  `(uint8 qType, string[] options)` tuple — the enum MUST be encoded as uint8
 *  so abi.decode(initData, (Question[])) range-validates it on-chain. */
function encodeQuestions(qs: { qType: number; options: string[] }[]): string {
    return coder.encode(
        ["tuple(uint8 qType, string[] options)[]"],
        [qs.map((q) => ({ qType: q.qType, options: q.options }))]
    );
}

describe("ZkSurveyVoting", function () {
    let semaphore: any;
    let voting: any;
    let owner: any;
    let nonOwner: any;
    let commitments: bigint[] = [];

    // The spec's worked fixed vector: Q0 single-choice / 3 options, Q1
    // multi-select / 4 options.
    const SURVEY: { qType: number; options: string[] }[] = [
        { qType: QType.SingleChoice, options: ["Red", "Green", "Blue"] },
        { qType: QType.MultiSelect, options: ["A", "B", "C", "D"] },
    ];

    /** Deploy a fresh ZkSurveyVoting clone via PollRegistry. The bare
     *  implementation has _disableInitializers() so it can never be initialized
     *  directly — only clones produced by the registry are usable. */
    async function deploySurveyClone(
        qs: { qType: number; options: string[] }[]
    ): Promise<any> {
        const ZkSurveyVoting = await ethers.getContractFactory("ZkSurveyVoting");
        const impl = await ZkSurveyVoting.deploy();

        const PollRegistry = await ethers.getContractFactory("PollRegistry");
        const registry = await PollRegistry.deploy();

        await registry.registerModule(MODULE, await impl.getAddress());

        const initData = impl.interface.encodeFunctionData("initialize", [
            await semaphore.getAddress(),
            owner.address,
            encodeQuestions(qs),
        ]);

        await registry.createPoll(MODULE, "Survey", "Test survey", initData);

        const cloneAddress = (await registry.getAllPolls())[0].pollAddress;
        return ethers.getContractAt("ZkSurveyVoting", cloneAddress);
    }

    /** Like deploySurveyClone but returns the registry so the caller can assert
     *  on createPoll itself (e.g. the init-validation reverts, which surface as
     *  PollRegistry.InitFailed — the registry does not bubble the inner error). */
    async function deployRegistryAndImpl(): Promise<{ registry: any; impl: any }> {
        const ZkSurveyVoting = await ethers.getContractFactory("ZkSurveyVoting");
        const impl = await ZkSurveyVoting.deploy();
        const PollRegistry = await ethers.getContractFactory("PollRegistry");
        const registry = await PollRegistry.deploy();
        await registry.registerModule(MODULE, await impl.getAddress());
        return { registry, impl };
    }

    /** Deploy the Semaphore stack + default ZkSurveyVoting clone for beforeEach. */
    async function deployVoting(qs = SURVEY) {
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

        voting = await deploySurveyClone(qs);

        // Generate 3 voter identities.
        commitments = [];
        for (let i = 0; i < 3; i++) {
            const pk = crypto.randomBytes(32).toString("hex");
            commitments.push(new Identity(pk).commitment);
        }
    }

    /** Build a mock Semaphore proof binding `message` to the survey commitment of
     *  `answers` (overridable). With MockSemaphoreVerifier the points/root are not
     *  checked — see HONESTY BAR. */
    function mockProof(opts: {
        answers: (number | bigint)[];
        nullifier: bigint;
        root: any;
        scope: bigint;
        message?: bigint;
    }) {
        return {
            merkleTreeDepth: 1,
            merkleTreeRoot: opts.root,
            nullifier: opts.nullifier,
            message: opts.message ?? surveyMsg(opts.answers),
            scope: opts.scope,
            points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
        };
    }

    beforeEach(async function () {
        await deployVoting();
    });

    // ── IZkPoll compliance & survey views ─────────────────────────────

    describe("IZkPoll compliance & survey views", function () {
        it("getState returns Registration initially", async function () {
            expect(await voting.getState()).to.equal(0); // PollState.Registration
        });

        it("getParticipantCount starts at 0", async function () {
            expect(await voting.getParticipantCount()).to.equal(0);
        });

        it("owner returns the correct address", async function () {
            expect(await voting.owner()).to.equal(owner.address);
        });

        it("exposes MAX_OPTIONS = 32", async function () {
            expect(await voting.MAX_OPTIONS()).to.equal(32n);
        });

        it("getQuestionCount returns the number of questions", async function () {
            expect(await voting.getQuestionCount()).to.equal(2n);
        });

        it("getQuestionOptions / getQuestionType return each question's own labels & type", async function () {
            expect(await voting.getQuestionOptions(0)).to.deep.equal(["Red", "Green", "Blue"]);
            expect(await voting.getQuestionOptions(1)).to.deep.equal(["A", "B", "C", "D"]);
            expect(await voting.getQuestionType(0)).to.equal(QType.SingleChoice);
            expect(await voting.getQuestionType(1)).to.equal(QType.MultiSelect);
        });

        it("getSurveyResults returns one zero-filled array per question initially", async function () {
            const all = await voting.getSurveyResults();
            expect(all.length).to.equal(2);
            expect(all[0]).to.deep.equal([0n, 0n, 0n]); // Q0: 3 options
            expect(all[1]).to.deep.equal([0n, 0n, 0n, 0n]); // Q1: 4 options
        });

        // Gate 3: getResults()/getOptions() are the DOCUMENTED question-0 degenerate.
        it("getResults() is the documented question-0 tally (degenerate)", async function () {
            const q0 = await voting.getQuestionResults(0);
            const flat = await voting.getResults();
            expect(flat).to.deep.equal(q0);
            expect(flat.length).to.equal(3); // Q0 has 3 options
        });

        it("getOptions() is the documented question-0 labels (degenerate)", async function () {
            expect(await voting.getOptions()).to.deep.equal(["Red", "Green", "Blue"]);
        });
    });

    // ── Initialize validation ──────────────────────────────────────────
    //
    // Through the registry clone path these surface as PollRegistry.InitFailed
    // (createPoll does `(bool ok,) = clone.call(initData); if(!ok) revert
    // InitFailed();` — it does NOT bubble the inner NoQuestions/TooManyOptions/
    // NeedAtLeastTwoOptions revert). The bare impl can't be tested directly:
    // _disableInitializers() makes it revert InvalidInitialization first. The
    // behavioral guarantee — a malformed survey cannot be created — is asserted.

    describe("Initialize validation", function () {
        it("Rejects an empty survey (NoQuestions → InitFailed)", async function () {
            const { registry, impl } = await deployRegistryAndImpl();
            const initData = impl.interface.encodeFunctionData("initialize", [
                await semaphore.getAddress(),
                owner.address,
                encodeQuestions([]),
            ]);
            await expect(
                registry.createPoll(MODULE, "Empty", "no questions", initData)
            ).to.be.revertedWithCustomError(registry, "InitFailed");
        });

        it("Rejects a question with <2 options (NeedAtLeastTwoOptions → InitFailed)", async function () {
            const { registry, impl } = await deployRegistryAndImpl();
            const initData = impl.interface.encodeFunctionData("initialize", [
                await semaphore.getAddress(),
                owner.address,
                encodeQuestions([{ qType: QType.SingleChoice, options: ["Only one"] }]),
            ]);
            await expect(
                registry.createPoll(MODULE, "Sparse", "1 option", initData)
            ).to.be.revertedWithCustomError(registry, "InitFailed");
        });

        it("Rejects a question with >MAX_OPTIONS options (TooManyOptions → InitFailed)", async function () {
            const { registry, impl } = await deployRegistryAndImpl();
            const tooMany = Array.from({ length: 33 }, (_, i) => `Opt ${i}`);
            const initData = impl.interface.encodeFunctionData("initialize", [
                await semaphore.getAddress(),
                owner.address,
                encodeQuestions([{ qType: QType.MultiSelect, options: tooMany }]),
            ]);
            await expect(
                registry.createPoll(MODULE, "Huge", "33 options", initData)
            ).to.be.revertedWithCustomError(registry, "InitFailed");
        });

        it("Allows exactly MAX_OPTIONS (32) options on a question", async function () {
            const opts = Array.from({ length: 32 }, (_, i) => `Opt ${i}`);
            const poll = await deploySurveyClone([{ qType: QType.MultiSelect, options: opts }]);
            expect((await poll.getQuestionOptions(0)).length).to.equal(32);
        });

        it("exposes MAX_QUESTIONS = 16", async function () {
            expect(await voting.MAX_QUESTIONS()).to.equal(16n);
        });

        it("Rejects a survey with >MAX_QUESTIONS questions (TooManyQuestions → InitFailed)", async function () {
            // MAX_QUESTIONS + 1 well-formed questions (each ≥2 options, ≤MAX_OPTIONS),
            // so the ONLY init violation is the question-count cap — not a stray
            // per-question check (both would surface as InitFailed).
            const max = Number(await voting.MAX_QUESTIONS());
            const tooMany = Array.from({ length: max + 1 }, (_, i) => ({
                qType: QType.SingleChoice,
                options: [`Q${i}-A`, `Q${i}-B`],
            }));
            const { registry, impl } = await deployRegistryAndImpl();
            const initData = impl.interface.encodeFunctionData("initialize", [
                await semaphore.getAddress(),
                owner.address,
                encodeQuestions(tooMany),
            ]);
            await expect(
                registry.createPoll(MODULE, "Overlong", "too many questions", initData)
            ).to.be.revertedWithCustomError(registry, "InitFailed");
        });

        it("Allows exactly MAX_QUESTIONS questions & a basic cast tallies", async function () {
            // Exactly MAX_QUESTIONS well-formed questions; kept cheap (2 options each)
            // so the suite stays fast. Initializes, then a single SingleChoice cast
            // across every question succeeds.
            const max = Number(await voting.MAX_QUESTIONS());
            const qs = Array.from({ length: max }, (_, i) => ({
                qType: QType.SingleChoice,
                options: [`Q${i}-A`, `Q${i}-B`],
            }));
            const poll = await deploySurveyClone(qs);
            expect(await poll.getQuestionCount()).to.equal(BigInt(max));

            // A basic cast over all MAX_QUESTIONS questions (every answer = index 0).
            const pk = crypto.randomBytes(32).toString("hex");
            const commitment = new Identity(pk).commitment;
            await poll.registerVoter(commitment);
            const group = new Group();
            group.addMember(commitment);
            await poll.startVoting();

            const answers = Array.from({ length: max }, () => 0);
            const scope = BigInt(await poll.getAddress());
            await expect(
                poll.castVote(answers, mockProof({ answers, nullifier: 7n, root: group.root, scope }))
            ).to.emit(poll, "SurveyVoteCast");
            // Q0's first option got the single vote.
            expect((await poll.getSurveyResults())[0]).to.deep.equal([1n, 0n]);
        });

        it("Rejects an out-of-range enum qType (Panic 0x21 on decode → InitFailed)", async function () {
            // Only QType 0 (SingleChoice) and 1 (MultiSelect) exist. A hand-crafted
            // initData with qType = 2 makes Solidity 0.8's abi.decode revert
            // Panic(0x21) (invalid enum value) inside initialize — which surfaces as
            // PollRegistry.InitFailed through the clone path. encodeQuestions encodes
            // qType as a raw uint8, so a `2` lands directly in the enum slot.
            const { registry, impl } = await deployRegistryAndImpl();
            const initData = impl.interface.encodeFunctionData("initialize", [
                await semaphore.getAddress(),
                owner.address,
                encodeQuestions([{ qType: 2, options: ["A", "B"] }]),
            ]);
            await expect(
                registry.createPoll(MODULE, "BadEnum", "qType=2", initData)
            ).to.be.revertedWithCustomError(registry, "InitFailed");
        });

        it("Prevents double initialization", async function () {
            await expect(
                voting.initialize(await semaphore.getAddress(), owner.address, encodeQuestions(SURVEY))
            ).to.be.revertedWithCustomError(voting, "InvalidInitialization");
        });
    });

    // ── Registration ────────────────────────────────────────────────────

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

    // ── Voting (survey ballots) ──────────────────────────────────────────

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

        // ── Gate 2: the LOAD-BEARING keccak-recompute test ──────────────
        describe("Gate 2 — keccak recompute (ethers abi.encode === Solidity)", function () {
            it("The worked vector [2,5] succeeds: on-chain keccak(abi.encode(answers))>>8 == JS message", async function () {
                // answers = [2, 5]: Q0 = option 2 (Blue), Q1 = bitmask 0b0101 = {A, C}.
                const answers = [2, 5];
                const msg = surveyMsg(answers); // BigInt(keccak256(abi.encode([2,5]))) >> 8
                // proof.message is bound to the JS-computed commitment; the cast
                // succeeds ONLY IF the contract's on-chain recompute equals it —
                // i.e. ethers' abi.encode(uint256[]) layout matches Solidity's.
                await expect(
                    voting.castVote(answers, mockProof({ answers, nullifier: 1n, root: group.root, scope, message: msg }))
                )
                    .to.emit(voting, "SurveyVoteCast")
                    .withArgs(answers);
            });

            it("Binding message = msg + 1 reverts TamperedVoteSignal", async function () {
                const answers = [2, 5];
                const tampered = surveyMsg(answers) + 1n;
                await expect(
                    voting.castVote(
                        answers,
                        mockProof({ answers, nullifier: 2n, root: group.root, scope, message: tampered })
                    )
                ).to.be.revertedWithCustomError(voting, "TamperedVoteSignal");
            });
        });

        // ── Per-question validation ─────────────────────────────────────
        describe("Per-question validation", function () {
            it("WrongQuestionCount when answers.length != questions.length", async function () {
                const answers = [2]; // survey has 2 questions
                await expect(
                    voting.castVote(answers, mockProof({ answers, nullifier: 3n, root: group.root, scope }))
                ).to.be.revertedWithCustomError(voting, "WrongQuestionCount");
            });

            it("SingleChoice out-of-range index reverts InvalidAnswer", async function () {
                // Q0 has 3 options → valid indices 0,1,2. Index 3 is out of range.
                const answers = [3, 5];
                await expect(
                    voting.castVote(answers, mockProof({ answers, nullifier: 4n, root: group.root, scope }))
                ).to.be.revertedWithCustomError(voting, "InvalidAnswer");
            });

            it("MultiSelect empty (0) reverts InvalidAnswer", async function () {
                // Q1 bitmask 0 = no option selected → empty, rejected.
                const answers = [2, 0];
                await expect(
                    voting.castVote(answers, mockProof({ answers, nullifier: 5n, root: group.root, scope }))
                ).to.be.revertedWithCustomError(voting, "InvalidAnswer");
            });

            it("MultiSelect high-bit / out-of-range reverts InvalidAnswer", async function () {
                // Q1 has 4 options → valid bitmask range (0, 1<<4) = (0, 16). Bit 4
                // (value 16) is a non-existent option 4 — out of range.
                const answers = [2, 16];
                await expect(
                    voting.castVote(answers, mockProof({ answers, nullifier: 6n, root: group.root, scope }))
                ).to.be.revertedWithCustomError(voting, "InvalidAnswer");
            });
        });

        // ── Per-question tally ───────────────────────────────────────────
        describe("Per-question tally", function () {
            it("SingleChoice increments exactly one option; MultiSelect increments each set bit", async function () {
                // answers = [2, 5]: Q0 → option 2; Q1 bitmask 5 = 0b0101 → options 0 and 2.
                const answers = [2, 5];
                await voting.castVote(answers, mockProof({ answers, nullifier: 10n, root: group.root, scope }));
                const all = await voting.getSurveyResults();
                expect(all[0]).to.deep.equal([0n, 0n, 1n]); // Q0: only option 2
                expect(all[1]).to.deep.equal([1n, 0n, 1n, 0n]); // Q1: options 0 and 2
            });

            it("getSurveyResults sums exactly across 3 voters with mixed answers", async function () {
                // Voter 1: Q0=0,        Q1=0b0001={A}
                // Voter 2: Q0=2 (Blue), Q1=0b0101={A,C}
                // Voter 3: Q0=2 (Blue), Q1=0b1110={B,C,D}
                // Q0 tally: opt0=1, opt1=0, opt2=2
                // Q1 tally: A=2 (v1,v2), B=1 (v3), C=2 (v2,v3), D=1 (v3)
                await voting.castVote([0, 1], mockProof({ answers: [0, 1], nullifier: 21n, root: group.root, scope }));
                await voting.castVote([2, 5], mockProof({ answers: [2, 5], nullifier: 22n, root: group.root, scope }));
                await voting.castVote([2, 14], mockProof({ answers: [2, 14], nullifier: 23n, root: group.root, scope }));
                const all = await voting.getSurveyResults();
                expect(all[0]).to.deep.equal([1n, 0n, 2n]);
                expect(all[1]).to.deep.equal([2n, 1n, 2n, 1n]);
                // getQuestionResults(q) matches the slices of getSurveyResults().
                expect(await voting.getQuestionResults(0)).to.deep.equal([1n, 0n, 2n]);
                expect(await voting.getQuestionResults(1)).to.deep.equal([2n, 1n, 2n, 1n]);
                // Gate 3 (post-cast): getResults() IS the question-0 tally, not zeros.
                expect(await voting.getResults()).to.deep.equal([1n, 0n, 2n]);
            });
        });

        // ── Boundary vectors ─────────────────────────────────────────────
        describe("Boundary vectors", function () {
            it("Max SingleChoice option index (optionCount-1) is accepted & tallied", async function () {
                // Q0 has 3 options → max index 2. Q1 max bitmask handled below.
                const answers = [2, 1]; // Q0 max index 2; Q1 minimal non-empty {A}
                await voting.castVote(answers, mockProof({ answers, nullifier: 30n, root: group.root, scope }));
                expect((await voting.getSurveyResults())[0]).to.deep.equal([0n, 0n, 1n]);
            });

            it("Full-width MultiSelect bitmask (1<<optionCount)-1 is accepted & tallies every option", async function () {
                // Q1 has 4 options → full mask = (1<<4)-1 = 15 = 0b1111 → all of A,B,C,D.
                const answers = [0, 15];
                await voting.castVote(answers, mockProof({ answers, nullifier: 31n, root: group.root, scope }));
                expect((await voting.getSurveyResults())[1]).to.deep.equal([1n, 1n, 1n, 1n]);
            });
        });

        // ── Nullifier single-use & no-lockout ────────────────────────────
        describe("Nullifier single-use & no-lockout", function () {
            it("Double-vote with the same nullifier reverts (AlreadyVoted)", async function () {
                const nullifier = 99n;
                await voting.castVote([2, 5], mockProof({ answers: [2, 5], nullifier, root: group.root, scope }));
                await expect(
                    voting.castVote([1, 3], mockProof({ answers: [1, 3], nullifier, root: group.root, scope }))
                ).to.be.revertedWithCustomError(voting, "AlreadyVoted");
            });

            it("WrongQuestionCount reverts BEFORE the nullifier write — same identity retries & SUCCEEDS", async function () {
                const nullifier = 40n;
                const bad = [2]; // wrong length
                await expect(
                    voting.castVote(bad, mockProof({ answers: bad, nullifier, root: group.root, scope }))
                ).to.be.revertedWithCustomError(voting, "WrongQuestionCount");
                expect(await voting.verifyParticipation(nullifier)).to.equal(false);

                await voting.castVote([2, 5], mockProof({ answers: [2, 5], nullifier, root: group.root, scope }));
                expect(await voting.verifyParticipation(nullifier)).to.equal(true);
            });

            it("InvalidAnswer reverts BEFORE the nullifier write — same identity retries & SUCCEEDS", async function () {
                const nullifier = 41n;
                const bad = [2, 0]; // empty multi-select
                await expect(
                    voting.castVote(bad, mockProof({ answers: bad, nullifier, root: group.root, scope }))
                ).to.be.revertedWithCustomError(voting, "InvalidAnswer");
                expect(await voting.verifyParticipation(nullifier)).to.equal(false);

                await voting.castVote([1, 7], mockProof({ answers: [1, 7], nullifier, root: group.root, scope }));
                expect(await voting.verifyParticipation(nullifier)).to.equal(true);
            });

            it("TamperedVoteSignal reverts BEFORE the nullifier write — same identity retries & SUCCEEDS", async function () {
                const nullifier = 42n;
                const answers = [2, 5];
                // proof.message bound to a DIFFERENT vector ⇒ recompute mismatch.
                await expect(
                    voting.castVote(
                        answers,
                        mockProof({ answers, nullifier, root: group.root, scope, message: surveyMsg([1, 3]) })
                    )
                ).to.be.revertedWithCustomError(voting, "TamperedVoteSignal");
                expect(await voting.verifyParticipation(nullifier)).to.equal(false);

                await voting.castVote(answers, mockProof({ answers, nullifier, root: group.root, scope }));
                expect(await voting.verifyParticipation(nullifier)).to.equal(true);
            });
        });

        // ── Scope binding ────────────────────────────────────────────────
        it("Wrong scope reverts (InvalidScope), then valid retry succeeds (no lockout)", async function () {
            const nullifier = 50n;
            const answers = [2, 5];
            await expect(
                voting.castVote(answers, mockProof({ answers, nullifier, root: group.root, scope: 12345n }))
            ).to.be.revertedWithCustomError(voting, "InvalidScope");
            expect(await voting.verifyParticipation(nullifier)).to.equal(false);

            await voting.castVote(answers, mockProof({ answers, nullifier, root: group.root, scope }));
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
        });

        // ── Emission ──────────────────────────────────────────────────────
        it("SurveyVoteCast emits the EXACT answer vector", async function () {
            const answers = [1, 6];
            const tx = await voting.castVote(answers, mockProof({ answers, nullifier: 60n, root: group.root, scope }));
            const receipt = await tx.wait();
            const parsed = receipt.logs
                .map((l: any) => {
                    try {
                        return voting.interface.parseLog(l);
                    } catch {
                        return null;
                    }
                })
                .filter((p: any) => p && p.name === "SurveyVoteCast");
            expect(parsed.length).to.equal(1);
            expect(parsed[0].args[0]).to.deep.equal([1n, 6n]);
        });

        it("Cannot vote in Registration phase (NotInVoting)", async function () {
            const fresh = await deploySurveyClone(SURVEY);
            const answers = [2, 5];
            await expect(
                fresh.castVote(
                    answers,
                    mockProof({ answers, nullifier: 1n, root: 0n, scope: BigInt(await fresh.getAddress()) })
                )
            ).to.be.revertedWithCustomError(fresh, "NotInVoting");
        });
    });

    // ── Participation verification ───────────────────────────────────────

    describe("Participation verification", function () {
        it("Returns true after voting with that nullifier", async function () {
            await voting.registerVoters(commitments);
            const group = new Group();
            commitments.forEach((c) => group.addMember(c));
            await voting.startVoting();

            const scope = BigInt(await voting.getAddress());
            const nullifier = 444n;
            const answers = [2, 5];
            await voting.castVote(answers, mockProof({ answers, nullifier, root: group.root, scope }));
            expect(await voting.verifyParticipation(nullifier)).to.equal(true);
        });

        it("Returns false for unused nullifier", async function () {
            expect(await voting.verifyParticipation(999n)).to.equal(false);
        });
    });

    // ── State transitions ────────────────────────────────────────────────

    describe("State transitions", function () {
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
    });
});
