/**
 * Sprint 0 · S0.3 — SPIKE: organizer-owned live-meeting registration loop.
 *
 * Goal (from the agile plan): empirically prove, with NO CONTRACT CHANGES,
 * that the Live Meeting Vote flow works on the existing ZkAnonVoting (M1):
 *
 *   1. The ORGANIZER (poll owner) registers an EPHEMERAL identity — generated
 *      exactly the way the wallet-free voter page will (`new Identity()`),
 *      no wallet, no token.
 *   2. The organizer transitions Registration → Voting (`startVoting`).
 *   3. A THIRD PARTY — the RELAYER (a different signer that is neither the
 *      owner nor the voter) — submits the voter's `castVote`. This is the
 *      gasless path: the voter never holds a wallet or pays gas.
 *   4. The tally increments and participation is verifiable by nullifier.
 *
 * It also proves the PHASE-ORDERING constraint that the live host UI must
 * respect (spec §2.2 #3): `registerVoter` only works in Registration and
 * `castVote` only works in Voting — they can never interleave. Hence the
 * live host is a sequential phase machine (confirm everyone → Start Voting →
 * vote), with no continuous late-join.
 *
 * CAVEAT — this runs against MockSemaphoreVerifier (returns true), so it
 * proves the FLOW + ACCESS CONTROL + PHASE ORDERING, not real ZK proof
 * verification. Real-Groth16 verification is the separate P4-23 nightly.
 */
import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";

describe("SPIKE S0.3 — organizer-owned live-meeting loop (no contract changes)", function () {
    let semaphore: any;
    let voting: any;
    let organizer: any; // poll owner — registers voters from their own wallet
    let relayer: any; // third-party submitter — neither owner nor voter

    async function deploySemaphoreAndPoll(options: string[]): Promise<any> {
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
        const impl = await ZkAnonVoting.deploy();

        const PollRegistry = await ethers.getContractFactory("PollRegistry");
        const registry = await PollRegistry.deploy();
        await registry.registerModule("zk-anon-voting", await impl.getAddress());

        // The poll is created by `organizer` → organizer becomes the owner.
        const initData = impl.interface.encodeFunctionData("initialize", [
            await semaphore.getAddress(),
            organizer.address,
            options,
        ]);
        await registry
            .connect(organizer)
            .createPoll("zk-anon-voting", "Live Meeting", "Spike poll", initData);

        const cloneAddress = (await registry.getAllPolls())[0].pollAddress;
        return ethers.getContractAt("ZkAnonVoting", cloneAddress);
    }

    beforeEach(async function () {
        [organizer, relayer] = await ethers.getSigners();
        voting = await deploySemaphoreAndPoll(["Yes", "No"]);
        expect(await voting.owner()).to.equal(organizer.address);
    });

    it("runs the full register → startVoting → relayed-vote → tally loop", async function () {
        // ── 1. Voter mints an EPHEMERAL identity in-browser (no wallet) ──
        const voterIdentity = new Identity();
        const commitment = voterIdentity.commitment;

        // ── 2. ORGANIZER (owner) registers it from their own wallet ──
        await expect(voting.connect(organizer).registerVoter(commitment))
            .to.emit(voting, "VoterRegistered")
            .withArgs(commitment);
        expect(await voting.registeredCommitments(commitment)).to.equal(true);
        expect(await voting.getParticipantCount()).to.equal(1);

        // ── 3a. PHASE ORDERING: cannot vote while still in Registration ──
        const scope = BigInt(await voting.getAddress());
        const earlyProof = {
            merkleTreeDepth: 1,
            merkleTreeRoot: 0n,
            nullifier: 1n,
            message: 0n,
            scope,
            points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
        };
        await expect(
            voting.connect(relayer).castVote(0n, earlyProof)
        ).to.be.revertedWithCustomError(voting, "NotInVoting");

        // ── 4. Organizer opens voting (Registration → Voting) ──
        await voting.connect(organizer).startVoting();
        expect(await voting.getState()).to.equal(1); // PollState.Voting

        // ── 3b. PHASE ORDERING: cannot register a late-comer once Voting started ──
        const lateComer = new Identity().commitment;
        await expect(
            voting.connect(organizer).registerVoter(lateComer)
        ).to.be.revertedWithCustomError(voting, "NotInRegistration");

        // ── 5. RELAYER submits the voter's vote (caller ≠ voter ≠ owner) ──
        // The group/root is frozen now that registration is closed — the live
        // voter page syncs the group only here (three-state model, S1.5).
        const group = new Group();
        group.addMember(commitment);
        const optionIndex = 0n; // "Yes"
        const nullifier = 42n;
        const voteProof = {
            merkleTreeDepth: 1,
            merkleTreeRoot: group.root,
            nullifier,
            message: optionIndex,
            scope,
            points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
        };
        await expect(voting.connect(relayer).castVote(optionIndex, voteProof))
            .to.emit(voting, "VoteCast")
            .withArgs(optionIndex);

        // ── 6. Tally incremented + participation provable by nullifier ──
        const results = await voting.getResults();
        expect(results[0]).to.equal(1n); // "Yes" got the vote
        expect(results[1]).to.equal(0n);
        expect(await voting.verifyParticipation(nullifier)).to.equal(true);
    });

    it("documents that the relayer never needs to be the owner (gasless, no ownership transfer)", async function () {
        // The relayer is a plain third party. It is NOT the owner and CANNOT
        // register voters — registration is the organizer's job. This is the
        // whole reason the live flow is organizer-owned, not relayer-owned.
        const commitment = new Identity().commitment;
        await expect(
            voting.connect(relayer).registerVoter(commitment)
        )
            .to.be.revertedWithCustomError(voting, "OwnableUnauthorizedAccount")
            .withArgs(relayer.address);
    });
});
