import { ethers } from "ethers";
import { getRelayerWallet, getProvider } from "./wallet";
import { config } from "./config";
import type { SemaphoreProof } from "./validation";
import ZkAnonVotingABI from "./abi/ZkAnonVoting.json";
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
