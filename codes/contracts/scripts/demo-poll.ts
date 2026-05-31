/**
 * Create one anon-vote demo poll on the local node and emit a fixture the
 * Flutter on-chain-read integration test consumes. Run AFTER deploy:local:
 *
 *   npm run deploy:local && npx hardhat run scripts/demo-poll.ts --network localhost
 *
 * Mirrors the frontend's CreatePoll encoding:
 *   createPoll("anon-vote", title, desc, ZkAnonVoting.initialize(semaphore, owner, options))
 */
import { ethers, network } from "hardhat";
import fs from "fs";
import path from "path";

const OPTIONS = ["Yes", "No", "Abstain"];
const TITLE = "Demo Poll";
const DESCRIPTION = "A demo anon-vote poll for the Flutter on-chain read tests";
const FIXTURE =
  "/home/hoang/zkvote-flutter-wt/codes/mobile/test/fixtures/local_chain.json";

async function main() {
  const chainId = Number((await ethers.provider.getNetwork()).chainId);
  const addrPath = path.resolve(__dirname, "../../frontend/src/deployed-addresses.json");
  const all = JSON.parse(fs.readFileSync(addrPath, "utf-8"));
  const entry = all[String(chainId)];
  if (!entry) throw new Error(`No deployed addresses for chainId ${chainId}`);
  const REGISTRY = entry.REGISTRY_ADDRESS as string;
  const SEMAPHORE = entry.SEMAPHORE_ADDRESS as string;

  const [owner] = await ethers.getSigners();
  const registry = await ethers.getContractAt("PollRegistry", REGISTRY);
  const anonIface = (await ethers.getContractFactory("ZkAnonVoting")).interface;

  const initData = anonIface.encodeFunctionData("initialize", [
    SEMAPHORE,
    owner.address,
    OPTIONS,
  ]);

  const tx = await registry.createPoll("anon-vote", TITLE, DESCRIPTION, initData);
  const receipt = await tx.wait();

  // Parse PollCreated to learn the clone address.
  let pollAddress: string | undefined;
  for (const log of receipt!.logs) {
    try {
      const parsed = registry.interface.parseLog(log);
      if (parsed?.name === "PollCreated") {
        pollAddress = parsed.args.pollAddress as string;
        break;
      }
    } catch {
      /* not a registry event */
    }
  }
  if (!pollAddress) throw new Error("Could not determine poll address from PollCreated");

  const fixture = {
    _comment:
      "Local Hardhat chain fixture for the Flutter on-chain read integration test. " +
      "Regenerate: npm run deploy:local && npx hardhat run scripts/demo-poll.ts --network localhost",
    rpcUrl: "http://127.0.0.1:8545",
    chainId,
    registry: REGISTRY,
    semaphore: SEMAPHORE,
    owner: owner.address,
    demoPoll: {
      address: pollAddress,
      moduleType: "anon-vote",
      title: TITLE,
      description: DESCRIPTION,
      options: OPTIONS,
      expectedState: 0, // Registration
      expectedResults: OPTIONS.map(() => 0),
    },
  };
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true });
  fs.writeFileSync(FIXTURE, JSON.stringify(fixture, null, 2));
  console.log(`Demo poll created at ${pollAddress}`);
  console.log(`Fixture written: ${FIXTURE}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
