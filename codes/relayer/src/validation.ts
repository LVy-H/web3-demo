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

export interface ApprovalVoteRequest {
    pollAddress: string;
    bitmask: number;
    proof: SemaphoreProof;
}

export interface RankedVoteRequest {
    pollAddress: string;
    packedRanking: number;
    proof: SemaphoreProof;
}

export interface QuadraticVoteRequest {
    pollAddress: string;
    packedAlloc: number;
    proof: SemaphoreProof;
}

export interface SurveyVoteRequest {
    pollAddress: string;
    // The full answer vector (one word per question, in question order). Carried
    // as decimal strings so a wide uint256 answer survives without precision loss.
    answers: string[];
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

// Mirror of the contract's MAX_OPTIONS. A JS number is exact past 32 bits
// (53-bit mantissa), so a bitmask for <=32 options round-trips safely as a
// number. See docs/superpowers/specs/2026-06-02-approval-voting-design.md.
const MAX_OPTIONS = 32;

/** Validate an APPROVAL-vote relay request. The ballot is a bitmask (bit i set
 *  ⇒ option i approved). Mirrors validateVoteRequest but for the bitmask field:
 *  rejects empty/out-of-word-range masks and binds message==bitmask, scope==poll. */
export function validateApprovalVoteRequest(
    body: unknown
): { ok: true; data: ApprovalVoteRequest } | { ok: false; error: string } {
    if (!body || typeof body !== "object") {
        return { ok: false, error: "Request body must be a JSON object" };
    }

    const b = body as Record<string, unknown>;

    if (!isValidAddress(b.pollAddress)) {
        return { ok: false, error: "Invalid pollAddress: must be a valid Ethereum address" };
    }

    // bitmask must be a positive integer that fits in MAX_OPTIONS bits.
    // 0 is an empty ballot (rejected on-chain as EmptyBallot); >= 2^MAX_OPTIONS
    // can never be a valid ballot for a <=32-option poll. The contract still
    // enforces the per-poll bound (bitmask < 2^options.length).
    if (typeof b.bitmask !== "number" || !Number.isInteger(b.bitmask)) {
        return { ok: false, error: "Invalid bitmask: must be an integer" };
    }
    if (b.bitmask <= 0) {
        return { ok: false, error: "Invalid bitmask: must be > 0 (empty ballot is not allowed)" };
    }
    if (b.bitmask >= 2 ** MAX_OPTIONS) {
        return { ok: false, error: `Invalid bitmask: must fit in ${MAX_OPTIONS} bits` };
    }

    if (!isValidProof(b.proof)) {
        return {
            ok: false,
            error: "Invalid proof: must include merkleTreeDepth, merkleTreeRoot, nullifier, message, scope, and points (array of 8 strings)",
        };
    }

    const proof = b.proof as SemaphoreProof;

    if (proof.message !== String(b.bitmask)) {
        return {
            ok: false,
            error: `Proof message (${proof.message}) does not match bitmask (${b.bitmask})`,
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
            bitmask: b.bitmask as number,
            proof,
        },
    };
}

// Max packed-ranking value (exclusive). A ranked ballot packs up to 8 rank
// slots of 4 bits each ⇒ 32 bits ⇒ valid range is [1, 2^32). The contract
// re-validates the slot structure (prefix/distinct/in-range/no-gap); the relayer
// only fast-rejects empty / out-of-word-range values and binds message+scope.
// See docs/superpowers/specs/2026-06-02-ranked-choice-design.md.
const MAX_PACKED_RANKING = 2 ** 32;

/** Validate a RANKED-vote relay request. The ballot is a packed ranking (4-bit
 *  rank slots in the low 32 bits). Mirrors validateApprovalVoteRequest but for
 *  the packedRanking field: rejects empty/out-of-32-bit-range values and binds
 *  message==packedRanking, scope==poll. The contract owns slot-structure
 *  validation (gap/dupe/range) and the off-chain IRV owns the winner. */
export function validateRankedVoteRequest(
    body: unknown
): { ok: true; data: RankedVoteRequest } | { ok: false; error: string } {
    if (!body || typeof body !== "object") {
        return { ok: false, error: "Request body must be a JSON object" };
    }

    const b = body as Record<string, unknown>;

    if (!isValidAddress(b.pollAddress)) {
        return { ok: false, error: "Invalid pollAddress: must be a valid Ethereum address" };
    }

    // packedRanking must be a positive integer that fits in 32 bits. 0 is an
    // empty ballot (rejected on-chain as EmptyBallot); >= 2^32 can never be a
    // valid packed ranking. The contract still enforces the per-poll slot rules.
    if (typeof b.packedRanking !== "number" || !Number.isInteger(b.packedRanking)) {
        return { ok: false, error: "Invalid packedRanking: must be an integer" };
    }
    if (b.packedRanking <= 0) {
        return { ok: false, error: "Invalid packedRanking: must be > 0 (empty ballot is not allowed)" };
    }
    if (b.packedRanking >= MAX_PACKED_RANKING) {
        return { ok: false, error: "Invalid packedRanking: must fit in 32 bits (< 2^32)" };
    }

    if (!isValidProof(b.proof)) {
        return {
            ok: false,
            error: "Invalid proof: must include merkleTreeDepth, merkleTreeRoot, nullifier, message, scope, and points (array of 8 strings)",
        };
    }

    const proof = b.proof as SemaphoreProof;

    if (proof.message !== String(b.packedRanking)) {
        return {
            ok: false,
            error: `Proof message (${proof.message}) does not match packedRanking (${b.packedRanking})`,
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
            packedRanking: b.packedRanking as number,
            proof,
        },
    };
}

// Max packed-allocation value (exclusive). A quadratic ballot packs up to 8
// allocation slots of 4 bits each ⇒ 32 bits ⇒ valid range is [1, 2^32). The
// contract owns the quadratic budget (Σvᵢ² ≤ CREDITS), the ghost-slot rule, and
// the high-bits guard; the relayer only fast-rejects empty / out-of-word-range
// values and binds message+scope. We do NOT reimplement the budget here —
// duplicating that math is a divergence risk and the contract is authoritative.
// See docs/superpowers/specs/2026-06-03-quadratic-voting-design.md.
const MAX_PACKED_ALLOC = 2 ** 32;

/** Validate a QUADRATIC-vote relay request. The ballot is a packed allocation
 *  (4-bit vote-count slots in the low 32 bits). Mirrors validateRankedVoteRequest
 *  but for the packedAlloc field: rejects empty/out-of-32-bit-range values and
 *  binds message==packedAlloc, scope==poll. The contract owns the budget
 *  (Σvᵢ² ≤ CREDITS) and ghost-slot/structure validation. */
export function validateQuadraticVoteRequest(
    body: unknown
): { ok: true; data: QuadraticVoteRequest } | { ok: false; error: string } {
    if (!body || typeof body !== "object") {
        return { ok: false, error: "Request body must be a JSON object" };
    }

    const b = body as Record<string, unknown>;

    if (!isValidAddress(b.pollAddress)) {
        return { ok: false, error: "Invalid pollAddress: must be a valid Ethereum address" };
    }

    // packedAlloc must be a positive integer that fits in 32 bits. 0 is an empty
    // ballot (rejected on-chain as EmptyBallot); >= 2^32 can never be a valid
    // packed allocation. The contract still enforces the per-poll budget + rules.
    if (typeof b.packedAlloc !== "number" || !Number.isInteger(b.packedAlloc)) {
        return { ok: false, error: "Invalid packedAlloc: must be an integer" };
    }
    if (b.packedAlloc <= 0) {
        return { ok: false, error: "Invalid packedAlloc: must be > 0 (empty ballot is not allowed)" };
    }
    if (b.packedAlloc >= MAX_PACKED_ALLOC) {
        return { ok: false, error: "Invalid packedAlloc: must fit in 32 bits (< 2^32)" };
    }

    if (!isValidProof(b.proof)) {
        return {
            ok: false,
            error: "Invalid proof: must include merkleTreeDepth, merkleTreeRoot, nullifier, message, scope, and points (array of 8 strings)",
        };
    }

    const proof = b.proof as SemaphoreProof;

    if (proof.message !== String(b.packedAlloc)) {
        return {
            ok: false,
            error: `Proof message (${proof.message}) does not match packedAlloc (${b.packedAlloc})`,
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
            packedAlloc: b.packedAlloc as number,
            proof,
        },
    };
}

// The BN254 scalar field order r. A Semaphore `message` is a field element, so a
// well-formed message is in [0, r). For the survey module the message is a
// keccak COMMITMENT — `keccak256(abi.encode(answers)) >> 8`, a 248-bit value that
// is always < r — so the relayer's only message check is a SHAPE check against
// this bound (see validateSurveyVoteRequest).
const BN254_FIELD_ORDER =
    21888242871839275222246405745257275088548364400416034343698204186575808495617n;

// Mirror of the contract's MAX_QUESTIONS. A survey ballot is one answer word per
// question, capped on-chain at 16 questions. The relayer fast-rejects an
// obviously-oversized vector; the contract re-checks `answers.length ==
// questions.length` for the specific poll.
const MAX_QUESTIONS = 16;

// 2^256 (exclusive upper bound for a uint256 answer word). Each answer must fit
// in one EVM word; the contract owns the per-question semantic validation (option
// index < optionCount, bitmask in range) — the relayer only checks the word range.
const MAX_UINT256 = 1n << 256n;

/** Parse one answer-vector element into a non-negative uint256-range BigInt, or
 *  return null if it is not a valid integer word. Accepts a decimal string or a
 *  JS number (must be a non-negative safe integer). Rejects negatives,
 *  non-integers, hex/garbage strings, and values >= 2^256. */
function parseAnswerWord(v: unknown): bigint | null {
    let n: bigint;
    if (typeof v === "number") {
        if (!Number.isInteger(v) || v < 0) return null;
        n = BigInt(v);
    } else if (typeof v === "string") {
        // Decimal digits only — no hex, no sign, no whitespace, no empty string.
        if (!/^\d+$/.test(v)) return null;
        n = BigInt(v);
    } else {
        return null;
    }
    if (n < 0n || n >= MAX_UINT256) return null;
    return n;
}

/** Validate a SURVEY-vote relay request. The ballot is the FULL answer vector
 *  (`answers`: one uint256 word per question, in question order) plus one proof.
 *
 *  CRITICAL difference from the other modules — the relayer does NOT bind
 *  `message` to the ballot. Every sibling validator checks
 *  `proof.message === String(<single ballot value>)` because their ballot IS the
 *  Semaphore message. Survey is different: the message is a keccak COMMITMENT,
 *  `message = keccak256(abi.encode(answers)) >> 8` — a wide field element the
 *  CONTRACT recomputes from calldata and binds (TamperedVoteSignal on mismatch).
 *  The relayer MUST NOT re-derive that commitment: re-implementing the
 *  abi.encode + keccak + >>8 in JS risks a Dart/JS/Solidity mismatch, and it is
 *  not the relayer's job to own it. So the message check here is SHAPE-ONLY: a
 *  non-zero field element (> 0 and < BN254 r) — NOT `=== String(answers)`. The
 *  `answers` vector is validated for word-range only (non-empty, each a
 *  uint256-range decimal); the contract owns per-question semantic validation. */
export function validateSurveyVoteRequest(
    body: unknown
): { ok: true; data: SurveyVoteRequest } | { ok: false; error: string } {
    if (!body || typeof body !== "object") {
        return { ok: false, error: "Request body must be a JSON object" };
    }

    const b = body as Record<string, unknown>;

    if (!isValidAddress(b.pollAddress)) {
        return { ok: false, error: "Invalid pollAddress: must be a valid Ethereum address" };
    }

    // answers must be a non-empty array of uint256-range integer words, one per
    // question. The contract enforces the per-poll length (== questions.length)
    // and the per-question semantics; the relayer fast-rejects empty / oversized
    // vectors and non-integer words. We do NOT bind answers to the message.
    if (!Array.isArray(b.answers)) {
        return { ok: false, error: "Invalid answers: must be an array" };
    }
    if (b.answers.length === 0) {
        return { ok: false, error: "Invalid answers: must be a non-empty array" };
    }
    if (b.answers.length > MAX_QUESTIONS) {
        return { ok: false, error: `Invalid answers: at most ${MAX_QUESTIONS} questions` };
    }
    const answers: string[] = [];
    for (let i = 0; i < b.answers.length; i++) {
        const word = parseAnswerWord(b.answers[i]);
        if (word === null) {
            return {
                ok: false,
                error: `Invalid answer at index ${i}: must be a non-negative integer < 2^256`,
            };
        }
        answers.push(word.toString());
    }

    if (!isValidProof(b.proof)) {
        return {
            ok: false,
            error: "Invalid proof: must include merkleTreeDepth, merkleTreeRoot, nullifier, message, scope, and points (array of 8 strings)",
        };
    }

    const proof = b.proof as SemaphoreProof;

    // SHAPE-ONLY message check (see the function doc): the message is a keccak
    // commitment the CONTRACT recomputes and binds — the relayer only checks it is
    // a non-zero in-field element. A "0" message can never be a valid commitment;
    // a wide non-zero value (a real commitment) is ACCEPTED unchanged. We do NOT
    // require `message === String(answers)`.
    let messageBig: bigint;
    try {
        messageBig = BigInt(proof.message);
    } catch {
        return { ok: false, error: "Invalid proof message: must be a decimal field element" };
    }
    if (messageBig <= 0n || messageBig >= BN254_FIELD_ORDER) {
        return {
            ok: false,
            error: "Invalid proof message: must be a non-zero field element (< BN254 r)",
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
            answers,
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
