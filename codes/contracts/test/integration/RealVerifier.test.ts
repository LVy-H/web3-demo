import { expect } from "chai";
import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import { generateProof } from "@semaphore-protocol/proof";
import * as crypto from "crypto";
import * as path from "path";

/**
 * Real Groth16 verifier integration (P4-23). Deploys the REAL `SemaphoreVerifier`
 * (not the accept-anything Mock), generates a REAL Semaphore proof with the
 * bundled depth-16 artifacts (NO CDN fetch — `codes/mobile/assets/zk`), and
 * asserts the on-chain verifier ACCEPTS a valid vote and REJECTS a tampered one.
 *
 * This is the behaviour the MockSemaphoreVerifier cannot exercise. It runs
 * snarkjs (a real proof, ~seconds) so it's gated behind `RUN_REAL_VERIFIER=1`
 * and skipped by the fast suite (nightly / on-demand).
 */
const run = process.env.RUN_REAL_VERIFIER === "1";
const CONTRACTS_ROOT = path.resolve(__dirname, "../..");
const ARTIFACTS = {
    wasm: path.join(CONTRACTS_ROOT, "../mobile/assets/zk/semaphore-16.wasm"),
    zkey: path.join(CONTRACTS_ROOT, "../mobile/assets/zk/semaphore-16.zkey"),
};
const DEPTH = 16; // matches the bundled artifacts; LeanIMT root is member-derived

(run ? describe : describe.skip)("RealVerifier (Groth16) — P4-23", function () {
    this.timeout(180000);

    it("real verifier accepts a valid proof and rejects a tampered one", async function () {
        const [owner] = await ethers.getSigners();

        // Deploy: PoseidonT3 → REAL SemaphoreVerifier → Semaphore → ZkAnonVoting clone.
        const PoseidonT3 = await ethers.getContractFactory("PoseidonT3");
        const poseidon = await PoseidonT3.deploy();
        const Verifier = await ethers.getContractFactory("SemaphoreVerifier");
        const verifier = await Verifier.deploy();
        const Semaphore = await ethers.getContractFactory("Semaphore", {
            libraries: {
                "poseidon-solidity/PoseidonT3.sol:PoseidonT3":
                    await poseidon.getAddress(),
            },
        });
        const semaphore = await Semaphore.deploy(await verifier.getAddress());

        const Impl = await ethers.getContractFactory("ZkAnonVoting");
        const impl = await Impl.deploy();
        const Registry = await ethers.getContractFactory("PollRegistry");
        const registry = await Registry.deploy();
        await registry.registerModule("anon-vote", await impl.getAddress());
        const initData = impl.interface.encodeFunctionData("initialize", [
            await semaphore.getAddress(),
            owner.address,
            ["Yes", "No"],
        ]);
        await registry.createPoll("anon-vote", "Real", "real verifier", initData);
        const pollAddr = (await registry.getAllPolls())[0].pollAddress;
        const voting = await ethers.getContractAt("ZkAnonVoting", pollAddr);

        // Register a real identity, then open voting.
        const identity = new Identity(crypto.randomBytes(32).toString("hex"));
        await voting.registerVoters([identity.commitment]);
        await voting.startVoting();

        // A REAL Groth16 proof for "Yes" (option 0), scope = poll address.
        const group = new Group([identity.commitment]);
        const scope = BigInt(pollAddr);
        const message = 0n;
        const proof = await generateProof(
            identity,
            group,
            message,
            scope,
            DEPTH,
            ARTIFACTS
        );
        const sp = {
            merkleTreeDepth: proof.merkleTreeDepth,
            merkleTreeRoot: proof.merkleTreeRoot,
            nullifier: proof.nullifier,
            message: proof.message,
            scope: proof.scope,
            points: proof.points,
        };

        // Tampered points → the REAL verifier rejects (a Mock would accept). Cast
        // it FIRST: the revert doesn't consume the nullifier, so the valid cast
        // below still lands.
        const bad = { ...sp, points: [...sp.points] };
        bad.points[0] = (BigInt(bad.points[0]) ^ 1n).toString();
        await expect(voting.castVote(message, bad)).to.be.reverted;

        // Valid proof → the vote lands, verified by the real verifier.
        await expect(voting.castVote(message, sp)).to.emit(voting, "VoteCast");
        expect(await voting.getResults()).to.deep.equal([1n, 0n]);
    });
});
