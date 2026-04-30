import { ethers } from "ethers";

export interface SemaphoreProof {
    merkleTreeDepth: string | number;
    merkleTreeRoot: string;
    nullifier: string;
    message: string;
    scope: string;
    points: string[];
}

export interface VoteRequest {
    pollAddress: string;
    vote: number;
    proof: SemaphoreProof;
}

export interface ClaimAirdropRequest {
    airdropAddress: string;
    receiver: string;
    proof: SemaphoreProof;
}

function isValidAddress(addr: unknown): addr is string {
    return typeof addr === "string" && ethers.isAddress(addr);
}

function isValidProof(proof: unknown): proof is SemaphoreProof {
    if (!proof || typeof proof !== "object") return false;
    const p = proof as Record<string, unknown>;

    if (p.merkleTreeDepth === undefined || p.merkleTreeDepth === null) return false;
    if (typeof p.merkleTreeRoot !== "string") return false;
    if (typeof p.nullifier !== "string") return false;
    if (typeof p.message !== "string") return false;
    if (typeof p.scope !== "string") return false;
    if (!Array.isArray(p.points) || p.points.length !== 8) return false;
    for (const pt of p.points) {
        if (typeof pt !== "string") return false;
    }

    return true;
}

export function validateVoteRequest(
    body: unknown
): { ok: true; data: VoteRequest } | { ok: false; error: string } {
    if (!body || typeof body !== "object") {
        return { ok: false, error: "Request body must be a JSON object" };
    }

    const b = body as Record<string, unknown>;

    if (!isValidAddress(b.pollAddress)) {
        return { ok: false, error: "Invalid pollAddress: must be a valid Ethereum address" };
    }

    if (typeof b.vote !== "number" || !Number.isInteger(b.vote) || b.vote < 0) {
        return { ok: false, error: "Invalid vote: must be a non-negative integer" };
    }

    if (!isValidProof(b.proof)) {
        return {
            ok: false,
            error: "Invalid proof: must include merkleTreeDepth, merkleTreeRoot, nullifier, message, scope, and points (array of 8 strings)",
        };
    }

    const proof = b.proof as SemaphoreProof;

    if (proof.message !== String(b.vote)) {
        return {
            ok: false,
            error: `Proof message (${proof.message}) does not match vote (${b.vote})`,
        };
    }

    const expectedScope = BigInt(b.pollAddress as string).toString();
    if (proof.scope !== expectedScope) {
        return {
            ok: false,
            error: `Proof scope does not match pollAddress. Expected ${expectedScope}, got ${proof.scope}`,
        };
    }

    return {
        ok: true,
        data: {
            pollAddress: b.pollAddress as string,
            vote: b.vote as number,
            proof,
        },
    };
}

export function validateClaimRequest(
    body: unknown
): { ok: true; data: ClaimAirdropRequest } | { ok: false; error: string } {
    if (!body || typeof body !== "object") {
        return { ok: false, error: "Request body must be a JSON object" };
    }

    const b = body as Record<string, unknown>;

    if (!isValidAddress(b.airdropAddress)) {
        return { ok: false, error: "Invalid airdropAddress" };
    }

    if (!isValidAddress(b.receiver)) {
        return { ok: false, error: "Invalid receiver address" };
    }

    if (!isValidProof(b.proof)) {
        return {
            ok: false,
            error: "Invalid proof structure",
        };
    }

    const proof = b.proof as SemaphoreProof;

    const expectedMessage = BigInt(b.receiver as string).toString();
    if (proof.message !== expectedMessage) {
        return {
            ok: false,
            error: "Proof message does not match receiver address",
        };
    }

    return {
        ok: true,
        data: {
            airdropAddress: b.airdropAddress as string,
            receiver: b.receiver as string,
            proof,
        },
    };
}
