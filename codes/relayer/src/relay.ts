import { ethers } from "ethers";
import { getRelayerWallet, getProvider } from "./wallet";
import { config } from "./config";
import type { SemaphoreProof } from "./validation";
import ZkAnonVotingABI from "./abi/ZkAnonVoting.json";
import ZkApprovalVotingABI from "./abi/ZkApprovalVoting.json";
import ZkRankedVotingABI from "./abi/ZkRankedVoting.json";
import ZkAirdropABI from "./abi/ZkAirdrop.json";

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

    const tx = await contract.castVote(vote, proofStruct, {
        gasLimit: config.maxGasLimit,
    });

    const receipt = await tx.wait();
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

    const tx = await contract.castVote(bitmask, proofStruct, {
        gasLimit: config.maxGasLimit,
    });

    const receipt = await tx.wait();
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

    const tx = await contract.castVote(packedRanking, proofStruct, {
        gasLimit: config.maxGasLimit,
    });

    const receipt = await tx.wait();
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

    const tx = await contract.claimAirdrop(receiver, proofStruct, {
        gasLimit: config.maxGasLimit,
    });

    const receipt = await tx.wait();
    return { txHash: receipt.hash };
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
