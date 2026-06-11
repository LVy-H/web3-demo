import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import * as fs from "fs";
import * as path from "path";

/**
 * Live real-vs-mock verifier discriminator.
 *
 * A *successful* vote proves nothing about which verifier is wired — the
 * MockSemaphoreVerifier accepts every proof, including valid ones. The ONLY
 * behaviour that tells the real Groth16 verifier apart from the mock is a BAD
 * proof getting REJECTED. So this script, against the running local chain
 * (the same :8545 the mobile app hits):
 *
 *   1. creates a fresh anon-vote poll on the deployed registry,
 *   2. registers one real identity (so the Merkle root check passes — the cast
 *      reaches the verifier step rather than failing earlier),
 *   3. opens voting, then submits an all-zero (mock) Groth16 proof.
 *
 * Under the REAL verifier the cast must REVERT (Groth16 rejects zero points).
 * Under the mock it would SUCCEED. Exit 0 = real verifier confirmed; exit 2 =
 * the mock is live; exit 1 = unexpected error.
 *
 *   npx hardhat run scripts/check-live-verifier.ts --network localhost
 */
async function main() {
  const addrs = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../deployed-addresses.json"),
      "utf8",
    ),
  )["31337"];
  const [owner] = await ethers.getSigners();

  const registry = await ethers.getContractAt(
    "PollRegistry",
    addrs.REGISTRY_ADDRESS,
  );
  const impl = await ethers.getContractAt(
    "ZkAnonVoting",
    addrs.ANON_VOTING_IMPL,
  );
  const initData = impl.interface.encodeFunctionData("initialize", [
    addrs.SEMAPHORE_ADDRESS,
    owner.address,
    ["Yes", "No"],
    0, // resultsPolicy: sealed-until-close (default)
  ]);
  await (
    await registry.createPoll(
      "anon-vote",
      "LiveVerifierCheck",
      "real-vs-mock discriminator",
      initData,
    )
  ).wait();
  const polls = await registry.getAllPolls();
  const pollAddr = polls[polls.length - 1].pollAddress;
  const voting = await ethers.getContractAt("ZkAnonVoting", pollAddr);

  const identity = new Identity();
  await (await voting.registerVoters([identity.commitment])).wait();
  await (await voting.startVoting()).wait();

  // All-zero Groth16 proof with a valid Merkle root (group of the one registered
  // member) so the root check passes and the cast reaches the verifier.
  const group = new Group([identity.commitment]);
  const mockProof = {
    merkleTreeDepth: 1,
    merkleTreeRoot: group.root,
    nullifier: 1n,
    message: 0n,
    scope: BigInt(pollAddr),
    points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
  };

  console.log(`Live chain ${addrs.REGISTRY_ADDRESS} — poll ${pollAddr}`);
  try {
    await (await voting.castVote(0n, mockProof)).wait();
    console.log(
      "❌ MOCK-PROOF CAST SUCCEEDED — the MockSemaphoreVerifier is live, NOT the real Groth16 verifier.",
    );
    process.exitCode = 2;
  } catch {
    console.log(
      "✓ mock-proof cast REVERTED on the live chain — REAL Groth16 SemaphoreVerifier confirmed.",
    );
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
