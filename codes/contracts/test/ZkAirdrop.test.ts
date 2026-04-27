import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import * as crypto from "crypto";

/**
 * ZkAirdrop test suite.
 *
 * Covers deployment, funding, registration, lifecycle, claim happy path,
 * and revert paths (wrong scope, wrong receiver, reused nullifier,
 * claim before startAirdrop). Follows the proof-shape pattern from
 * ZkAnonVoting.test.ts: builds an off-chain Semaphore Group whose root
 * mirrors the on-chain group, then constructs a SemaphoreProof struct
 * with zeroed `points`. The on-chain Semaphore.verifyProof checks the
 * merkleTreeRoot against the on-chain group, then delegates to the
 * MockSemaphoreVerifier which always returns true — so the proof
 * struct passes without needing real Groth16 artifacts.
 *
 * TODO(P4-23): test invalid-proof revert under the real SemaphoreVerifier
 * in nightly CI.
 */
describe("ZkAirdrop", function () {
    let semaphore: any;
    let airdrop: any;
    let owner: any;
    let nonOwner: any;
    let receiver: any;
    let funder: any;
    let airdropAddress: string;

    const AIRDROP_AMOUNT = ethers.parseEther("1.0");

    /** Deploy the full Semaphore stack + a fresh ZkAirdrop instance. */
    async function deployAirdrop(amount: bigint = AIRDROP_AMOUNT) {
        [owner, nonOwner, receiver, funder] = await ethers.getSigners();

        const PoseidonT3 = await ethers.getContractFactory("PoseidonT3");
        const poseidonT3 = await PoseidonT3.deploy();

        const MockVerifier = await ethers.getContractFactory(
            "MockSemaphoreVerifier"
        );
        const verifier = await MockVerifier.deploy();

        const Semaphore = await ethers.getContractFactory("Semaphore", {
            libraries: {
                "poseidon-solidity/PoseidonT3.sol:PoseidonT3":
                    await poseidonT3.getAddress(),
            },
        });
        semaphore = await Semaphore.deploy(await verifier.getAddress());

        const ZkAirdrop = await ethers.getContractFactory("ZkAirdrop");
        airdrop = await ZkAirdrop.deploy(await semaphore.getAddress(), amount);
        airdropAddress = await airdrop.getAddress();
    }

    /** Build a SemaphoreProof struct that the on-chain Semaphore will accept
     *  under MockSemaphoreVerifier (which returns true regardless of `points`). */
    function buildProof(opts: {
        group: Group;
        scope: bigint;
        message: bigint;
        nullifier: bigint;
    }) {
        return {
            merkleTreeDepth: 1,
            merkleTreeRoot: opts.group.root,
            nullifier: opts.nullifier,
            message: opts.message,
            scope: opts.scope,
            points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n] as [
                bigint,
                bigint,
                bigint,
                bigint,
                bigint,
                bigint,
                bigint,
                bigint
            ],
        };
    }

    beforeEach(async function () {
        await deployAirdrop();
    });

    // ── 1. Deployment + initial state ────────────────────────────────

    describe("Deployment + initial state", function () {
        it("owner is the deployer", async function () {
            expect(await airdrop.owner()).to.equal(owner.address);
        });

        it("airdropAmount matches constructor arg", async function () {
            expect(await airdrop.airdropAmount()).to.equal(AIRDROP_AMOUNT);
        });

        it("state == AirdropState.Registration (0)", async function () {
            expect(await airdrop.state()).to.equal(0);
        });

        it("groupId is set and the group exists on Semaphore", async function () {
            // Note: the prompt asked to assert "non-zero", but Semaphore's
            // group counter starts at 0, so the first group on a fresh
            // Semaphore deployment returns id 0. The meaningful assertion
            // is that Semaphore recognises the id (i.e. a group was
            // actually created) — getMerkleTreeSize succeeds for an
            // existing group and reverts for a non-existent one.
            const gid = await airdrop.groupId();
            expect(gid).to.equal(0n);
            expect(await semaphore.getMerkleTreeSize(gid)).to.equal(0n);
        });

        it("contract balance starts at 0 ETH", async function () {
            expect(await ethers.provider.getBalance(airdropAddress)).to.equal(
                0n
            );
        });
    });

    // ── 2. Funding via receive() ─────────────────────────────────────

    describe("Funding via receive()", function () {
        it("accepts ETH and balance increases", async function () {
            const value = ethers.parseEther("5.0");
            await funder.sendTransaction({ to: airdropAddress, value });
            expect(await ethers.provider.getBalance(airdropAddress)).to.equal(
                value
            );
        });

        it("accumulates across multiple sends", async function () {
            await funder.sendTransaction({
                to: airdropAddress,
                value: ethers.parseEther("1.0"),
            });
            await owner.sendTransaction({
                to: airdropAddress,
                value: ethers.parseEther("2.5"),
            });
            expect(await ethers.provider.getBalance(airdropAddress)).to.equal(
                ethers.parseEther("3.5")
            );
        });
    });

    // ── 3. Registration phase ────────────────────────────────────────

    describe("Registration phase", function () {
        it("registerMember succeeds and emits MemberRegistered", async function () {
            const id = new Identity(crypto.randomBytes(32).toString("hex"));
            await expect(airdrop.registerMember(id.commitment))
                .to.emit(airdrop, "MemberRegistered")
                .withArgs(id.commitment);
        });

        it("multiple commitments can register (permissionless — no admin gate)", async function () {
            const id1 = new Identity(crypto.randomBytes(32).toString("hex"));
            const id2 = new Identity(crypto.randomBytes(32).toString("hex"));
            const id3 = new Identity(crypto.randomBytes(32).toString("hex"));

            // owner registers one
            await airdrop.registerMember(id1.commitment);
            // non-owner can also register — proves no admin gate
            await airdrop.connect(nonOwner).registerMember(id2.commitment);
            // a third arbitrary signer too
            await airdrop.connect(receiver).registerMember(id3.commitment);

            expect(
                await semaphore.getMerkleTreeSize(await airdrop.groupId())
            ).to.equal(3n);
        });

        it("registerMember reverts after startAirdrop with 'Not in registration phase'", async function () {
            const id = new Identity(crypto.randomBytes(32).toString("hex"));
            await airdrop.registerMember(id.commitment);
            await airdrop.startAirdrop();

            const id2 = new Identity(crypto.randomBytes(32).toString("hex"));
            await expect(
                airdrop.registerMember(id2.commitment)
            ).to.be.revertedWith("Not in registration phase");
        });
    });

    // ── 4. Lifecycle / startAirdrop ──────────────────────────────────

    describe("Lifecycle / startAirdrop", function () {
        it("non-owner cannot startAirdrop ('Not owner')", async function () {
            await expect(
                airdrop.connect(nonOwner).startAirdrop()
            ).to.be.revertedWith("Not owner");
        });

        it("owner transitions Registration -> Claiming and emits AirdropStarted", async function () {
            await expect(airdrop.startAirdrop()).to.emit(
                airdrop,
                "AirdropStarted"
            );
            expect(await airdrop.state()).to.equal(1); // Claiming
        });

        it("second startAirdrop reverts with 'Can only start from registration'", async function () {
            await airdrop.startAirdrop();
            await expect(airdrop.startAirdrop()).to.be.revertedWith(
                "Can only start from registration"
            );
        });
    });

    // ── 5. Claim happy path ──────────────────────────────────────────

    describe("Claim happy path", function () {
        it("registered identity claims, ETH transferred, event emitted, nullifier marked", async function () {
            // Register one identity
            const id = new Identity(crypto.randomBytes(32).toString("hex"));
            await airdrop.registerMember(id.commitment);

            // Fund the airdrop with enough ETH
            await funder.sendTransaction({
                to: airdropAddress,
                value: ethers.parseEther("5.0"),
            });

            await airdrop.startAirdrop();

            // Build off-chain group mirroring the on-chain group
            const group = new Group();
            group.addMember(id.commitment);

            const scope = BigInt(airdropAddress);
            const message = BigInt(receiver.address);
            const nullifier = 12345n;

            const proof = buildProof({ group, scope, message, nullifier });

            const receiverBalBefore = await ethers.provider.getBalance(
                receiver.address
            );
            const airdropBalBefore = await ethers.provider.getBalance(
                airdropAddress
            );

            // The caller of claimAirdrop is not the receiver, so receiver's
            // balance change equals exactly airdropAmount (no gas cost on receiver).
            await expect(
                airdrop.connect(funder).claimAirdrop(receiver.address, proof)
            )
                .to.emit(airdrop, "AirdropClaimed")
                .withArgs(receiver.address, nullifier);

            const receiverBalAfter = await ethers.provider.getBalance(
                receiver.address
            );
            expect(receiverBalAfter - receiverBalBefore).to.equal(
                AIRDROP_AMOUNT
            );

            const airdropBalAfter = await ethers.provider.getBalance(
                airdropAddress
            );
            expect(airdropBalBefore - airdropBalAfter).to.equal(AIRDROP_AMOUNT);

            expect(await airdrop.isNullifierUsed(nullifier)).to.equal(true);
        });
    });

    // ── 6. Claim revert paths ────────────────────────────────────────

    describe("Claim revert paths", function () {
        let id: Identity;
        let group: Group;

        beforeEach(async function () {
            id = new Identity(crypto.randomBytes(32).toString("hex"));
            await airdrop.registerMember(id.commitment);
            await funder.sendTransaction({
                to: airdropAddress,
                value: ethers.parseEther("5.0"),
            });
            group = new Group();
            group.addMember(id.commitment);
        });

        it("claim before startAirdrop reverts with 'Not in claiming phase'", async function () {
            // Still in Registration — claim must fail.
            const proof = buildProof({
                group,
                scope: BigInt(airdropAddress),
                message: BigInt(receiver.address),
                nullifier: 1n,
            });
            await expect(
                airdrop.claimAirdrop(receiver.address, proof)
            ).to.be.revertedWith("Not in claiming phase");
        });

        it("wrong scope reverts with 'Invalid claim scope'", async function () {
            await airdrop.startAirdrop();
            const proof = buildProof({
                group,
                scope: BigInt(nonOwner.address), // not this airdrop's address
                message: BigInt(receiver.address),
                nullifier: 2n,
            });
            await expect(
                airdrop.claimAirdrop(receiver.address, proof)
            ).to.be.revertedWith("Invalid claim scope");
        });

        it("wrong receiver in message reverts with 'Receiver mismatch'", async function () {
            await airdrop.startAirdrop();
            const proof = buildProof({
                group,
                scope: BigInt(airdropAddress),
                message: BigInt(nonOwner.address), // message != receiver
                nullifier: 3n,
            });
            await expect(
                airdrop.claimAirdrop(receiver.address, proof)
            ).to.be.revertedWith("Receiver mismatch");
        });

        it("reused nullifier reverts with 'Airdrop already claimed by this identity'", async function () {
            await airdrop.startAirdrop();
            const proof = buildProof({
                group,
                scope: BigInt(airdropAddress),
                message: BigInt(receiver.address),
                nullifier: 4n,
            });

            // First claim succeeds
            await airdrop.claimAirdrop(receiver.address, proof);
            expect(await airdrop.isNullifierUsed(4n)).to.equal(true);

            // Second claim with the same nullifier reverts
            await expect(
                airdrop.claimAirdrop(receiver.address, proof)
            ).to.be.revertedWith("Airdrop already claimed by this identity");
        });
    });
});
