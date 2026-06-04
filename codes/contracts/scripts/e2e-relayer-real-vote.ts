import { ethers } from "hardhat";
import { Identity } from "@semaphore-protocol/identity";
import { Group } from "@semaphore-protocol/group";
import { generateProof } from "@semaphore-protocol/proof";
import * as fs from "fs";
import * as path from "path";

/**
 * End-to-end wallet-free vote against the REAL Groth16 verifier on the live chain.
 *
 * This exercises the exact submission pipeline the Tessera mobile app uses to
 * vote — `ProofService.generateVoteProof` → `RelayClient.relayVote` →
 * `POST /api/relay/vote` → relayer `castVote` → on-chain SemaphoreVerifier —
 * end to end, minus only the on-device WebView that hosts the prover. It
 * generates a REAL Semaphore proof from the bundled depth-16 artifacts (the same
 * `codes/mobile/assets/zk` the app ships), POSTs it to the running relayer, and:
 *
 *   - asserts a TAMPERED proof is REJECTED (the real verifier rejects it; the
 *     mock would accept — so this is what proves the path is genuinely verified),
 *   - asserts a VALID proof is RELAYED and the on-chain tally increments.
 *
 * Requires a running real-verifier stack:  ZK_REAL_VERIFIER=1 ./dev-stack.sh up
 *   npx hardhat run scripts/e2e-relayer-real-vote.ts --network localhost
 *   RELAYER_URL overrides the relayer base (default http://127.0.0.1:3001).
 *
 * Exit 0 = wallet-free relayer vote + real verifier confirmed; 2 = assertion
 * failed (mock live, or a valid proof rejected); 1 = unexpected error.
 */
const RELAYER = process.env.RELAYER_URL || "http://127.0.0.1:3001";
const ARTIFACTS = {
  wasm: path.join(__dirname, "../../mobile/assets/zk/semaphore-16.wasm"),
  zkey: path.join(__dirname, "../../mobile/assets/zk/semaphore-16.zkey"),
};
const DEPTH = 16; // matches the bundled artifacts

async function postVote(body: unknown): Promise<{
  status: number;
  json: Record<string, unknown>;
}> {
  const r = await fetch(`${RELAYER}/api/relay/vote`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = (await r.json().catch(() => ({}))) as Record<string, unknown>;
  return { status: r.status, json };
}

async function main() {
  const addrs = JSON.parse(
    fs.readFileSync(path.join(__dirname, "../deployed-addresses.json"), "utf8"),
  )["31337"];
  const [owner] = await ethers.getSigners();

  // 1. Owner side: create an anon-vote poll, register one identity, open voting.
  const registry = await ethers.getContractAt(
    "PollRegistry",
    addrs.REGISTRY_ADDRESS,
  );
  const impl = await ethers.getContractAt("ZkAnonVoting", addrs.ANON_VOTING_IMPL);
  const initData = impl.interface.encodeFunctionData("initialize", [
    addrs.SEMAPHORE_ADDRESS,
    owner.address,
    ["Yes", "No"],
  ]);
  await (
    await registry.createPoll(
      "anon-vote",
      "RealVoteE2E",
      "wallet-free relayer vote against the real verifier",
      initData,
    )
  ).wait();
  const polls = await registry.getAllPolls();
  const pollAddr = polls[polls.length - 1].pollAddress;
  const voting = await ethers.getContractAt("ZkAnonVoting", pollAddr);

  const identity = new Identity();
  await (await voting.registerVoters([identity.commitment])).wait();
  await (await voting.startVoting()).wait();
  console.log(`Poll ${pollAddr} — 1 voter registered, voting open.`);

  // 2. Voter side: a REAL Groth16 proof for "Yes" (option 0), scope = poll addr.
  const group = new Group([identity.commitment]);
  const vote = 0;
  const proof = await generateProof(
    identity,
    group,
    BigInt(vote),
    BigInt(pollAddr),
    DEPTH,
    ARTIFACTS,
  );
  const wire = {
    merkleTreeDepth: proof.merkleTreeDepth.toString(),
    merkleTreeRoot: proof.merkleTreeRoot.toString(),
    nullifier: proof.nullifier.toString(),
    message: proof.message.toString(),
    scope: proof.scope.toString(),
    points: proof.points.map((p) => p.toString()),
  };

  // 3a. Tampered proof FIRST — a reverted cast does not consume the nullifier,
  //     so the valid cast below still lands. The relayer must reject it.
  const tampered = { ...wire, points: [...wire.points] };
  tampered.points[0] = (BigInt(tampered.points[0]) ^ 1n).toString();
  const bad = await postVote({ pollAddress: pollAddr, vote, proof: tampered });
  if (bad.status >= 200 && bad.status < 300 && bad.json.success) {
    console.log(
      "❌ relayer ACCEPTED a tampered proof — the real verifier is NOT enforcing.",
    );
    process.exitCode = 2;
    return;
  }
  console.log(`✓ relayer rejected the tampered proof (HTTP ${bad.status}).`);

  // 3b. Valid proof — relayed, verified by the real verifier, tally increments.
  const good = await postVote({ pollAddress: pollAddr, vote, proof: wire });
  if (!(good.status >= 200 && good.status < 300 && good.json.success)) {
    console.log(
      `❌ relayer rejected a VALID proof (HTTP ${good.status}):`,
      good.json,
    );
    process.exitCode = 2;
    return;
  }
  const results = (await voting.getResults()).map((n: bigint) => Number(n));
  console.log(
    `✓ valid vote relayed (tx ${good.json.txHash}); on-chain results = [${results}].`,
  );
  if (results[0] !== 1 || results[1] !== 0) {
    console.log("❌ tally mismatch — expected [1, 0].");
    process.exitCode = 2;
    return;
  }
  console.log(
    "✓ END-TO-END: wallet-free relayer vote + REAL Groth16 verifier confirmed on the live chain.",
  );
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
