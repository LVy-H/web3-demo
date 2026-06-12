// Unit tests for the rate-limit env overrides (RELAY_RATE_LIMIT_MAX /
// RELAY_RATE_LIMIT_WINDOW_MS). `config` is a frozen snapshot taken at module
// import, so each case resets the module registry and re-imports to observe
// the env at import time. setup.ts already provides RELAYER_PRIVATE_KEY.
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

const ENV_KEYS = ["RELAY_RATE_LIMIT_MAX", "RELAY_RATE_LIMIT_WINDOW_MS"] as const;
const saved: Record<string, string | undefined> = {};

async function freshConfig() {
    vi.resetModules();
    return (await import("../src/config")).config;
}

describe("config rate-limit env overrides", () => {
    beforeEach(() => {
        for (const k of ENV_KEYS) {
            saved[k] = process.env[k];
            delete process.env[k];
        }
    });

    afterEach(() => {
        for (const k of ENV_KEYS) {
            if (saved[k] === undefined) delete process.env[k];
            else process.env[k] = saved[k];
        }
        vi.resetModules();
    });

    it("defaults to 20 req / 60s when env vars are unset (production default)", async () => {
        const config = await freshConfig();
        expect(config.rateLimitMax).toBe(20);
        expect(config.rateLimitWindowMs).toBe(60_000);
    });

    it("RELAY_RATE_LIMIT_MAX overrides the request cap", async () => {
        process.env.RELAY_RATE_LIMIT_MAX = "600";
        const config = await freshConfig();
        expect(config.rateLimitMax).toBe(600);
        expect(config.rateLimitWindowMs).toBe(60_000); // window untouched
    });

    it("RELAY_RATE_LIMIT_WINDOW_MS overrides the window", async () => {
        process.env.RELAY_RATE_LIMIT_WINDOW_MS = "1000";
        const config = await freshConfig();
        expect(config.rateLimitWindowMs).toBe(1_000);
        expect(config.rateLimitMax).toBe(20); // cap untouched
    });

    it("falls back to defaults on non-numeric or zero values", async () => {
        process.env.RELAY_RATE_LIMIT_MAX = "not-a-number";
        process.env.RELAY_RATE_LIMIT_WINDOW_MS = "0";
        const config = await freshConfig();
        expect(config.rateLimitMax).toBe(20);
        expect(config.rateLimitWindowMs).toBe(60_000);
    });
});
