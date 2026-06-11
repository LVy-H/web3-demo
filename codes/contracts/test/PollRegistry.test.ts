import { expect } from "chai";
import { ethers } from "hardhat";

describe("PollRegistry", function () {
    let registry: any;
    let owner: any;
    let nonOwner: any;
    let semaphore: any;
    let zkAnonVotingImpl: any;

    /** Encode ZkAnonVoting.initialize(semaphore, owner, options, resultsPolicy). */
    async function anonInitData(
        options: string[] = ["Yes", "No"],
        resultsPolicy = 0
    ): Promise<string> {
        return zkAnonVotingImpl.interface.encodeFunctionData("initialize", [
            await semaphore.getAddress(),
            owner.address,
            options,
            resultsPolicy,
        ]);
    }

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
            )
                .to.be.revertedWithCustomError(registry, "OwnableUnauthorizedAccount")
                .withArgs(nonOwner.address);
        });

        it("Zero address is rejected", async function () {
            await expect(
                registry.registerModule("zk-anon-voting", ethers.ZeroAddress)
            ).to.be.revertedWithCustomError(registry, "ZeroAddress");
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
            const initData = await anonInitData();

            const tx = await registry.createPoll(
                "zk-anon-voting",
                "First Poll",
                "A test poll",
                initData
            );
            await tx.wait();

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
            )
                .to.be.revertedWithCustomError(registry, "ModuleNotRegistered")
                .withArgs("nonexistent");
        });

        it("Lists all polls", async function () {
            for (let i = 0; i < 3; i++) {
                await registry.createPoll(
                    "zk-anon-voting",
                    `Poll ${i}`,
                    `Desc ${i}`,
                    await anonInitData(["A", "B"])
                );
            }

            expect(await registry.getPollCount()).to.equal(3);
            const all = await registry.getAllPolls();
            expect(all.length).to.equal(3);
            expect(all[2].title).to.equal("Poll 2");
        });
    });

    // ── R4 privacy defaults: visibility + getListedPolls + getPollInfo ──

    describe("visibility (R4 privacy defaults)", function () {
        beforeEach(async function () {
            await registry.registerModule(
                "zk-anon-voting",
                await zkAnonVotingImpl.getAddress()
            );
        });

        it("4-arg createPoll defaults to UNLISTED (visibility = 0)", async function () {
            await registry.createPoll(
                "zk-anon-voting",
                "Default",
                "no visibility arg",
                await anonInitData()
            );

            const all = await registry.getAllPolls();
            expect(all.length).to.equal(1);
            expect(all[0].visibility).to.equal(0);
        });

        it("4-arg createPoll emits PollCreated with visibility = 0", async function () {
            await expect(
                registry.createPoll("zk-anon-voting", "Default", "d", await anonInitData())
            )
                .to.emit(registry, "PollCreated")
                .withArgs(
                    (addr: string) => ethers.isAddress(addr) && addr !== ethers.ZeroAddress,
                    "zk-anon-voting",
                    "Default",
                    owner.address,
                    0
                );
        });

        it("5-arg createPoll stores the opted-in LISTED flag and emits it", async function () {
            await expect(
                registry["createPoll(string,string,string,uint8,bytes)"](
                    "zk-anon-voting",
                    "Public",
                    "opted in",
                    1,
                    await anonInitData()
                )
            )
                .to.emit(registry, "PollCreated")
                .withArgs(
                    (addr: string) => ethers.isAddress(addr) && addr !== ethers.ZeroAddress,
                    "zk-anon-voting",
                    "Public",
                    owner.address,
                    1
                );

            const all = await registry.getAllPolls();
            expect(all[0].visibility).to.equal(1);
        });

        it("5-arg createPoll with explicit 0 stays unlisted", async function () {
            await registry["createPoll(string,string,string,uint8,bytes)"](
                "zk-anon-voting",
                "Explicitly private",
                "",
                0,
                await anonInitData()
            );
            expect((await registry.getAllPolls())[0].visibility).to.equal(0);
        });

        it("Rejects an out-of-range visibility value", async function () {
            await expect(
                registry["createPoll(string,string,string,uint8,bytes)"](
                    "zk-anon-voting",
                    "Bad",
                    "",
                    2,
                    await anonInitData()
                )
            )
                .to.be.revertedWithCustomError(registry, "InvalidVisibility")
                .withArgs(2);
        });

        it("getListedPolls returns ONLY listed polls (directory view)", async function () {
            // 2 unlisted (default), 2 listed (opt-in), 1 more unlisted (explicit)
            await registry.createPoll("zk-anon-voting", "U0", "", await anonInitData());
            await registry["createPoll(string,string,string,uint8,bytes)"](
                "zk-anon-voting", "L1", "", 1, await anonInitData());
            await registry.createPoll("zk-anon-voting", "U2", "", await anonInitData());
            await registry["createPoll(string,string,string,uint8,bytes)"](
                "zk-anon-voting", "L3", "", 1, await anonInitData());
            await registry["createPoll(string,string,string,uint8,bytes)"](
                "zk-anon-voting", "U4", "", 0, await anonInitData());

            // getAllPolls (owner/ops compat) still returns everything…
            expect((await registry.getAllPolls()).length).to.equal(5);

            // …but the public directory view filters to the opt-ins, in order.
            const listed = await registry.getListedPolls();
            expect(listed.length).to.equal(2);
            expect(listed.map((p: any) => p.title)).to.deep.equal(["L1", "L3"]);
            for (const p of listed) expect(p.visibility).to.equal(1);
        });

        it("getListedPolls is empty when every poll kept the default", async function () {
            await registry.createPoll("zk-anon-voting", "U0", "", await anonInitData());
            await registry.createPoll("zk-anon-voting", "U1", "", await anonInitData());
            expect((await registry.getListedPolls()).length).to.equal(0);
        });

        it("getPollInfo resolves an UNLISTED poll by address (link-access model)", async function () {
            await registry.createPoll(
                "zk-anon-voting",
                "Secret club vote",
                "link-only",
                await anonInitData()
            );
            const pollAddress = (await registry.getAllPolls())[0].pollAddress;

            // Not in the directory…
            expect((await registry.getListedPolls()).length).to.equal(0);

            // …but fully resolvable by whoever holds the link/QR/code.
            const info = await registry.getPollInfo(pollAddress);
            expect(info.pollAddress).to.equal(pollAddress);
            expect(info.title).to.equal("Secret club vote");
            expect(info.moduleType).to.equal("zk-anon-voting");
            expect(info.creator).to.equal(owner.address);
            expect(info.visibility).to.equal(0);
        });

        it("getPollInfo reverts UnknownPoll for an address the registry didn't create", async function () {
            const stranger = ethers.getAddress("0x00000000000000000000000000000000000000ff");
            await expect(registry.getPollInfo(stranger))
                .to.be.revertedWithCustomError(registry, "UnknownPoll")
                .withArgs(stranger);
        });

        it("exposes the visibility constants", async function () {
            expect(await registry.VISIBILITY_UNLISTED()).to.equal(0);
            expect(await registry.VISIBILITY_LISTED()).to.equal(1);
        });
    });
});
