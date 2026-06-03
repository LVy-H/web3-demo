import { ethers } from "ethers";
import { getRelayerWallet, getProvider } from "./wallet";
import { getTxManager } from "./tx_manager";
import { getRegistryAddress } from "./config";
import type { SemaphoreProof } from "./validation";
import ZkAnonVotingABI from "./abi/ZkAnonVoting.json";
import ZkApprovalVotingABI from "./abi/ZkApprovalVoting.json";
import ZkRankedVotingABI from "./abi/ZkRankedVoting.json";
import ZkQuadraticVotingABI from "./abi/ZkQuadraticVoting.json";
import ZkSurveyVotingABI from "./abi/ZkSurveyVoting.json";
import ZkAirdropABI from "./abi/ZkAirdrop.json";
import PollRegistryABI from "./abi/PollRegistry.json";

function toProofStruct(proof: SemaphoreProof) {
    return {
        merkleTreeDepth: BigInt(proof.merkleTreeDepth),
        merkleTreeRoot: BigInt(proof.merkleTreeRoot),
        nullifier: BigInt(proof.nullifier),
        message: BigInt(proof.message),
        scope: BigInt(proof.scope),
        points: proof.points.map((p) => BigInt(p)),
    };
}

export async function relayCastVote(
    pollAddress: string,
    vote: number,
    proof: SemaphoreProof
): Promise<{ txHash: string }> {
    const wallet = getRelayerWallet();
    const contract = new ethers.Contract(pollAddress, ZkAnonVotingABI.abi, wallet);

    // Pre-check: poll must be in Voting state (state == 1)
    const state = await contract.getState();
    if (Number(state) !== 1) {
        throw new Error("Poll is not in voting phase");
    }

    // Pre-check: vote index must be valid
    const optionCount = await contract.getOptionCount();
    if (vote >= Number(optionCount)) {
        throw new Error(`Invalid vote index: ${vote}. Poll has ${optionCount} options`);
    }

    // Pre-check: nullifier not already used
    const isUsed = await contract.isNullifierUsed(BigInt(proof.nullifier));
    if (isUsed) {
        throw new Error("This vote token has already been used (nullifier consumed)");
    }

    const proofStruct = toProofStruct(proof);

    const { receipt } = await getTxManager().send("castVote", () =>
        contract.castVote.populateTransaction(vote, proofStruct)
    );
    return { txHash: receipt.hash };
}

export async function relayApprovalVote(
    pollAddress: string,
    bitmask: number,
    proof: SemaphoreProof
): Promise<{ txHash: string }> {
    const wallet = getRelayerWallet();
    const contract = new ethers.Contract(pollAddress, ZkApprovalVotingABI.abi, wallet);

    // Pre-check: poll must be in Voting state (state == 1)
    const state = await contract.getState();
    if (Number(state) !== 1) {
        throw new Error("Poll is not in voting phase");
    }

    // Pre-check: bitmask must be in range for this poll's option count.
    // Valid ballots are [1, 2^optionCount): non-empty and no bits beyond the
    // declared options. (The contract re-checks; this fails fast off-chain.)
    const optionCount = Number(await contract.getOptionCount());
    if (bitmask <= 0 || bitmask >= 2 ** optionCount) {
        throw new Error(
            `Invalid ballot bitmask ${bitmask}: poll has ${optionCount} options (valid range 1..${2 ** optionCount - 1})`
        );
    }

    // Pre-check: nullifier not already used
    const isUsed = await contract.isNullifierUsed(BigInt(proof.nullifier));
    if (isUsed) {
        throw new Error("This vote token has already been used (nullifier consumed)");
    }

    const proofStruct = toProofStruct(proof);

    const { receipt } = await getTxManager().send("approvalVote", () =>
        contract.castVote.populateTransaction(bitmask, proofStruct)
    );
    return { txHash: receipt.hash };
}

export async function relayRankedVote(
    pollAddress: string,
    packedRanking: number,
    proof: SemaphoreProof
): Promise<{ txHash: string }> {
    const wallet = getRelayerWallet();
    const contract = new ethers.Contract(pollAddress, ZkRankedVotingABI.abi, wallet);

    // Pre-check: poll must be in Voting state (state == 1)
    const state = await contract.getState();
    if (Number(state) !== 1) {
        throw new Error("Poll is not in voting phase");
    }

    // Pre-check: the first-preference slot must reference a real option. The
    // contract owns full slot validation (prefix/distinct/in-range/no-gap/no
    // high-bits); here we only fast-reject the cheapest off-chain check.
    const optionCount = Number(await contract.getOptionCount());
    const firstChoice = packedRanking & 0xf; // slot0, value = option index + 1
    if (firstChoice < 1 || firstChoice > optionCount) {
        throw new Error(
            `Invalid ranked ballot: first preference slot ${firstChoice} out of range for poll with ${optionCount} options`
        );
    }

    // Pre-check: nullifier not already used
    const isUsed = await contract.isNullifierUsed(BigInt(proof.nullifier));
    if (isUsed) {
        throw new Error("This vote token has already been used (nullifier consumed)");
    }

    const proofStruct = toProofStruct(proof);

    const { receipt } = await getTxManager().send("rankedVote", () =>
        contract.castVote.populateTransaction(packedRanking, proofStruct)
    );
    return { txHash: receipt.hash };
}

export async function relayQuadraticVote(
    pollAddress: string,
    packedAlloc: number,
    proof: SemaphoreProof
): Promise<{ txHash: string }> {
    const wallet = getRelayerWallet();
    const contract = new ethers.Contract(pollAddress, ZkQuadraticVotingABI.abi, wallet);

    // Pre-check: poll must be in Voting state (state == 1)
    const state = await contract.getState();
    if (Number(state) !== 1) {
        throw new Error("Poll is not in voting phase");
    }

    // Pre-check: no allocation to a non-existent option (cheap ghost-slot
    // fast-reject). The contract owns the full validation — the quadratic budget
    // (Σvᵢ² ≤ CREDITS), the empty-ballot check, and the high-bits guard. Here we
    // only confirm every slot at index >= optionCount is 0, mirroring the
    // contract's ghost-slot rule so an obviously-malformed ballot fails fast.
    const optionCount = Number(await contract.getOptionCount());
    for (let i = optionCount; i < 8; i++) {
        const v = (packedAlloc >> (4 * i)) & 0xf;
        if (v !== 0) {
            throw new Error(
                `Invalid quadratic ballot: slot ${i} allocates ${v} to a non-existent option (poll has ${optionCount} options)`
            );
        }
    }

    // Pre-check: nullifier not already used
    const isUsed = await contract.isNullifierUsed(BigInt(proof.nullifier));
    if (isUsed) {
        throw new Error("This vote token has already been used (nullifier consumed)");
    }

    const proofStruct = toProofStruct(proof);

    const { receipt } = await getTxManager().send("quadraticVote", () =>
        contract.castVote.populateTransaction(packedAlloc, proofStruct)
    );
    return { txHash: receipt.hash };
}

export async function relaySurveyVote(
    pollAddress: string,
    answers: string[],
    proof: SemaphoreProof
): Promise<{ txHash: string }> {
    const wallet = getRelayerWallet();
    const contract = new ethers.Contract(pollAddress, ZkSurveyVotingABI.abi, wallet);

    // Pre-check: poll must be in Voting state (state == 1)
    const state = await contract.getState();
    if (Number(state) !== 1) {
        throw new Error("Poll is not in voting phase");
    }

    // NOTE: unlike the single-question modules there is NO getOptionCount /
    // per-answer range pre-check here. A survey ballot is a full answer vector and
    // the contract owns ALL of its validation — the per-question type/range checks
    // (option index < optionCount, bitmask in range) AND the message binding
    // (proof.message == keccak256(abi.encode(answers)) >> 8). The relayer does NOT
    // recompute that commitment (re-deriving it in JS risks a Dart/JS/Solidity
    // mismatch), so it must NOT bind message to answers — that is the contract's
    // job. We only fast-check the cheap off-chain signals: state + nullifier.

    // Pre-check: nullifier not already used
    const isUsed = await contract.isNullifierUsed(BigInt(proof.nullifier));
    if (isUsed) {
        throw new Error("This vote token has already been used (nullifier consumed)");
    }

    const proofStruct = toProofStruct(proof);

    // The answer vector goes through as the first castVote arg (BigInt-ized so a
    // wide uint256 answer word survives). toProofStruct already BigInt-izes the
    // proof's `message` (the wide keccak commitment) and `scope`, so the full-width
    // commitment flows through unchanged.
    const { receipt } = await getTxManager().send("surveyVote", () =>
        contract.castVote.populateTransaction(
            answers.map((a) => BigInt(a)),
            proofStruct
        )
    );
    return { txHash: receipt.hash };
}

export async function relayClaimAirdrop(
    airdropAddress: string,
    receiver: string,
    proof: SemaphoreProof
): Promise<{ txHash: string }> {
    const wallet = getRelayerWallet();
    const contract = new ethers.Contract(airdropAddress, ZkAirdropABI.abi, wallet);

    // Pre-check: airdrop must be in Claiming state (state == 1)
    const state = await contract.state();
    if (Number(state) !== 1) {
        throw new Error("Airdrop is not in claiming phase");
    }

    // Pre-check: nullifier not already used
    const isUsed = await contract.isNullifierUsed(BigInt(proof.nullifier));
    if (isUsed) {
        throw new Error("Airdrop already claimed with this identity");
    }

    const proofStruct = toProofStruct(proof);

    const { receipt } = await getTxManager().send("claimAirdrop", () =>
        contract.claimAirdrop.populateTransaction(receiver, proofStruct)
    );
    return { txHash: receipt.hash };
}

// ── Sponsored poll lifecycle (M1) ───────────────────────────────────────────
//
// register-voter, start-voting and the state read are IDENTICAL across every
// module (same selector/signature), so they reuse ONE module ABI (ZkAnonVoting)
// on any poll address — no per-module dispatch. Only create-poll needs the
// PollRegistry ABI. The relayer is the owner (Decision 1A) so onlyOwner passes.

// The poll module ABI used for the owner-side calls (registerVoter / startVoting
// / getState). These three are part of the shared IZkPoll/Ownable surface and do
// not vary by module, so the anon ABI is a safe generic.
const MODULE_ABI = ZkAnonVotingABI.abi;

/** An error whose message is ALREADY vetted, user-facing copy (a known contract
 *  revert mapped to plain language, or a pre-check outcome like "joining is
 *  closed"). The routes return these as 400 with the message; ANY other error
 *  (a raw RPC / infra failure such as the node being unreachable) is returned as
 *  a generic 500 "Internal relayer error", mirroring the existing vote routes —
 *  so no raw RPC text ever leaks and infra failures aren't mislabeled 400. */
export class ClientFacingError extends Error {}

/** If `err` is a recognized contract revert, return a ClientFacingError carrying
 *  plain copy; otherwise return null (the caller re-throws the raw error so the
 *  route maps it to a generic 500). Recognizes the modules' custom-error names in
 *  the revert data/message. */
function mapLifecycleRevert(err: unknown): ClientFacingError | null {
    const raw = err instanceof Error ? err.message : String(err);
    if (/NotInRegistration|CanOnlyStartFromRegistration/.test(raw)) {
        return new ClientFacingError("Joining is closed — voting has already started on this poll.");
    }
    if (/AlreadyRegistered/.test(raw)) {
        return new ClientFacingError("This identity is already registered for this poll.");
    }
    if (/NeedAtLeastOneVoter/.test(raw)) {
        return new ClientFacingError("Can't open voting yet — at least one voter must join first.");
    }
    if (/NeedAtLeastTwoOptions/.test(raw)) {
        return new ClientFacingError("Can't open voting — the poll needs at least two options.");
    }
    if (/OwnableUnauthorizedAccount/.test(raw)) {
        return new ClientFacingError("This poll isn't hosted by this relayer.");
    }
    return null;
}

/** Sponsored CREATE: the relayer pays gas to clone + initialize a poll via
 *  PollRegistry.createPoll. The owner baked into initData is enforced == relayer
 *  upstream (validateCreatePollRequest), so the created poll is relayer-owned and
 *  the relayer can later register/start it. Returns the new poll address, parsed
 *  from the PollCreated event (a state-changing call's return value is NOT in the
 *  receipt — it must be read from the emitted log). */
export async function relayCreatePoll(
    moduleType: string,
    title: string,
    description: string,
    initData: string
): Promise<{ pollAddress: string; txHash: string }> {
    const registryAddress = getRegistryAddress();
    if (!registryAddress) {
        // Should be caught at the route layer; defensive here too.
        throw new Error("REGISTRY_NOT_CONFIGURED");
    }
    const wallet = getRelayerWallet();
    const registry = new ethers.Contract(registryAddress, PollRegistryABI.abi, wallet);

    const { receipt } = await getTxManager().send("createPoll", () =>
        registry.createPoll.populateTransaction(moduleType, title, description, initData)
    );

    // Parse PollCreated(address pollAddress, string moduleType, string title,
    // address creator) out of the logs — createPoll's returned address is not
    // available from a sent tx's receipt.
    const iface = new ethers.Interface(PollRegistryABI.abi);
    let pollAddress: string | undefined;
    for (const log of receipt.logs) {
        try {
            const parsed = iface.parseLog({ topics: log.topics, data: log.data });
            if (parsed && parsed.name === "PollCreated") {
                pollAddress = parsed.args[0] as string;
                break;
            }
        } catch {
            // Not a registry log (e.g. a Semaphore group-creation event) — skip.
        }
    }
    if (!pollAddress) {
        throw new Error("Poll was created but its address could not be read from the event");
    }

    return { pollAddress: ethers.getAddress(pollAddress), txHash: receipt.hash };
}

/** Sponsored REGISTER: the relayer (owner) adds a voter's identity commitment to
 *  the poll group. Under 0B this only works while the poll is in Registration
 *  (state 0); if voting has started we surface "joining is closed". Idempotent on
 *  an already-registered commitment so a double-tap "Join" is harmless. */
export async function relayRegisterVoter(
    pollAddress: string,
    identityCommitment: string
): Promise<{ txHash: string; alreadyRegistered: boolean }> {
    const wallet = getRelayerWallet();
    const contract = new ethers.Contract(pollAddress, MODULE_ABI, wallet);

    try {
        // Pre-check: under 0B registration is phase-locked to Registration
        // (state 0). Surface the honest 0B limitation clearly, not a raw revert.
        const state = Number(await contract.getState());
        if (state !== 0) {
            throw new ClientFacingError("Joining is closed — voting has already started on this poll.");
        }

        // Idempotent: if this commitment is already a member, a re-tap "Join" is
        // a no-op success (not an error). registeredCommitments(c) is public.
        const already = await contract.registeredCommitments(BigInt(identityCommitment));
        if (already) {
            return { txHash: "", alreadyRegistered: true };
        }

        const { receipt } = await getTxManager().send("registerVoter", () =>
            contract.registerVoter.populateTransaction(BigInt(identityCommitment))
        );
        return { txHash: receipt.hash, alreadyRegistered: false };
    } catch (err) {
        // Our own pre-check copy is already client-facing → re-throw verbatim.
        // A recognized contract revert → plain 400 copy. Anything else (infra /
        // node down) → re-throw raw so the route maps it to a generic 500.
        if (err instanceof ClientFacingError) throw err;
        const mapped = mapLifecycleRevert(err);
        if (mapped) throw mapped;
        throw err;
    }
}

/** Sponsored START: the relayer (owner) flips the poll Registration → Voting.
 *  This is the creator's "Open voting" action (0B). Maps the needs-≥1-voter /
 *  needs-≥2-options / wrong-state reverts to clear messages. */
export async function relayStartVoting(
    pollAddress: string
): Promise<{ txHash: string }> {
    const wallet = getRelayerWallet();
    const contract = new ethers.Contract(pollAddress, MODULE_ABI, wallet);

    try {
        // Fail fast on an obviously-wrong state (already Voting / Ended) with a
        // clear message; the contract re-checks (CanOnlyStartFromRegistration).
        const state = Number(await contract.getState());
        if (state !== 0) {
            throw new ClientFacingError("Voting is already open (or the poll has ended).");
        }

        const { receipt } = await getTxManager().send("startVoting", () =>
            contract.startVoting.populateTransaction()
        );
        return { txHash: receipt.hash };
    } catch (err) {
        if (err instanceof ClientFacingError) throw err;
        const mapped = mapLifecycleRevert(err);
        if (mapped) throw mapped;
        throw err;
    }
}

export async function checkRelayerBalance(): Promise<{
    sufficient: boolean;
    balance: string;
}> {
    const wallet = getRelayerWallet();
    const balance = await getProvider().getBalance(wallet.address);
    const balanceEth = ethers.formatEther(balance);
    return {
        sufficient: balance > ethers.parseEther("0.01"),
        balance: balanceEth,
    };
}
