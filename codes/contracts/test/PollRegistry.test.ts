import { expect } from "chai";
import { ethers } from "hardhat";

describe("PollRegistry", function () {
    let registry: any;
    let owner: any;
    let nonOwner: any;
    let semaphore: any;
    let zkAnonVotingImpl: any;

    beforeEach(async function () {
        [owner, nonOwner] = await ethers.getSigners();

        // Deploy Semaphore stack (needed by ZkAnonVoting impl)
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

        // Deploy implementation contract (not initialized -- just for cloning)
        const ZkAnonVoting = await ethers.getContractFactory("ZkAnonVoting");
        zkAnonVotingImpl = await ZkAnonVoting.deploy();

        // Deploy PollRegistry
        const PollRegistry = await ethers.getContractFactory("PollRegistry");
        registry = await PollRegistry.deploy();
    });

    // ── Module registration ──────────────────────────────────────────

    describe("registerModule", function () {
        it("Owner can register a module", async function () {
            await expect(
                registry.registerModule("zk-anon-voting", await zkAnonVotingImpl.getAddress())
            )
                .to.emit(registry, "ModuleRegistered")
                .withArgs("zk-anon-voting", await zkAnonVotingImpl.getAddress());

            expect(await registry.modules("zk-anon-voting")).to.equal(
                await zkAnonVotingImpl.getAddress()
            );
        });

        it("Non-owner is rejected", async function () {
            await expect(
                registry
                    .connect(nonOwner)
                    .registerModule("zk-anon-voting", await zkAnonVotingImpl.getAddress())
            ).to.be.revertedWith("Not owner");
        });

        it("Zero address is rejected", async function () {
            await expect(
                registry.registerModule("zk-anon-voting", ethers.ZeroAddress)
            ).to.be.revertedWith("Zero address");
        });
    });

    // ── Poll creation ────────────────────────────────────────────────

    describe("createPoll", function () {
        beforeEach(async function () {
            await registry.registerModule(
                "zk-anon-voting",
                await zkAnonVotingImpl.getAddress()
            );
        });

        it("Creates a poll and returns its address", async function () {
            const semaphoreAddr = await semaphore.getAddress();
            const initData = zkAnonVotingImpl.interface.encodeFunctionData(
                "initialize",
                [semaphoreAddr, owner.address, ["Yes", "No"]]
            );

            const tx = await registry.createPoll(
                "zk-anon-voting",
                "First Poll",
                "A test poll",
                initData
            );
            const receipt = await tx.wait();

            // Verify poll count
            expect(await registry.getPollCount()).to.equal(1);

            // Verify poll info
            const allPolls = await registry.getAllPolls();
            expect(allPolls.length).to.equal(1);
            expect(allPolls[0].moduleType).to.equal("zk-anon-voting");
            expect(allPolls[0].title).to.equal("First Poll");
            expect(allPolls[0].description).to.equal("A test poll");
            expect(allPolls[0].creator).to.equal(owner.address);
            expect(allPolls[0].pollAddress).to.not.equal(ethers.ZeroAddress);

            // Verify the clone is functional
            const clone = await ethers.getContractAt(
                "ZkAnonVoting",
                allPolls[0].pollAddress
            );
            const opts = await clone.getOptions();
            expect(opts).to.deep.equal(["Yes", "No"]);
            expect(await clone.owner()).to.equal(owner.address);
        });

        it("Rejects unregistered module type", async function () {
            await expect(
                registry.createPoll("nonexistent", "X", "Y", "0x")
            ).to.be.revertedWith("Module not registered");
        });

        it("Lists all polls", async function () {
            const semaphoreAddr = await semaphore.getAddress();

            for (let i = 0; i < 3; i++) {
                const initData = zkAnonVotingImpl.interface.encodeFunctionData(
                    "initialize",
                    [semaphoreAddr, owner.address, ["A", "B"]]
                );
                await registry.createPoll(
                    "zk-anon-voting",
                    `Poll ${i}`,
                    `Desc ${i}`,
                    initData
                );
            }

            expect(await registry.getPollCount()).to.equal(3);
            const all = await registry.getAllPolls();
            expect(all.length).to.equal(3);
            expect(all[2].title).to.equal("Poll 2");
        });
    });
});
