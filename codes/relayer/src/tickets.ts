/**
 * Live Meeting Vote — pending-voter queue + ticket endpoints (S1.2).
 *
 * Provides the coordination channel between the wallet-free voter page and the
 * organizer's host dashboard, plus single-use ticket tracking. All state is
 * IN-MEMORY and per-poll — it is lost on relayer restart (acceptable for a
 * single live meeting; documented as a trade-off in README, open-Q3).
 *
 * Endpoints (mounted under /api/relay/tickets, behind the existing rate limiter):
 *   POST /issue    { pollId, orgPubKey }                     → register the org verification anchor
 *   POST /pending  { pollId, ticket, ephemeralIdentityCommitment, confirmationCode }
 *                                                            → voter announces itself (fresh ticket required)
 *   GET  /queue?pollId=…                                     → organizer dashboard reads pending voters
 *   POST /redeem   { pollId, ticket }                        → organizer confirms; ticket marked consumed (once)
 *
 * NOTE: registration on-chain is the ORGANIZER'S WALLET's job (registerVoter is
 * onlyOwner). The relayer never registers voters — redeem only blesses the
 * ticket as consumed. This overrides the original design doc's /relay/register.
 */
import { Router, type Request, type Response } from "express";
import { ethers } from "ethers";
import { verifyTicket, verifyTicketSignature, decodeTicket } from "./ticket";

export type PendingStatus = "pending" | "confirmed" | "rejected";

export interface PendingVoter {
    ticketNonce: string;
    ephemeralIdentityCommitment: string;
    confirmationCode: string;
    status: PendingStatus;
    createdAt: number;
}

interface PollTicketState {
    orgPubKey?: string;
    queue: PendingVoter[];
    consumed: Set<string>; // keys: `${pollIdLower}:${nonce}`
}

const store = new Map<string, PollTicketState>();

function stateFor(pollId: string): PollTicketState {
    const key = pollId.toLowerCase();
    let s = store.get(key);
    if (!s) {
        s = { queue: [], consumed: new Set() };
        store.set(key, s);
    }
    return s;
}

function consumedKey(pollId: string, nonce: string): string {
    return `${pollId.toLowerCase()}:${nonce}`;
}

/** Test helper: wipe all in-memory ticket state. */
export function __resetTicketStore(): void {
    store.clear();
}

// ── Validators (mirror validation.ts: { ok, data } | { ok, error }) ──────────

type Valid<T> = { ok: true; data: T } | { ok: false; error: string };

function isAddress(a: unknown): a is string {
    return typeof a === "string" && ethers.isAddress(a);
}

function isHexOfLen(s: unknown, len: number): s is string {
    return typeof s === "string" && new RegExp(`^[0-9a-fA-F]{${len}}$`).test(s);
}

function isDecimalString(s: unknown): s is string {
    return typeof s === "string" && /^[0-9]+$/.test(s);
}

export function validateIssueRequest(
    body: unknown
): Valid<{ pollId: string; orgPubKey: string }> {
    if (!body || typeof body !== "object") return { ok: false, error: "Body must be a JSON object" };
    const b = body as Record<string, unknown>;
    if (!isAddress(b.pollId)) return { ok: false, error: "Invalid pollId" };
    if (!isHexOfLen(b.orgPubKey, 64)) return { ok: false, error: "Invalid orgPubKey: 32-byte hex expected" };
    return { ok: true, data: { pollId: b.pollId, orgPubKey: b.orgPubKey } };
}

export function validatePendingRequest(
    body: unknown
): Valid<{ pollId: string; ticket: string; ephemeralIdentityCommitment: string; confirmationCode: string }> {
    if (!body || typeof body !== "object") return { ok: false, error: "Body must be a JSON object" };
    const b = body as Record<string, unknown>;
    if (!isAddress(b.pollId)) return { ok: false, error: "Invalid pollId" };
    if (typeof b.ticket !== "string" || b.ticket.length === 0) return { ok: false, error: "Invalid ticket" };
    if (!isDecimalString(b.ephemeralIdentityCommitment)) {
        return { ok: false, error: "Invalid ephemeralIdentityCommitment: decimal string expected" };
    }
    if (typeof b.confirmationCode !== "string" || !/^[0-9]{4}$/.test(b.confirmationCode)) {
        return { ok: false, error: "Invalid confirmationCode: 4 digits expected" };
    }
    return {
        ok: true,
        data: {
            pollId: b.pollId,
            ticket: b.ticket,
            ephemeralIdentityCommitment: b.ephemeralIdentityCommitment,
            confirmationCode: b.confirmationCode,
        },
    };
}

export function validateRedeemRequest(body: unknown): Valid<{ pollId: string; ticket: string }> {
    if (!body || typeof body !== "object") return { ok: false, error: "Body must be a JSON object" };
    const b = body as Record<string, unknown>;
    if (!isAddress(b.pollId)) return { ok: false, error: "Invalid pollId" };
    if (typeof b.ticket !== "string" || b.ticket.length === 0) return { ok: false, error: "Invalid ticket" };
    return { ok: true, data: { pollId: b.pollId, ticket: b.ticket } };
}

// ── Route handlers ───────────────────────────────────────────────────────────

function handleIssue(req: Request, res: Response): void {
    const v = validateIssueRequest(req.body);
    if (!v.ok) {
        res.status(400).json({ error: v.error });
        return;
    }
    stateFor(v.data.pollId).orgPubKey = v.data.orgPubKey;
    console.log(`[TICKETS] issue → poll=${v.data.pollId} registered org pubkey`);
    res.json({ success: true });
}

function handlePending(req: Request, res: Response): void {
    const v = validatePendingRequest(req.body);
    if (!v.ok) {
        res.status(400).json({ error: v.error });
        return;
    }
    const { pollId, ticket, ephemeralIdentityCommitment, confirmationCode } = v.data;
    const s = stateFor(pollId);
    if (!s.orgPubKey) {
        res.status(400).json({ error: "Poll not initialized — organizer must /issue first" });
        return;
    }

    let nonce: string;
    try {
        nonce = decodeTicket(ticket).n;
    } catch {
        res.status(400).json({ error: "Malformed ticket" });
        return;
    }
    if (s.consumed.has(consumedKey(pollId, nonce))) {
        res.status(409).json({ error: "Ticket already redeemed" });
        return;
    }

    const result = verifyTicket(ticket, s.orgPubKey);
    if (!result.valid) {
        res.status(400).json({ error: `Ticket rejected: ${result.reason}` });
        return;
    }

    // Upsert by nonce: a re-scan with a fresh ticket creates a new row; the same
    // ticket re-POSTed just refreshes the existing row.
    const existing = s.queue.find((q) => q.ticketNonce === nonce);
    if (existing) {
        existing.ephemeralIdentityCommitment = ephemeralIdentityCommitment;
        existing.confirmationCode = confirmationCode;
        existing.status = "pending";
    } else {
        s.queue.push({
            ticketNonce: nonce,
            ephemeralIdentityCommitment,
            confirmationCode,
            status: "pending",
            createdAt: Math.floor(Date.now() / 1000),
        });
    }
    console.log(`[TICKETS] pending → poll=${pollId} code=${confirmationCode}`);
    res.json({ success: true, status: "pending", confirmationCode });
}

function handleQueue(req: Request, res: Response): void {
    const pollId = req.query.pollId;
    if (!isAddress(pollId)) {
        res.status(400).json({ error: "Invalid or missing pollId" });
        return;
    }
    const s = stateFor(pollId);
    res.json({ pollId, voters: s.queue.filter((q) => q.status === "pending") });
}

function handleRedeem(req: Request, res: Response): void {
    const v = validateRedeemRequest(req.body);
    if (!v.ok) {
        res.status(400).json({ error: v.error });
        return;
    }
    const { pollId, ticket } = v.data;
    const s = stateFor(pollId);
    if (!s.orgPubKey) {
        res.status(400).json({ error: "Poll not initialized — organizer must /issue first" });
        return;
    }

    let nonce: string;
    try {
        nonce = decodeTicket(ticket).n;
    } catch {
        res.status(400).json({ error: "Malformed ticket" });
        return;
    }

    const key = consumedKey(pollId, nonce);
    if (s.consumed.has(key)) {
        res.status(409).json({ error: "Ticket already redeemed" });
        return;
    }
    // Signature-only (expiry may have lapsed during the face-to-face confirm).
    if (!verifyTicketSignature(ticket, s.orgPubKey)) {
        res.status(400).json({ error: "Ticket rejected: badSig" });
        return;
    }

    s.consumed.add(key);
    const entry = s.queue.find((q) => q.ticketNonce === nonce);
    if (entry) entry.status = "confirmed";
    console.log(`[TICKETS] redeem → poll=${pollId} nonce=${nonce} consumed`);
    res.json({ success: true });
}

/** Build the ticket router. Mount under /api/relay/tickets (behind the limiter). */
export function createTicketRouter(): Router {
    const router = Router();
    router.post("/issue", handleIssue);
    router.post("/pending", handlePending);
    router.get("/queue", handleQueue);
    router.post("/redeem", handleRedeem);
    return router;
}
