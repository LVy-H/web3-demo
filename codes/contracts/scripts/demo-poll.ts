/**
 * Seed the local node with demo polls and emit a fixture the Flutter
 * on-chain-read integration test consumes. Run AFTER deploy:local:
 *
 *   npm run deploy:local && npx hardhat run scripts/demo-poll.ts --network localhost
 *
 * Two seeds:
 *   1. An `anon-vote` poll (the existing `demoPoll` fixture entry).
 *   2. A `survey-vote` poll (Phase 12d M6 STACK E2E): a real survey created via
 *      `PollRegistry.createPoll("survey-vote", …)` with a double-wrapped
 *      `initData = abi.encode((uint8,string[])[])`, a registered voter, ONE
 *      survey ballot cast end-to-end, and a `getSurveyResults()` read asserting
 *      non-empty per-question tallies. This proves the full survey stack —
 *      deploy/register → create with the nested initData → cast (hash-commitment
 *      ballot bound to the proof `message`) → per-question tally read — on a real
 *      chain, no emulator. It runs against the local MockSemaphoreVerifier (the
 *      SAME honesty bound as the other demo casts: the SNARK is accepted without
 *      verification, so this proves the serialization / commitment-recompute /
 *      per-question tally LOGIC, not real Groth16 validity — see the HONESTY BAR
 *      in docs/architecture/module-survey.md).
 *
 * Mirrors the frontend's CreatePoll encoding:
 *   createPoll("anon-vote", title, desc, ZkAnonVoting.initialize(semaphore, owner, options))
 */
import { ethers, network } from "hardhat";
import { Group } from "@semaphore-protocol/group";
import fs from "fs";
import path from "path";

const OPTIONS = ["Yes", "No", "Abstain"];
const TITLE = "Demo Poll";
const DESCRIPTION = "A demo anon-vote poll for the Flutter on-chain read tests";

// ── Survey seed constants (Phase 12d M6) ────────────────────────────────────
const SURVEY_TITLE = "Demo Survey";
const SURVEY_DESCRIPTION =
  "A demo survey-vote poll (Q0 single-choice, Q1 multi-select) for the stack e2e";
// Q0 single-choice / 3 options, Q1 multi-select / 4 options — the spec's worked
// shape. The voter answers Q0 = option 2 (Blue), Q1 = bitmask 0b0101 = {A, C}.
const QType = { SingleChoice: 0, MultiSelect: 1 } as const;
const SURVEY_QUESTIONS = [
  { qType: QType.SingleChoice, options: ["Red", "Green", "Blue"] },
  { qType: QType.MultiSelect, options: ["A", "B", "C", "D"] },
];
const SURVEY_ANSWERS = [2, 5];

const coder = ethers.AbiCoder.defaultAbiCoder();

/** The survey ballot commitment: message = keccak256(abi.encode(answers)) >> 8.
 *  Copied VERBATIM from ZkSurveyVoting.test.ts (Gate 2) — `coder.encode(
 *  ['uint256[]'], [a])` produces the canonical offset+length+words layout that
 *  Solidity's on-chain `keccak256(abi.encode(answers))` reproduces byte-for-byte.
 *  The cast only lands if the contract's recompute equals this value; do NOT
 *  hand-roll abi.encode. */
const surveyMsg = (a: (number | bigint)[]): bigint =>
  BigInt(ethers.keccak256(coder.encode(["uint256[]"], [a]))) >> 8n;

/** ABI-encode a Question[] (the survey's initData blob): the double-wrapped
 *  `(uint8 qType, string[] options)[]`. The enum is encoded as uint8 so the
 *  contract's `abi.decode(initData, (Question[]))` range-validates it. */
function encodeSurveyInit(
  qs: { qType: number; options: string[] }[],
): string {
  return coder.encode(
    ["tuple(uint8 qType, string[] options)[]"],
    [qs.map((q) => ({ qType: q.qType, options: q.options }))],
  );
}
// Resolve relative to this script so the in-repo fixture is refreshed (the old
// hardcoded absolute path pointed at a worktree that no longer exists, leaving
// the committed fixture stale → chain_reader_test read a dead poll address).
const FIXTURE = path.resolve(
  __dirname,
  "../../mobile/test/fixtures/local_chain.json",
);

async function main() {
  const chainId = Number((await ethers.provider.getNetwork()).chainId);
  const addrPath = path.resolve(__dirname, "../deployed-addresses.json");
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

  // Register two voters (owner-only, allowed in Registration state) so the
  // group-reconstruction read has real VoterRegistered logs to decode.
  const commitments = ["11111111111111111111", "22222222222222222222"];
  const poll = await ethers.getContractAt("ZkAnonVoting", pollAddress);
  await (await poll.registerVoters(commitments.map((c) => BigInt(c)))).wait();

  // Advance Registration -> Voting so the poll shows in the app's default
  // "Active" Browse view (Registration maps to "upcoming", which the Active
  // filter hides) and the read-only vote area renders. The registered voters
  // stay readable via VoterRegistered events.
  await (await poll.startVoting()).wait();

  // ── Seed 2: survey-vote poll (Phase 12d M6 stack e2e) ─────────────────────
  // Created AFTER the anon poll so the anon clone stays the registry's first
  // createPoll — its address is unchanged and the committed `demoPoll` fixture
  // entry stays byte-identical. `demoSurvey` is a purely additive fixture key
  // (chain_reader_test reads only `demoPoll`).
  console.log("\n── Survey stack e2e (12d M6) ──");

  // 1. Create the survey via the registry. PollRegistry.createPoll does
  //    `clone.call(initData)`, so initData is the FULL `initialize(semaphore,
  //    owner, questionBlob)` calldata — and questionBlob is itself the
  //    double-wrapped `abi.encode((uint8,string[])[])` the contract decodes.
  const surveyIface = (await ethers.getContractFactory("ZkSurveyVoting"))
    .interface;
  const questionBlob = encodeSurveyInit(SURVEY_QUESTIONS);
  const surveyInit = surveyIface.encodeFunctionData("initialize", [
    SEMAPHORE,
    owner.address,
    questionBlob,
  ]);
  const surveyTx = await registry.createPoll(
    "survey-vote",
    SURVEY_TITLE,
    SURVEY_DESCRIPTION,
    surveyInit,
  );
  const surveyReceipt = await surveyTx.wait();
  let surveyAddress: string | undefined;
  for (const log of surveyReceipt!.logs) {
    try {
      const parsed = registry.interface.parseLog(log);
      if (parsed?.name === "PollCreated") {
        surveyAddress = parsed.args.pollAddress as string;
        break;
      }
    } catch {
      /* not a registry event */
    }
  }
  if (!surveyAddress)
    throw new Error("Could not determine survey address from PollCreated");
  console.log(`  created survey at ${surveyAddress} (tx ${surveyTx.hash})`);

  const survey = await ethers.getContractAt("ZkSurveyVoting", surveyAddress);

  // 2. Register a voter and open voting.
  const surveyCommitment = "33333333333333333333";
  await (await survey.registerVoter(BigInt(surveyCommitment))).wait();
  await (await survey.startVoting()).wait();

  // 3. Cast ONE survey ballot end-to-end. The hash-commitment ballot binds the
  //    whole answer vector to the single Semaphore `message`; the contract
  //    recomputes keccak256(abi.encode(answers)) >> 8 and requires it equals
  //    proof.message. Against MockSemaphoreVerifier the Groth16 POINTS are not
  //    checked (same honesty bound as the other demo casts) — but Semaphore's
  //    verifyProof still membership-checks `merkleTreeRoot` against the on-chain
  //    group, so we reconstruct the group root off-chain from the one registered
  //    commitment (the proven idiom from ZkSurveyVoting.test.ts). And `message`
  //    MUST equal the on-chain recompute or the cast reverts TamperedVoteSignal,
  //    so a landed cast proves the cross-impl serialization on a real chain.
  // The cast below uses a mock Groth16 proof (points = all-zero), which only the
  // MockSemaphoreVerifier accepts. Under USE_REAL_VERIFIER the real verifier
  // rejects it and the cast reverts, so skip the cast + tally-assert — the survey
  // is still created, registered, and opened, ready for a REAL on-device vote.
  // Per-question survey tallies for the fixture below. Stays all-zero under the
  // real verifier (the survey is created but not voted); the mock path fills it
  // from the on-chain results after its cast.
  let surveyResultsNum: number[][] = SURVEY_QUESTIONS.map((q) =>
    q.options.map(() => 0),
  );
  const useRealVerifier = process.env.USE_REAL_VERIFIER === "true";
  if (useRealVerifier) {
    console.log(
      "  (USE_REAL_VERIFIER: skipping the mock-proof survey cast — survey created, registered, and opened for a real proof)",
    );
  } else {
    const group = new Group();
    group.addMember(BigInt(surveyCommitment));
    const surveyScope = BigInt(surveyAddress);
    const surveyProof = {
      merkleTreeDepth: 1,
      merkleTreeRoot: group.root,
      nullifier: 1n,
      message: surveyMsg(SURVEY_ANSWERS),
      scope: surveyScope,
      points: [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n],
    };
    const castTx = await survey.castVote(SURVEY_ANSWERS, surveyProof);
    await castTx.wait();
    console.log(
      `  cast survey ballot answers=[${SURVEY_ANSWERS.join(", ")}] (tx ${castTx.hash})`,
    );

    // 4. Read per-question tallies and assert they are non-empty (the stack proof).
    //    answers = [2, 5]: Q0 → option 2 (Blue); Q1 bitmask 5 = 0b0101 → {A, C}.
    const surveyResults: bigint[][] = await survey.getSurveyResults();
    surveyResultsNum = surveyResults.map((q) => q.map((c) => Number(c)));
    const totalTallied = surveyResultsNum
      .flat()
      .reduce((a: number, b: number) => a + b, 0);
    if (totalTallied === 0)
      throw new Error(
        "Survey stack e2e FAILED: getSurveyResults() is all-zero after a cast",
      );
    console.log("  getSurveyResults():");
    surveyResultsNum.forEach((q, i) => {
      const labels = SURVEY_QUESTIONS[i].options;
      const kind = SURVEY_QUESTIONS[i].qType === QType.SingleChoice
        ? "single-choice"
        : "multi-select";
      console.log(
        `    Q${i} (${kind}): ${q
          .map((c, j) => `${labels[j]}=${c}`)
          .join("  ")}`,
      );
    });
    console.log(`  per-question tallies non-empty (total approvals/votes = ${totalTallied}) ✓`);
  }

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
      expectedState: 1, // Voting (advanced above)
      expectedResults: OPTIONS.map(() => 0),
      registeredCommitments: commitments,
      expectedParticipantCount: commitments.length,
    },
    // Additive Phase-12d entry — a survey-vote poll with one cast ballot so the
    // app can browse it. The per-question tallies reflect answers = [2, 5].
    demoSurvey: {
      address: surveyAddress,
      moduleType: "survey-vote",
      title: SURVEY_TITLE,
      description: SURVEY_DESCRIPTION,
      expectedState: 1, // Voting (advanced above)
      questions: SURVEY_QUESTIONS.map((q) => ({
        qType: q.qType,
        type: q.qType === QType.SingleChoice ? "single-choice" : "multi-select",
        options: q.options,
      })),
      castAnswers: SURVEY_ANSWERS,
      expectedSurveyResults: surveyResultsNum,
      registeredCommitments: [surveyCommitment],
      expectedParticipantCount: 1,
    },
  };
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true });
  fs.writeFileSync(FIXTURE, JSON.stringify(fixture, null, 2));
  console.log(`\nDemo poll created at ${pollAddress}`);
  console.log(`Demo survey created at ${surveyAddress}`);
  console.log(`Fixture written: ${FIXTURE}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
